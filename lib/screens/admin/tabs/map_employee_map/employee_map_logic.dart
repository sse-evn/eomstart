import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:micro_mobility_app/config/app_config.dart' show AppConfig;
import 'package:micro_mobility_app/models/location.dart';

class EmployeeMapLogic {
  LatLng? currentLocation;
  bool isLoading = true;
  bool _disposed = false;
  late MapController mapController;
  void Function()? onStateChanged;

  final FlutterSecureStorage storage = const FlutterSecureStorage();
  List<EmployeeLocation> employeeLocations = [];
  String? currentUserAvatarUrl;
  List<LatLng> selectedEmployeeHistory = [];
  String? selectedEmployeeId;
  String? selectedEmployeeName;

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
      } else {
        throw Exception('Недостаточно прав для геолокации.');
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
        final response = await http.get(
          Uri.parse(AppConfig.profileUrl),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          currentUserAvatarUrl = data['avatarUrl'] as String?;
          _notify();
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    }
  }

  Future<void> fetchEmployeeLocations() async {
    if (_disposed) return;
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;

      final response = await http.get(
        Uri.parse(AppConfig.lastLocationsUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is List) {
          employeeLocations = decoded
              .map((item) {
                if (item is! Map<String, dynamic>) return null;
                return EmployeeLocation(
                  userId: item['user_id']?.toString() ?? 'unknown',
                  name: item['name']?.toString(),
                  position: LatLng(
                    (item['lat'] as num?)?.toDouble() ?? 0.0,
                    (item['lon'] as num?)?.toDouble() ?? 0.0,
                  ),
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
        } else {
          employeeLocations = [];
        }
        _notify();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки позиций сотрудников: $e');
      employeeLocations = [];
      _notify();
    }
  }

  void startLiveTracking() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_disposed) fetchEmployeeLocations();
    });
  }

  void stopLiveTracking() {}

  Future<void> loadEmployeeHistory(String userId) async {
    if (_disposed) return;
    selectedEmployeeHistory = [];
    selectedEmployeeId = userId;

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;

      final now = DateTime.now();
      final startOfDay = DateTime.utc(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final url = '${AppConfig.locationHistoryUrl}?user_id=$userId'
          '&from=${Uri.encodeComponent(startOfDay.toIso8601String())}'
          '&to=${Uri.encodeComponent(endOfDay.toIso8601String())}';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is List) {
          final gpsPoints = decoded
              .map((item) {
                if (item is! Map<String, dynamic>) return null;
                return LatLng(
                  (item['lat'] as num?)?.toDouble() ?? 0.0,
                  (item['lon'] as num?)?.toDouble() ?? 0.0,
                );
              })
              .whereType<LatLng>()
              .toList();

          selectedEmployeeHistory = _smoothPolyline(gpsPoints);
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки истории: $e');
    }

    _notify();
  }

  /// Простое сглаживание GPS-точек
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
    _notify();
  }

  Future<void> initMap() async {
    if (_disposed) return;
    try {
      isLoading = true;
      _notify();
      await _fetchCurrentLocation();
      await _loadUserProfile();
      await fetchEmployeeLocations();
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    } catch (e) {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
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
