import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart'
    show AppConfig;
import 'package:path_provider/path_provider.dart';

import '../../core/services/api_service.dart';

class MapLogic {
  final BuildContext context;
  LatLng? currentLocation;
  final GeoJsonParser geoJsonParser = GeoJsonParser();
  late final MapController mapController;
  bool isLoading = false;
  bool isLocating = false; // Флаг для индикатора загрузки геопозиции
  List<dynamic> availableMaps = [];
  int selectedMapId = -1;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  bool showRestrictedZones = true;
  bool showParkingZones = true;
  bool showSpeedLimitZones = true;
  bool showBoundaries = true;
  bool isMapLoadedOffline = false;
  List<dynamic> otherScoutsLocations = [];
  Timer? _trackingTimer;
  final ApiService _apiService = ApiService();
  bool _disposed = false;
  void Function()? onStateChanged;

  // FMTC tile provider — теперь nullable
  FMTCTileProvider? tileProvider;

  // Для отслеживания, были ли тайлы предзагружены
  final bool _tilesPrefetched = false;

  String? currentUserAvatarUrl;

  /// Хранилище свойств полигонов (зон), так как GeoJsonParser 1.0.8 не отдает их напрямую
  final List<Map<String, dynamic>> _polygonProperties = [];

  static const String _MAPS_CACHE_KEY = 'cached_maps_list';
  static const String _MAPS_CACHE_TIMESTAMP_KEY = 'cached_maps_list_timestamp';
  static const String _SELECTED_MAP_ID_KEY = 'selected_map_id_cache';
  static const Duration _CACHE_TTL = Duration(minutes: 10);

  MapLogic(this.context, {String? initialAvatarUrl}) {
    mapController = MapController();

    // Настраиваем кастомный билдер маркеров для зон
    geoJsonParser.markerCreationCallback = _customMarkerBuilder;

    // Перехватываем создание полигонов, чтобы сохранить их свойства (метаданные)
    geoJsonParser.polygonCreationCallback = (points, holePoints, properties) {
      _polygonProperties.add(properties);
      return Polygon(
        points: points,
        holePointsList: holePoints,
        borderColor: Colors.red,
        color: Colors.red.withOpacity(0.2),
        borderStrokeWidth: 2.0,
      );
    };

    if (initialAvatarUrl != null) {
      updateAvatarUrl(initialAvatarUrl);
    }
  }

  Marker _customMarkerBuilder(LatLng point, Map<String, dynamic> properties) {
    String label = properties['description']?.toString() ??
        properties['iconContent']?.toString() ??
        properties['name']?.toString() ??
        '';

    // Если это "ГРАНИЦА", рисуем маленькую точку без текста
    if (label.toUpperCase() == 'ГРАНИЦА') {
      return Marker(
        point: point,
        width: 10,
        height: 10,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    // Специальные иконки для некоторых типов объектов
    IconData? specialIcon;
    Color? iconColor;
    if (label.contains('Парковка')) {
      specialIcon = Icons.local_parking_rounded;
      iconColor = Colors.blue;
    } else if (label.contains('Ремонт')) {
      specialIcon = Icons.build_rounded;
      iconColor = Colors.orange;
    }

    return Marker(
      point: point,
      width: label.length > 10 ? 100 : 60,
      height: 40,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (specialIcon != null)
              Icon(specialIcon, color: iconColor, size: 20),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [
                  Shadow(
                    blurRadius: 6.0,
                    color: Colors.black,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void updateAvatarUrl(String url) {
    if (url.isEmpty) return;

    if (url.startsWith('http')) {
      currentUserAvatarUrl = url;
    } else {
      final baseUrl = AppConfig.mediaBaseUrl;
      // Убираем лишние слеши при конкатенации
      final cleanUrl = url.startsWith('/') ? url : '/$url';
      currentUserAvatarUrl = baseUrl.endsWith('/')
          ? '$baseUrl${cleanUrl.substring(1)}'
          : '$baseUrl$cleanUrl';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed && onStateChanged != null) {
      onStateChanged!();
    }
  }

  void init() async {
    if (_disposed) return;

    await _initCaching(); // Теперь дожидаемся завершения

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        _initMap();
        _startTrackingTimer();
      }
    });
  }

  Future<void> _initCaching() async {
    const storeName = 'mapStore';
    final store = const FMTCStore(storeName);
    if (!(await store.manage.ready)) {
      await store.manage.create();
    }

    tileProvider = FMTCTileProvider(
      stores: const {
        storeName: BrowseStoreStrategy.readUpdateCreate,
      },
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
    );

    _notify(); // Важно: уведомить UI, что tileProvider готов
  }

  void dispose() {
    _disposed = true;
    _trackingTimer?.cancel();
    mapController.dispose();
  }

  Future<void> _initMap() async {
    if (_disposed) return;
    try {
      isLoading = true;
      _notify();

      // Запускаем гео в фоне, не дожидаясь (чтобы не блокировать карту)
      fetchCurrentLocation();

      // Загружаем основные данные параллельно
      await Future.wait([
        _loadSavedMapId(),
        _loadAvailableMaps(),
      ]);

      await _loadAndParseGeoJson();
    } catch (e) {
      _showErrorSnackBar('Ошибка инициализации: $e');
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  // Future<void> _prefetchTilesIfNeeded() async {
  //   if (_tilesPrefetched || tileProvider == null || currentLocation == null) {
  //     return;
  //   }

  //   try {
  //     debugPrint('🔄 Предзагрузка тайлов для офлайн-режима...');
  //     await tileProvider!.prefetch(
  //       center: currentLocation!,
  //       minZoom: 14,
  //       maxZoom: 17,
  //       radius: 25,
  //     );
  //     _tilesPrefetched = true;
  //     debugPrint('✅ Тайлы успешно закэшированы');
  //   } catch (e) {
  //     debugPrint('⚠️ Не удалось предзагрузить тайлы: $e');
  //     // Не показываем ошибку пользователю — это фоновая операция
  //   }
  // }

  Future<void> _startTrackingTimer() async {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_disposed) fetchOtherScoutsLocations();
    });
    // Первый запуск сразу
    fetchOtherScoutsLocations();
  }

  Future<void> fetchOtherScoutsLocations() async {
    if (_disposed) return;
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return;

      final locations = await _apiService.getLastLocations(token);

      // Исключаем себя из списка "других", если хотим (но на бэкенде это обычно все активные)
      // Для простоты оставим всех, в UI отфильтруем или покажем как есть
      otherScoutsLocations = locations;
      _notify();
    } catch (e) {
      debugPrint('Ошибка получения локаций команды: $e');
    }
  }

  /// Флаг, чтобы центрировать карту только один раз при старте
  bool _isFirstLocationFix = true;

  Future<void> fetchCurrentLocation({bool isManual = false}) async {
    if (_disposed) return;
    try {
      if (isManual) {
        isLocating = true;
        _notify();
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (isManual)
          _showErrorSnackBar('Включите GPS для определения местоположения');
        if (isManual) {
          isLocating = false;
          _notify();
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (isManual)
            _showErrorSnackBar('Нет разрешения на доступ к геопозиции');
          if (isManual) {
            isLocating = false;
            _notify();
          }
          return;
        }
      }

      // 🚀 Последнее известное положение
      Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        currentLocation = LatLng(lastPosition.latitude, lastPosition.longitude);
        if (_isFirstLocationFix || isManual) {
          final targetZoom =
              mapController.camera.zoom > 14 ? mapController.camera.zoom : 16.0;
          mapController.move(currentLocation!, targetZoom);
          if (!isManual) _isFirstLocationFix = false;
        }
        _notify();
      }

      // 🎯 Актуальное положение с таймаутом
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );

      currentLocation = LatLng(position.latitude, position.longitude);
      if (_isFirstLocationFix || isManual) {
        final targetZoom =
            mapController.camera.zoom > 14 ? mapController.camera.zoom : 16.0;
        mapController.move(currentLocation!, targetZoom);
        _isFirstLocationFix = false;
      }
    } catch (e) {
      debugPrint('Ошибка геолокации: $e');
      if (isManual) _showErrorSnackBar('Не удалось определить местоположение');
    } finally {
      if (isManual && !_disposed) {
        isLocating = false;
      }
      _notify();
    }
  }

  Future<void> _loadAvailableMaps() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    String? cachedJson;
    String? cachedTimestampStr;

    try {
      cachedJson = await storage.read(key: _MAPS_CACHE_KEY);
      cachedTimestampStr = await storage.read(key: _MAPS_CACHE_TIMESTAMP_KEY);
    } catch (e) {
      debugPrint('Ошибка чтения кеша карт: $e');
    }

    final cachedValid = _isCacheValid(cachedJson, cachedTimestampStr, now);
    if (cachedValid) {
      availableMaps = jsonDecode(cachedJson!) as List;
      _applyFirstMapIfNoneSelected();
      _notify();
      return;
    }

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен отсутствует');

      final response = await _authenticatedGet(AppConfig.adminMapsUrl, token);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is List) {
          availableMaps = body;
          _applyFirstMapIfNoneSelected();
          await storage.write(key: _MAPS_CACHE_KEY, value: response.body);
          await storage.write(
            key: _MAPS_CACHE_TIMESTAMP_KEY,
            value: now.toString(),
          );
          _notify();
          return;
        }
      }

      if (cachedJson != null) {
        availableMaps = jsonDecode(cachedJson) as List;
        _applyFirstMapIfNoneSelected();
        _notify();
      }
    } catch (e) {
      if (cachedJson != null) {
        availableMaps = jsonDecode(cachedJson) as List;
        _applyFirstMapIfNoneSelected();
        _notify();
      } else {
        _showErrorSnackBar('Ошибка загрузки списка карт: $e');
      }
    }
  }

  bool _isCacheValid(String? json, String? timestampStr, int now) {
    if (json == null || timestampStr == null) return false;
    final timestamp = int.tryParse(timestampStr);
    if (timestamp == null) return false;
    return (now - timestamp) < _CACHE_TTL.inMilliseconds;
  }

  Future<void> _loadSavedMapId() async {
    try {
      final savedId = await storage.read(key: _SELECTED_MAP_ID_KEY);
      if (savedId != null) {
        selectedMapId = int.tryParse(savedId) ?? -1;
      }
    } catch (e) {
      debugPrint('Ошибка загрузки сохраненного ID карты: $e');
    }
  }

  void _applyFirstMapIfNoneSelected() {
    if (selectedMapId == -1 && availableMaps.isNotEmpty) {
      final firstMap = availableMaps.first;
      if (firstMap is Map<String, dynamic> && firstMap.containsKey('id')) {
        selectedMapId = firstMap['id'] as int;
      }
    }
  }

  Future<void> _loadAndParseGeoJson() async {
    if (_disposed) return;
    try {
      String geoJsonString;
      if (selectedMapId != -1) {
        geoJsonString = await _loadGeoJsonFromServer(selectedMapId);
      } else if (availableMaps.isNotEmpty) {
        final firstMap = availableMaps.first;
        if (firstMap is Map<String, dynamic> && firstMap.containsKey('id')) {
          selectedMapId = firstMap['id'] as int;
          geoJsonString = await _loadGeoJsonFromServer(selectedMapId);
        } else {
          throw Exception('Нет доступных карт');
        }
      } else {
        throw Exception('Нет доступных карт');
      }

      _polygonProperties.clear();
      geoJsonParser.parseGeoJsonAsString(geoJsonString);
      _notify();
    } catch (e) {
      debugPrint('Ошибка парсинга GeoJSON: $e');
      _showErrorSnackBar(
          'Не удалось загрузить зоны для этой карты. Попробуйте обновить.');
    }
  }

  Future<String> _loadGeoJsonFromServer(int mapId) async {
    final localFile = await _getLocalMapFile(mapId);
    if (await localFile.exists()) {
      final content = await localFile.readAsString();
      if (content.isNotEmpty && content.trim().startsWith('{')) {
        debugPrint('✅ Загружено из офлайн-кеша: ${localFile.path}');
        isMapLoadedOffline = true;
        return content;
      } else {
        debugPrint(
            '⚠️ Кэшированный файл пуст или не в формате JSON. Удаление.');
        await localFile.delete();
      }
    }

    final token = await storage.read(key: 'jwt_token');
    if (token == null) throw Exception('Нет токена');

    final mapMetaResponse =
        await _authenticatedGet(AppConfig.getMapByIdUrl(mapId), token);
    if (mapMetaResponse.statusCode != 200) {
      throw Exception(
          'Не удалось получить метаданные карты (${mapMetaResponse.statusCode})');
    }

    final meta = jsonDecode(mapMetaResponse.body) as Map<String, dynamic>;
    if (!meta.containsKey('file_name')) {
      throw Exception('Неверный формат метаданных');
    }

    final fileUrl = AppConfig.getMapFileUrl(meta['file_name'] as String);
    final fileResponse = await _authenticatedGet(fileUrl, token);

    if (fileResponse.statusCode == 200 && fileResponse.body.isNotEmpty) {
      await _saveMapFileLocally(mapId, fileResponse.body);
      isMapLoadedOffline = false;
      return fileResponse.body;
    } else {
      throw Exception('Пустой или ошибочный GeoJSON-файл');
    }
  }

  Future<http.Response> _authenticatedGet(String url, String token) async {
    return http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
    );
  }

  Future<File> _getLocalMapFile(int mapId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/map_$mapId.geojson');
  }

  Future<void> _saveMapFileLocally(int mapId, String content) async {
    final file = await _getLocalMapFile(mapId);
    await file.create(recursive: true);
    await file.writeAsString(content, flush: true);
    debugPrint('✅ Карта $mapId сохранена в: ${file.path}');
  }

  Future<void> onMapChanged(int newMapId) async {
    if (_disposed || newMapId == selectedMapId) return;

    selectedMapId = newMapId;
    await storage.write(key: _SELECTED_MAP_ID_KEY, value: newMapId.toString());
    isLoading = true;
    isMapLoadedOffline = false;
    _notify();

    try {
      final geoJsonString = await _loadGeoJsonFromServer(newMapId);
      geoJsonParser.parseGeoJsonAsString(geoJsonString);
    } catch (e) {
      _showErrorSnackBar('Ошибка загрузки карты: $e');
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<void> downloadMapLocally(int mapId) async {
    if (_disposed) return;
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) {
        _showErrorSnackBar('Не авторизован');
        return;
      }

      final mapMetaResponse =
          await _authenticatedGet(AppConfig.getMapByIdUrl(mapId), token);
      if (mapMetaResponse.statusCode != 200) {
        _showErrorSnackBar('Не удалось получить данные карты');
        return;
      }

      final meta = jsonDecode(mapMetaResponse.body) as Map<String, dynamic>;
      if (!meta.containsKey('file_name')) {
        _showErrorSnackBar('Неверный формат данных карты');
        return;
      }

      final fileUrl = AppConfig.getMapFileUrl(meta['file_name'] as String);
      final fileResponse = await _authenticatedGet(fileUrl, token);

      if (fileResponse.statusCode == 200 && fileResponse.body.isNotEmpty) {
        await _saveMapFileLocally(mapId, fileResponse.body);
        _showSuccessSnackBar(
            'Карта успешно сохранена для оффлайн использования');
      } else {
        _showErrorSnackBar('Пустой или повреждённый GeoJSON-файл');
      }
    } catch (e) {
      debugPrint('Ошибка при сохранении карты: $e');
      _showErrorSnackBar('Ошибка сохранения карты: $e');
    }
  }

  void showLayerSettingsDialog() {
    if (_disposed || !context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Настройки слоев',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  _buildSwitchTile(
                    title: 'Рабочие зоны',
                    subtitle: 'Красные зоны',
                    value: showRestrictedZones,
                    color: Colors.red.withOpacity(0.6),
                    onChanged: (v) {
                      setState(() => showRestrictedZones = v);
                      this.showRestrictedZones = v;
                      _notify();
                    },
                  ),
                  _buildSwitchTile(
                    title: 'Зоны парковки',
                    subtitle: 'Розовые зоны',
                    value: showParkingZones,
                    color: Colors.pink.withOpacity(0.6),
                    onChanged: (v) {
                      setState(() => showParkingZones = v);
                      this.showParkingZones = v;
                      _notify();
                    },
                  ),
                  _buildSwitchTile(
                    title: 'Ограничения скорости',
                    subtitle: 'Зеленые и желтые зоны',
                    value: showSpeedLimitZones,
                    gradient: const LinearGradient(
                        colors: [Colors.green, Colors.yellow]),
                    onChanged: (v) {
                      setState(() => showSpeedLimitZones = v);
                      this.showSpeedLimitZones = v;
                      _notify();
                    },
                  ),
                  _buildSwitchTile(
                    title: 'Границы',
                    subtitle: 'Синие линии',
                    value: showBoundaries,
                    color: Colors.blue,
                    height: 4,
                    onChanged: (v) {
                      setState(() => showBoundaries = v);
                      this.showBoundaries = v;
                      _notify();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    Color? color,
    Gradient? gradient,
    double height = 24,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      value: value,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
      secondary: Container(
        width: 20,
        height: height,
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (_disposed || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (_disposed || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<bool> isOffline() async {
    return !(await isOnline());
  }

  Future<bool> isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  bool get isMapReady => tileProvider != null && currentLocation != null;

  /// Метод для поиска зоны (полигона) в указанной точке
  Map<String, dynamic>? findPolygonAtPoint(LatLng point) {
    for (var i = 0; i < geoJsonParser.polygons.length; i++) {
      final polygon = geoJsonParser.polygons[i];
      if (_isPointInPolygon(point, polygon.points)) {
        if (i < _polygonProperties.length) {
          return _polygonProperties[i];
        }
        return {'description': 'Зона без описания'};
      }
    }
    return null;
  }

  /// Алгоритм Ray Casting для проверки нахождения точки в полигоне
  bool _isPointInPolygon(LatLng point, List<LatLng> vertices) {
    int intersectCount = 0;
    for (int j = 0; j < vertices.length; j++) {
      LatLng vertJ = vertices[j];
      LatLng vertI = vertices[(j + 1) % vertices.length];

      if (((vertI.latitude > point.latitude) !=
              (vertJ.latitude > point.latitude)) &&
          (point.longitude <
              (vertJ.longitude - vertI.longitude) *
                      (point.latitude - vertI.latitude) /
                      (vertJ.latitude - vertI.latitude) +
                  vertI.longitude)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }
}
