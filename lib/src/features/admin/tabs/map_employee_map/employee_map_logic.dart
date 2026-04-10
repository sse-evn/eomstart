import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart' show AppConfig;
import 'package:micro_mobility_app/src/features/app/models/location.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class EmployeeMapLogic {
  LatLng? currentLocation;
  bool isLoading = true;
  bool _disposed = false;
  late MapController mapController;
  void Function()? onStateChanged;

  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  List<EmployeeLocation> employeeLocations = [];
  String? currentUserAvatarUrl;

  // История
  final Map<String, List<EmployeeLocation>> _cachedHistories = {};
  List<LatLng> selectedEmployeeHistory = [];
  String? selectedEmployeeId;
  String? selectedEmployeeName;
  DateTimeRange? selectedHistoryRange;

  FMTCTileProvider? tileProvider;
  Timer? _liveTrackingTimer;

  final GeoJsonParser geoJsonParser = GeoJsonParser();
  bool showRestrictedZones = true;
  bool showBoundaries = true;
  bool showParkingZones = true;
  bool showSpeedLimitZones = true;
  Map<String, String> _userNameCache = {};
  String _formatDateWithTimezone(DateTime dt) {
    final local = dt.toLocal(); // Убедиться что локальная TZ применена
    final offset = local.timeZoneOffset;

    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    final formattedOffset = '$sign$hours:$minutes';

    // Убираем миллисекунды, чтобы не ломать сервер Go
    final base = local.toIso8601String().split('.').first;

    return '$base$formattedOffset';
  }

  EmployeeMapLogic() {
    mapController = MapController();
  }

  void _notify() {
    if (_disposed || onStateChanged == null) return;
    onStateChanged!();
  }

  Future<void> _fetchCurrentLocation() async {
    if (_disposed) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Служба геолокации отключена.');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Доступ к геолокации запрещён.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Доступ запрещён навсегда. Измените в настройках.');
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        currentLocation = LatLng(position.latitude, position.longitude);
        _notify();
      }
    } catch (e) {
      debugPrint('Ошибка получения местоположения: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    if (_disposed) return;
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token != null) {
        final profile = await _apiService.getUserProfile(token);
        currentUserAvatarUrl = profile['avatarUrl'] as String?;
        _notify();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    }
  }

  Future<void> _loadUserNameCache() async {
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;
      final users = await _apiService.getAdminUsers(token);
      final Map<String, String> cache = {};
      for (var u in users) {
        if (u is Map) {
          final id = u['id']?.toString();
          final firstName = u['first_name']?.toString();
          final username = u['username']?.toString();
          if (id != null) {
            cache[id] = (firstName != null && firstName.isNotEmpty) ? firstName : (username ?? 'ID $id');
          }
        }
      }
      _userNameCache = cache;
    } catch (e) {
      debugPrint('Ошибка загрузки кэша имен: $e');
    }
  }

  Future<void> _loadAndParseGeoJson() async {
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;

      // Пытаемся взять последнюю выбранную карту из MapLogic (если сохранена в storage)
      final savedId = await storage.read(key: 'selected_map_id_cache');
      final mapId = int.tryParse(savedId ?? '') ?? -1;

      if (mapId == -1) return;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/map_$mapId.geojson');

      String content = '';
      if (await file.exists()) {
        content = await file.readAsString();
      }

      if (content.isEmpty) {
        // Если нет локальной, пробуем скачать (минимум логики из MapLogic)
        final metaResponse = await http.get(
          Uri.parse(AppConfig.getMapByIdUrl(mapId)),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (metaResponse.statusCode == 200) {
          final meta = jsonDecode(metaResponse.body);
          final fileUrl = AppConfig.getMapFileUrl(meta['file_name']);
          final fileRes = await http.get(
            Uri.parse(fileUrl),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (fileRes.statusCode == 200) {
            content = fileRes.body;
            await file.writeAsString(content);
          }
        }
      }

      if (content.isNotEmpty) {
        geoJsonParser.parseGeoJsonAsString(content);
        _notify();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки зон на админ-карте: $e');
    }
  }

  Future<void> fetchEmployeeLocations() async {
    if (_disposed) return;
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;

      final decoded = await _apiService.getLastLocations(token);
      
      employeeLocations = decoded
          .map((item) {
            if (item is! Map<String, dynamic>) return null;
            final id = item['user_id']?.toString() ?? 'unknown';
            final lat = (item['lat'] as num?)?.toDouble();
            final lon = (item['lon'] as num?)?.toDouble();
            if (lat == null || lon == null) return null;

            String? name = item['name']?.toString();
            if (name == null || name.isEmpty || name.contains('Сотрудник')) {
              name = _userNameCache[id];
            }

            return EmployeeLocation(
              userId: id,
              name: name,
              position: LatLng(lat, lon),
              battery: item['battery'] is num
                  ? (item['battery'] as num).toDouble()
                  : null,
              timestamp: DateTime.tryParse(item['ts']?.toString() ?? '') ??
                  DateTime.now(),
              avatarUrl: item['avatarUrl']?.toString(),
            );
          })
          .whereType<EmployeeLocation>()
          .toList();
      _notify();
    } catch (e) {
      debugPrint('Ошибка загрузки позиций сотрудников: $e');
      employeeLocations = [];
      _notify();
    }
  }

  void startLiveTracking() {
    stopLiveTracking();
    _liveTrackingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_disposed) return;
      fetchEmployeeLocations();
    });
  }

  void stopLiveTracking() {
    _liveTrackingTimer?.cancel();
    _liveTrackingTimer = null;
  }

  Future<void> loadEmployeeHistory(String userId,
      {DateTimeRange? range}) async {
    if (_disposed) return;

    selectedEmployeeId = userId;
    selectedHistoryRange = range;

    final effectiveRange = range ?? _getDefaultRange();

    // Форматирование дат
    final fromStr = _formatDateWithTimezone(effectiveRange.start);
    final toStr = _formatDateWithTimezone(effectiveRange.end);

    final cacheKey = "$userId|$fromStr|$toStr";

    if (_cachedHistories.containsKey(cacheKey)) {
      final cached = _cachedHistories[cacheKey]!;
      selectedEmployeeHistory = cached.map((e) => e.position).toList();
      _notify();
      return;
    }

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;

      final points = await _apiService.getLocationHistory(token, userId, fromStr, toStr);

      if (points.isNotEmpty) {
        final gpsPoints = points
            .map((item) {
              if (item is! Map<String, dynamic>) return null;
              final lat = (item['lat'] as num?)?.toDouble();
              final lon = (item['lon'] as num?)?.toDouble();
              if (lat == null || lon == null) return null;
              return LatLng(lat, lon);
            })
            .whereType<LatLng>()
            .toList();

        _cachedHistories[cacheKey] = points
            .map((item) {
              final map = item as Map<String, dynamic>;
              final lat = (map['lat'] as num?)?.toDouble() ?? 0.0;
              final lon = (map['lon'] as num?)?.toDouble() ?? 0.0;
              return EmployeeLocation(
                userId: userId,
                name: map['name']?.toString(),
                position: LatLng(lat, lon),
                battery: (map['battery'] as num?)?.toDouble(),
                timestamp:
                    DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
                        DateTime.now(),
                avatarUrl: map['avatarUrl']?.toString(),
              );
            })
            .whereType<EmployeeLocation>()
            .toList();

        selectedEmployeeHistory = _smoothPolyline(gpsPoints);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки истории: $e');
    }

    _notify();
  }

  DateTimeRange _getDefaultRange() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return DateTimeRange(start: startOfDay, end: endOfDay);
  }

  List<LatLng> _smoothPolyline(List<LatLng> points) {
    if (points.length < 3) return points;
    final smoothed = <LatLng>[points.first];
    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final current = points[i];
      final next = points[i + 1];
      final avgLat = (prev.latitude + current.latitude + next.latitude) / 3;
      final avgLon = (prev.longitude + current.longitude + next.longitude) / 3;
      smoothed.add(LatLng(avgLat, avgLon));
    }
    smoothed.add(points.last);
    return smoothed;
  }

  void clearHistory() {
    selectedEmployeeHistory = [];
    selectedEmployeeId = null;
    selectedEmployeeName = null;
    selectedHistoryRange = null;
    _notify();
  }

  Future<void> initMap() async {
    if (_disposed) return;
    isLoading = true;
    _notify();

    // FMTC Store Initialization
    const storeName = 'mapStore';
    final store = const FMTCStore(storeName);
    if (!(await store.manage.ready)) {
      await store.manage.create();
    }
    tileProvider = FMTCTileProvider(
      stores: const {storeName: BrowseStoreStrategy.readUpdateCreate},
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
    );

    await _fetchCurrentLocation();
    await _loadUserProfile();
    await _loadUserNameCache();
    await _loadAndParseGeoJson();
    await fetchEmployeeLocations();
    if (!_disposed) {
      isLoading = false;
      _notify();
    }
  }

  void init() {
    if (_disposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        initMap();
        startLiveTracking();
      }
    });
  }

  void dispose() {
    _disposed = true;
    stopLiveTracking();
    mapController.dispose();
  }
}
