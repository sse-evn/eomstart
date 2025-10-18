// lib/screens/map_screen/map_logic.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:micro_mobility_app/config/config.dart' show AppConfig;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../utils/map_app_constants.dart';
import 'package:flutter_map/flutter_map.dart';

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
  String? currentUserAvatarUrl;

  static const String _MAPS_CACHE_KEY = 'cached_maps_list';
  static const String _MAPS_CACHE_TIMESTAMP_KEY = 'cached_maps_list_timestamp';
  static const Duration _CACHE_TTL = Duration(minutes: 10);

  MapLogic(this.context) {
    mapController = MapController();
  }

  void _notify() {
    if (_disposed || onStateChanged == null) return;
    onStateChanged!();
  }

  void init() {
    if (_disposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _initMap();
    });
  }

  void dispose() {
    _disposed = true;
    mapController.dispose();
  }

  Future<void> _initMap() async {
    if (_disposed) return;
    try {
      await fetchCurrentLocation();
      await _loadUserProfile();
      await _loadAvailableMaps();
      await _loadAndParseGeoJson();
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    } catch (e) {
      if (!_disposed) {
        isLoading = false;
        _notify();
        _showErrorSnackBar('Ошибка инициализации: $e');
      }
    }
  }

  Future<void> fetchCurrentLocation() async {
    if (_disposed) return;
    isLoading = true;
    _notify();
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
      isLoading = false;
      if (currentLocation != null) {
        mapController.move(currentLocation!, mapController.camera.zoom);
      }
      _notify();
    } catch (e) {
      if (!_disposed) {
        isLoading = false;
        _notify();
        _showErrorSnackBar('Ошибка получения местоположения: $e');
      }
    }
  }

  Future<void> _loadAvailableMaps() async {
    if (_disposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    String? cachedJson;
    String? cachedTimestampStr;

    try {
      cachedJson = await storage.read(key: _MAPS_CACHE_KEY);
      cachedTimestampStr = await storage.read(key: _MAPS_CACHE_TIMESTAMP_KEY);
    } catch (e) {
      debugPrint('Ошибка чтения кеша карт: $e');
    }

    if (cachedJson != null && cachedTimestampStr != null) {
      final cachedTimestamp = int.tryParse(cachedTimestampStr);
      if (cachedTimestamp != null &&
          now - cachedTimestamp < _CACHE_TTL.inMilliseconds) {
        try {
          final decoded = jsonDecode(cachedJson);
          if (decoded is List) {
            availableMaps = decoded;
            _applyFirstMapIfNoneSelected();
            _notify();
            return;
          }
        } catch (e) {
          debugPrint('Невалидный кеш карт: $e');
        }
      }
    }

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse(AppConfig.adminMapsUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 200 && !_disposed) {
          final dynamic body = jsonDecode(response.body);
          if (body is List) {
            availableMaps = body;
            _applyFirstMapIfNoneSelected();
            await storage.write(key: _MAPS_CACHE_KEY, value: response.body);
            await storage.write(
                key: _MAPS_CACHE_TIMESTAMP_KEY, value: now.toString());
            _notify();
          }
        } else {
          if (cachedJson != null && availableMaps.isEmpty) {
            try {
              final decoded = jsonDecode(cachedJson);
              if (decoded is List) {
                availableMaps = decoded;
                _applyFirstMapIfNoneSelected();
                _notify();
              }
            } catch (e) {
              debugPrint('Не удалось использовать резервный кеш: $e');
            }
          }
        }
      }
    } catch (e) {
      if (cachedJson != null && availableMaps.isEmpty) {
        try {
          final decoded = jsonDecode(cachedJson);
          if (decoded is List) {
            availableMaps = decoded;
            _applyFirstMapIfNoneSelected();
            _notify();
          }
        } catch (e) {
          debugPrint('Не удалось загрузить даже из кеша: $e');
        }
      }
      if (!_disposed) {
        _showErrorSnackBar('Ошибка загрузки списка карт: $e');
      }
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
      if (!_disposed) {
        geoJsonParser.parseGeoJsonAsString(geoJsonString);
        _notify();
      }
    } catch (e) {
      if (!_disposed) {
        _showErrorSnackBar('Ошибка загрузки GeoJSON: $e');
      }
    }
  }

  Future<String> _loadGeoJsonFromServer(int mapId) async {
    if (_disposed) return '';

    // Сначала пробуем загрузить из локального кеша
    try {
      final localFile = await _getLocalMapFile(mapId);
      if (await localFile.exists()) {
        final content = await localFile.readAsString();
        if (content.isNotEmpty) {
          debugPrint('✅ Загружено из офлайн-кеша: ${localFile.path}');
          isMapLoadedOffline = true;
          return content;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Не удалось прочитать офлайн-карту: $e');
    }

    // Если нет локальной — грузим с сервера
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Нет токена');

      final response = await http.get(
        Uri.parse(AppConfig.getMapByIdUrl(mapId)),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('API вернул ${response.statusCode}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || !body.containsKey('file_name')) {
        throw Exception('Неверный формат ответа');
      }

      final fileName = body['file_name'] as String;
      final fileUrl = AppConfig.getMapFileUrl(fileName);

      final fileResponse = await http.get(
        Uri.parse(fileUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (fileResponse.statusCode == 200 && fileResponse.body.isNotEmpty) {
        // Сохраняем на устройство
        await _saveMapFileLocally(mapId, fileResponse.body);
        isMapLoadedOffline = false;
        return fileResponse.body;
      } else {
        throw Exception('Пустой или ошибочный GeoJSON-файл');
      }
    } catch (e) {
      // Если всё провалилось — пробуем ещё раз локальный файл (вдруг появился)
      try {
        final localFile = await _getLocalMapFile(mapId);
        if (await localFile.exists()) {
          final content = await localFile.readAsString();
          if (content.isNotEmpty) {
            debugPrint(
                '🔄 Восстановлено из кеша после ошибки: ${localFile.path}');
            isMapLoadedOffline = true;
            return content;
          }
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<File> _getLocalMapFile(int mapId) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'map_$mapId.geojson';
    return File('${dir.path}/$fileName');
  }

  Future<void> _saveMapFileLocally(int mapId, String content) async {
    try {
      final file = await _getLocalMapFile(mapId);
      await file.create(recursive: true);
      await file.writeAsString(content, flush: true);
      debugPrint('✅ Карта $mapId сохранена в: ${file.path}');
    } catch (e) {
      debugPrint('❌ Ошибка сохранения карты $mapId: $e');
      rethrow;
    }
  }

  Future<void> onMapChanged(int newMapId) async {
    if (_disposed || newMapId == selectedMapId) return;
    selectedMapId = newMapId;
    isLoading = true;
    isMapLoadedOffline = false;
    _notify();
    try {
      final geoJsonString = await _loadGeoJsonFromServer(newMapId);
      if (!_disposed) {
        geoJsonParser.parseGeoJsonAsString(geoJsonString);
      }
    } catch (e) {
      if (!_disposed) {
        _showErrorSnackBar('Ошибка загрузки карты: $e');
      }
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

      final response = await http.get(
        Uri.parse(AppConfig.getMapByIdUrl(mapId)),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        _showErrorSnackBar('Не удалось получить данные карты');
        return;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || !body.containsKey('file_name')) {
        _showErrorSnackBar('Неверный формат данных карты');
        return;
      }

      final fileName = body['file_name'] as String;
      final fileUrl = AppConfig.getMapFileUrl(fileName);

      final fileResponse = await http.get(
        Uri.parse(fileUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (fileResponse.statusCode == 200 && fileResponse.body.isNotEmpty) {
        await _saveMapFileLocally(mapId, fileResponse.body);
        _showSuccessSnackBar(
            'Карта успешно сохранена для оффлайн использования');
      } else {
        _showErrorSnackBar('Пустой или повреждённый GeoJSON-файл');
      }
    } catch (e) {
      debugPrint('Ошибка при сохранении карты: $e');
      if (!_disposed) {
        _showErrorSnackBar('Ошибка сохранения карты: $e');
      }
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
                  const Text('Настройки слоев',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Запретные зоны'),
                    subtitle:
                        const Text('Красные зоны (запрет на проезд/парковку)'),
                    value: showRestrictedZones,
                    onChanged: (bool value) {
                      if (!_disposed) {
                        setState(() {
                          showRestrictedZones = value;
                        });
                      }
                    },
                    secondary: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Зоны парковки'),
                    subtitle: const Text('Розовые зоны (запрет на парковку)'),
                    value: showParkingZones,
                    onChanged: (bool value) {
                      if (!_disposed) {
                        setState(() {
                          showParkingZones = value;
                        });
                      }
                    },
                    secondary: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.pink.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Ограничения скорости'),
                    subtitle: const Text(
                        'Зеленые и желтые зоны (ограничение скорости)'),
                    value: showSpeedLimitZones,
                    onChanged: (bool value) {
                      if (!_disposed) {
                        setState(() {
                          showSpeedLimitZones = value;
                        });
                      }
                    },
                    secondary: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Colors.green, Colors.yellow]),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Границы'),
                    subtitle: const Text('Синие линии (граница рабочей зоны)'),
                    value: showBoundaries,
                    onChanged: (bool value) {
                      if (!_disposed) {
                        setState(() {
                          showBoundaries = value;
                        });
                      }
                    },
                    secondary: Container(
                      width: 24,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
    try {
      final result = await Connectivity().checkConnectivity();
      return result == ConnectivityResult.none;
    } catch (e) {
      return true;
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
}
