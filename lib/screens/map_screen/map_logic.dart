import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:micro_mobility_app/config/app_config.dart' show AppConfig;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import '../../utils/map_app_constants.dart';

class MapLogic {
  final BuildContext context;
  LatLng? currentLocation;
  final GeoJsonParser geoJsonParser = GeoJsonParser();
  late final MapController mapController;
  bool isLoading = false;
  List<dynamic> availableMaps = [];
  int selectedMapId = -1;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  bool showRestrictedZones = true;
  bool showParkingZones = true;
  bool showSpeedLimitZones = true;
  bool showBoundaries = true;
  bool isMapLoadedOffline = false;
  bool _disposed = false;
  void Function()? onStateChanged;

  // FMTC tile provider — теперь nullable
  FMTCTileProvider? tileProvider;

  // Для отслеживания, были ли тайлы предзагружены
  bool _tilesPrefetched = false;

  String? currentUserAvatarUrl;

  static const String _MAPS_CACHE_KEY = 'cached_maps_list';
  static const String _MAPS_CACHE_TIMESTAMP_KEY = 'cached_maps_list_timestamp';
  static const Duration _CACHE_TTL = Duration(minutes: 10);

  MapLogic(this.context, {String? initialAvatarUrl})
      : currentUserAvatarUrl = initialAvatarUrl {
    mapController = MapController();
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
      if (!_disposed) _initMap();
    });
  }

  Future<void> _initCaching() async {
    const storeName = 'mapStore';
    final store = FMTCStore(storeName);
    if (!(await store.manage.ready)) {
      await store.manage.create();
    }

    tileProvider = FMTCTileProvider(
      stores: const {
        storeName: BrowseStoreStrategy.readUpdateCreate,
      },
      loadingStrategy: BrowseLoadingStrategy.onlineFirst,
    );

    _notify(); // Важно: уведомить UI, что tileProvider готов
  }

  void dispose() {
    _disposed = true;
    mapController.dispose();
  }

  Future<void> _initMap() async {
    if (_disposed) return;
    try {
      isLoading = true;
      _notify();

      await fetchCurrentLocation();
      if (currentLocation != null && await isOnline()) {
        // await _prefetchTilesIfNeeded();
      }

      await _loadAvailableMaps();
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

  Future<void> fetchCurrentLocation() async {
    if (_disposed) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Служба геолокации отключена');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Доступ к местоположению запрещён');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Доступ к местоположению запрещён навсегда');
      }

      Position position = await Geolocator.getCurrentPosition();
      currentLocation = LatLng(position.latitude, position.longitude);
      mapController.move(currentLocation!, 16.0); // Установите разумный zoom
    } catch (e) {
      _showErrorSnackBar('Ошибка получения местоположения: $e');
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

      geoJsonParser.parseGeoJsonAsString(geoJsonString);
      _notify();
    } catch (e) {
      _showErrorSnackBar('Ошибка загрузки GeoJSON: $e');
    }
  }

  Future<String> _loadGeoJsonFromServer(int mapId) async {
    final localFile = await _getLocalMapFile(mapId);
    if (await localFile.exists()) {
      final content = await localFile.readAsString();
      if (content.isNotEmpty) {
        debugPrint('✅ Загружено из офлайн-кеша: ${localFile.path}');
        isMapLoadedOffline = true;
        return content;
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
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Настройки слоев',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  _buildSwitchTile(
                    title: 'Запретные зоны',
                    subtitle: 'Красные зоны (запрет на проезд/парковку)',
                    value: showRestrictedZones,
                    color: Colors.red.withOpacity(0.6),
                    onChanged: (v) => setState(() => showRestrictedZones = v),
                  ),
                  _buildSwitchTile(
                    title: 'Зоны парковки',
                    subtitle: 'Розовые зоны (запрет на парковку)',
                    value: showParkingZones,
                    color: Colors.pink.withOpacity(0.6),
                    onChanged: (v) => setState(() => showParkingZones = v),
                  ),
                  _buildSwitchTile(
                    title: 'Ограничения скорости',
                    subtitle: 'Зеленые и желтые зоны (ограничение скорости)',
                    value: showSpeedLimitZones,
                    gradient:
                        LinearGradient(colors: [Colors.green, Colors.yellow]),
                    onChanged: (v) => setState(() => showSpeedLimitZones = v),
                  ),
                  _buildSwitchTile(
                    title: 'Границы',
                    subtitle: 'Синие линии (граница рабочей зоны)',
                    value: showBoundaries,
                    color: Colors.blue,
                    height: 4,
                    onChanged: (v) => setState(() => showBoundaries = v),
                  ),
                  const SizedBox(height: 20),
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
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      secondary: Container(
        width: 24,
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
}
