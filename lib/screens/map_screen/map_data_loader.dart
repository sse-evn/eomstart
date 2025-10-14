import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:micro_mobility_app/config/config.dart' show AppConfig;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import '../../utils/map_app_constants.dart';
import '../../services/location_service.dart';
import 'package:flutter_map/flutter_map.dart';

class MapLogic {
  final BuildContext context;
  LatLng? currentLocation;
  final LocationService locationService = LocationService();
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

  MapLogic(this.context) {
    mapController = MapController();
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

  void _notify() {
    if (_disposed || onStateChanged == null) return;
    onStateChanged!();
  }

  Future<void> _initMap() async {
    if (_disposed) return;
    try {
      await fetchCurrentLocation();
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
      final position = await locationService.determinePosition();
      if (_disposed) return;
      currentLocation = LatLng(position.latitude, position.longitude);
      isLoading = false;
      mapController.move(currentLocation!, mapController.camera.zoom);
      _notify();
    } catch (e) {
      if (!_disposed) {
        isLoading = false;
        _notify();
        _showErrorSnackBar('Ошибка получения местоположения');
      }
    }
  }

  Future<void> _loadAvailableMaps() async {
    if (_disposed) return;
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
            if (selectedMapId == -1 && availableMaps.isNotEmpty) {
              final firstMap = availableMaps.first;
              if (firstMap is Map<String, dynamic> &&
                  firstMap.containsKey('id')) {
                selectedMapId = firstMap['id'] as int;
              }
            }
            _notify();
          }
        }
      }
    } catch (e) {
      if (!_disposed) {
        _showErrorSnackBar('Ошибка загрузки списка карт: $e');
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
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse(AppConfig.getMapByIdUrl(mapId)),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 200 && !_disposed) {
          final dynamic body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body.containsKey('file_name')) {
            final fileName = body['file_name'] as String;
            final fileUrl = AppConfig.getMapFileUrl(fileName);
            final localFile = await _getLocalMapFile(mapId);
            if (localFile != null && await localFile.exists()) {
              isMapLoadedOffline = true;
              return await localFile.readAsString();
            }
            final fileResponse = await http.get(
              Uri.parse(fileUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/geo+json',
              },
            );
            if (fileResponse.statusCode == 200) {
              isMapLoadedOffline = false;
              await _saveMapFileLocally(mapId, fileResponse.body);
              return fileResponse.body;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки GeoJSON с сервера: $e');
      if (!_disposed) {
        final localFile = await _getLocalMapFile(mapId);
        if (localFile != null && await localFile.exists()) {
          isMapLoadedOffline = true;
          return await localFile.readAsString();
        }
      }
    }
    throw Exception('Не удалось загрузить карту');
  }

  Future<File?> _getLocalMapFile(int mapId) async {
    if (_disposed) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'map_$mapId.geojson';
      final filePath = path.join(dir.path, fileName);
      return File(filePath);
    } catch (e) {
      debugPrint('Ошибка получения пути к локальному файлу: $e');
      return null;
    }
  }

  Future<void> _saveMapFileLocally(int mapId, String content) async {
    if (_disposed) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'map_$mapId.geojson';
      final filePath = path.join(dir.path, fileName);
      final file = File(filePath);
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Ошибка сохранения файла локально: $e');
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
      if (token != null) {
        final response = await http.get(
          Uri.parse(AppConfig.getMapByIdUrl(mapId)),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 200 && !_disposed) {
          final dynamic body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body.containsKey('file_name')) {
            final fileName = body['file_name'] as String;
            final fileUrl = AppConfig.getMapFileUrl(fileName);
            final fileResponse = await http.get(
              Uri.parse(fileUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/geo+json',
              },
            );
            if (fileResponse.statusCode == 200) {
              await _saveMapFileLocally(mapId, fileResponse.body);
              _showSuccessSnackBar(
                  'Карта успешно сохранена для оффлайн использования');
            }
          }
        }
      }
    } catch (e) {
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
                  const Text(
                    'Настройки слоев',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
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
                        gradient: const LinearGradient(
                          colors: [Colors.green, Colors.yellow],
                        ),
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
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (_disposed || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
}
