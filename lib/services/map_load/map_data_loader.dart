// lib/screens/map_logic.dart

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
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/models/user_shift_location.dart';
import 'package:micro_mobility_app/services/websocket/global_websocket_service.dart';
import 'package:micro_mobility_app/services/websocket/location_tracking_service.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../utils/map_app_constants.dart';
import '../../services/location_service.dart';

class MapLogic {
  final BuildContext context;

  // --- State-like variables ---
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
  late GlobalWebSocketService globalWebSocketService;
  late LocationTrackingService locationTrackingService;
  StreamSubscription<Location>? locationSubscription;
  bool connectionError = false;
  String connectionErrorMessage = '';
  List<Location> users = [];
  List<UserShiftLocation> activeShifts = [];
  bool isWebSocketConnected = false;

  // Callback to notify UI about state changes
  void Function()? onStateChanged;

  MapLogic(this.context) {
    mapController = MapController();
    globalWebSocketService =
        Provider.of<GlobalWebSocketService>(context, listen: false);
    locationTrackingService =
        Provider.of<LocationTrackingService>(context, listen: false);
  }

  void init() {
    globalWebSocketService.addLocationsCallback(_updateUsers);
    globalWebSocketService.addShiftsCallback(_updateShifts);
    globalWebSocketService.addConnectionCallback(_updateConnectionStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initMap();
    });
  }

  void dispose() {
    globalWebSocketService.removeLocationsCallback(_updateUsers);
    globalWebSocketService.removeShiftsCallback(_updateShifts);
    globalWebSocketService.removeConnectionCallback(_updateConnectionStatus);
    locationSubscription?.cancel();
    mapController.dispose();
  }

  void _updateUsers(List<Location> newUsers) {
    users = newUsers;
    _notify();
  }

  void _updateShifts(List<UserShiftLocation> shifts) {
    activeShifts = shifts;
    _notify();
  }

  void _updateConnectionStatus(bool isConnected) {
    isWebSocketConnected = isConnected;
    _notify();
  }

  void _notify() {
    if (onStateChanged != null) {
      onStateChanged!();
    }
  }

  Future<void> _initMap() async {
    try {
      await fetchCurrentLocation();
      await _loadAvailableMaps();
      await _loadAndParseGeoJson();
      await locationTrackingService.init(context);
      isLoading = false;
      _notify();
    } catch (e) {
      isLoading = false;
      connectionError = true;
      connectionErrorMessage = e.toString();
      _notify();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка инициализации: $e')),
      );
    }
  }

  Future<void> fetchCurrentLocation() async {
    isLoading = true;
    _notify();
    try {
      final position = await locationService.determinePosition();
      currentLocation = LatLng(position.latitude, position.longitude);
      isLoading = false;
      mapController.move(currentLocation!, mapController.camera.zoom);
      _notify();
    } catch (e) {
      isLoading = false;
      _notify();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка получения местоположения')),
      );
    }
  }

  Future<void> _loadAvailableMaps() async {
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
        if (response.statusCode == 200) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки списка карт: $e')),
      );
    }
  }

  Future<void> _loadAndParseGeoJson() async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки GeoJSON: $e')),
      );
    }
  }

  Future<String> _loadGeoJsonFromServer(int mapId) async {
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
        if (response.statusCode == 200) {
          final dynamic body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body.containsKey('file_name')) {
            final fileName = body['file_name'] as String;
            final fileUrl = AppConfig.getMapFileUrl(fileName);
            final localFile = await _getLocalMapFile(mapId);
            if (localFile != null && await localFile.exists()) {
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
              await _saveMapFileLocally(mapId, fileResponse.body);
              return fileResponse.body;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки GeoJSON с сервера: $e');
      final localFile = await _getLocalMapFile(mapId);
      if (localFile != null && await localFile.exists()) {
        return await localFile.readAsString();
      }
    }
    throw Exception('Не удалось загрузить карту');
  }

  Future<File?> _getLocalMapFile(int mapId) async {
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
    if (newMapId != selectedMapId) {
      selectedMapId = newMapId;
      isLoading = true;
      _notify();
      try {
        final geoJsonString = await _loadGeoJsonFromServer(newMapId);
        geoJsonParser.parseGeoJsonAsString(geoJsonString);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки карты: $e')),
        );
      } finally {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<void> downloadMapLocally(int mapId) async {
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
        if (response.statusCode == 200) {
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Карта успешно сохранена для оффлайн использования'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сохранения карты: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void showLayerSettingsDialog() {
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
                      setState(() {
                        showRestrictedZones = value;
                      });
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
                      setState(() {
                        showParkingZones = value;
                      });
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
                      setState(() {
                        showSpeedLimitZones = value;
                      });
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
                      setState(() {
                        showBoundaries = value;
                      });
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
}
