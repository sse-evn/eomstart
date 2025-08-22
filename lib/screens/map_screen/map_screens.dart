// lib/screens/map_screen/map_screens.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/services/location_service.dart';
import 'package:micro_mobility_app/utils/map_app_constants.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/services/websocket_service.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

class MapScreen extends StatefulWidget {
  final File? customGeoJsonFile;

  const MapScreen({super.key, this.customGeoJsonFile});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation;
  final LocationService _locationService = LocationService();
  final GeoJsonParser _geoJsonParser = GeoJsonParser();
  late final MapController _mapController;
  bool _isLoading = false;
  List<dynamic> _availableMaps = [];
  int _selectedMapId = -1;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _showRestrictedZones = true;
  bool _showParkingZones = true;
  bool _showSpeedLimitZones = true;
  bool _showBoundaries = true;

  late WebSocketService _webSocketService;
  bool _isWebSocketConnected = false;
  Timer? _locationSendTimer;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initMap();
    });
  }

  Future<void> _initMap() async {
    try {
      await _fetchCurrentLocation();
      await _loadAvailableMaps();
      await _loadAndParseGeoJson();
      await _connectWebSocket();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка инициализации: $e')),
          );
        });
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      final position = await _locationService.determinePosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoading = false;
          _mapController.move(_currentLocation!, _mapController.camera.zoom);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка получения местоположения')),
        );
      }
    }
  }

  Future<void> _connectWebSocket() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

    // === ПОЛУЧАЕМ РЕАЛЬНЫЕ ДАННЫЕ ИЗ PROVIDER ===
    final provider = Provider.of<ShiftProvider>(context, listen: false);
    final username = provider.currentUsername ?? 'worker';
    final userId = provider.activeShift?.userId ?? 123;

    _webSocketService = WebSocketService(onLocationsUpdated: (users) {
      debugPrint("MapScreen: Получен список онлайн пользователей");
    });

    try {
      await _webSocketService.connect();
      _startPeriodicLocationSending(userId, username);

      if (_currentLocation != null) {
        final location = Location(
          userID: userId,
          username: username,
          lat: _currentLocation!.latitude,
          lng: _currentLocation!.longitude,
          timestamp: DateTime.now(),
        );
        _webSocketService.sendLocation(location);
      }

      if (mounted) {
        setState(() => _isWebSocketConnected = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isWebSocketConnected = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка WebSocket: $e')),
        );
      }
    }
  }

  void _startPeriodicLocationSending(int userId, String username) {
    _locationSendTimer?.cancel();
    _locationSendTimer =
        Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (_webSocketService.isConnected && _currentLocation != null) {
        final location = Location(
          userID: userId,
          username: username,
          lat: _currentLocation!.latitude,
          lng: _currentLocation!.longitude,
          timestamp: DateTime.now(),
        );
        _webSocketService.sendLocation(location);
      }
    });
  }

  Future<void> _loadAvailableMaps() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse('https://eom-sharing.duckdns.org/api/admin/maps'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final dynamic body = jsonDecode(response.body);
          if (body is List) {
            setState(() {
              _availableMaps = body;
              if (_selectedMapId == -1 && _availableMaps.isNotEmpty) {
                final firstMap = _availableMaps.first;
                if (firstMap is Map<String, dynamic> &&
                    firstMap.containsKey('id')) {
                  _selectedMapId = firstMap['id'] as int;
                }
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки списка карт: $e')),
        );
      }
    }
  }

  Future<void> _loadAndParseGeoJson() async {
    try {
      String geoJsonString;

      if (widget.customGeoJsonFile != null) {
        geoJsonString = await widget.customGeoJsonFile!.readAsString();
      } else if (_selectedMapId != -1) {
        geoJsonString = await _loadGeoJsonFromServer(_selectedMapId);
      } else if (_availableMaps.isNotEmpty) {
        final firstMap = _availableMaps.first;
        if (firstMap is Map<String, dynamic> && firstMap.containsKey('id')) {
          final mapId = firstMap['id'] as int;
          setState(() => _selectedMapId = mapId);
          geoJsonString = await _loadGeoJsonFromServer(mapId);
        } else {
          throw Exception('Нет доступных карт');
        }
      } else {
        throw Exception('Нет доступных карт');
      }

      _geoJsonParser.parseGeoJsonAsString(geoJsonString);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки GeoJSON: $e')),
        );
      }
    }
  }

  Future<String> _loadGeoJsonFromServer(int mapId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse('https://eom-sharing.duckdns.org/api/admin/maps/$mapId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final dynamic body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body.containsKey('file_name')) {
            final fileName = body['file_name'] as String;
            final fileUrl =
                'https://eom-sharing.duckdns.org/api/admin/maps/files/$fileName';

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

  @override
  void dispose() {
    _locationSendTimer?.cancel();
    _webSocketService.disconnect();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта зон'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(
              _isWebSocketConnected ? Icons.wifi : Icons.wifi_off,
              color: _isWebSocketConnected ? Colors.green : Colors.red,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isWebSocketConnected
                      ? 'WebSocket подключен'
                      : 'WebSocket отключен'),
                ),
              );
            },
          ),
          if (_availableMaps.isNotEmpty)
            PopupMenuButton<int>(
              icon: const Icon(Icons.map),
              onSelected: _onMapChanged,
              itemBuilder: (BuildContext context) {
                return _availableMaps.map((map) {
                  if (map is Map<String, dynamic>) {
                    final id = map['id'] as int;
                    final city = map['city'] as String? ?? 'Неизвестный город';
                    final description = map['description'] as String? ?? '';
                    final displayName =
                        description.isNotEmpty ? '$city - $description' : city;
                    return PopupMenuItem<int>(
                        value: id, child: Text(displayName));
                  }
                  return const PopupMenuItem<int>(
                      value: 0, child: Text('Некорректная карта'));
                }).toList();
              },
            ),
          if (_selectedMapId != -1)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _downloadMapLocally(_selectedMapId),
              tooltip: 'Сохранить карту локально',
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? AppConstants.defaultMapCenter,
              initialZoom: AppConstants.defaultMapZoom,
              minZoom: AppConstants.minZoom,
              maxZoom: AppConstants.maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.cartoDbPositronUrl,
                subdomains: AppConstants.cartoDbSubdomains,
                userAgentPackageName: AppConstants.userAgentPackageName,
                retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
              ),
              if (_geoJsonParser.polygons.isNotEmpty && _showRestrictedZones)
                PolygonLayer(
                  polygons: _geoJsonParser.polygons.map((polygon) {
                    return Polygon(
                      points: polygon.points,
                      borderColor: Colors.red,
                      color: Colors.red.withOpacity(0.2),
                      borderStrokeWidth: 2.0,
                    );
                  }).toList(),
                ),
              if (_geoJsonParser.polylines.isNotEmpty && _showBoundaries)
                PolylineLayer(
                  polylines: _geoJsonParser.polylines.map((polyline) {
                    return Polyline(
                      points: polyline.points,
                      color: Colors.blue,
                      strokeWidth: 5,
                    );
                  }).toList(),
                ),
              if (_geoJsonParser.markers.isNotEmpty)
                MarkerLayer(
                  markers: _geoJsonParser.markers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final marker = entry.value;
                    return Marker(
                      point: marker.point,
                      width: 30,
                      height: 30,
                      child: Container(
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 3.0,
                                color: Colors.black,
                                offset: Offset(1.0, 1.0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 16,
                      height: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue[700],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            bottom: 80,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'layersFab',
              backgroundColor: Colors.green[700],
              onPressed: _showLayerSettingsDialog,
              child: const Icon(Icons.layers, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'locationFab',
              backgroundColor: Colors.green[700],
              onPressed: _fetchCurrentLocation,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Future<void> _onMapChanged(int newMapId) async {
    if (newMapId != _selectedMapId) {
      setState(() {
        _selectedMapId = newMapId;
        _isLoading = true;
      });

      try {
        final geoJsonString = await _loadGeoJsonFromServer(newMapId);
        _geoJsonParser.parseGeoJsonAsString(geoJsonString);
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка загрузки карты: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _downloadMapLocally(int mapId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse('https://eom-sharing.duckdns.org/api/admin/maps/$mapId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final dynamic body = jsonDecode(response.body);
          if (body is Map<String, dynamic> && body.containsKey('file_name')) {
            final fileName = body['file_name'] as String;
            final fileUrl =
                'https://eom-sharing.duckdns.org/api/admin/maps/files/$fileName';

            final fileResponse = await http.get(
              Uri.parse(fileUrl),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/geo+json',
              },
            );

            if (fileResponse.statusCode == 200) {
              await _saveMapFileLocally(mapId, fileResponse.body);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Карта успешно сохранена для оффлайн использования'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения карты: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLayerSettingsDialog() {
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
                    value: _showRestrictedZones,
                    onChanged: (bool value) {
                      setState(() {
                        _showRestrictedZones = value;
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
                    value: _showParkingZones,
                    onChanged: (bool value) {
                      setState(() {
                        _showParkingZones = value;
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
                    value: _showSpeedLimitZones,
                    onChanged: (bool value) {
                      setState(() {
                        _showSpeedLimitZones = value;
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
                    value: _showBoundaries,
                    onChanged: (bool value) {
                      setState(() {
                        _showBoundaries = value;
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
