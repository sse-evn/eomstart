// lib/screens/admin/tabs/employee_map_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/services/websocket_service.dart';
import 'package:micro_mobility_app/utils/map_app_constants.dart'
    show AppConstants;

class EmployeeMapTab extends StatefulWidget {
  const EmployeeMapTab({super.key});

  @override
  State<EmployeeMapTab> createState() => _EmployeeMapTabState();
}

class _EmployeeMapTabState extends State<EmployeeMapTab> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late WebSocketService _webSocketService;
  List<Location> _onlineUsers = [];
  LatLng? _currentLocation;
  bool _isLoading = true;
  String _error = '';
  bool _isRefreshing = false;
  late MapController _mapController; // Добавлен контроллер

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      await _fetchCurrentLocation();
      await _connectWebSocket();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        if (lat != null && lng != null && mounted) {
          setState(() {
            _currentLocation = LatLng(lat, lng);
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка получения локации: $e');
    }
  }

  Future<void> _connectWebSocket() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      setState(() {
        _error = 'Токен не найден';
      });
      return;
    }

    _webSocketService = WebSocketService(onLocationsUpdated: (users) {
      if (mounted) {
        setState(() {
          _onlineUsers = users;
        });
      }
    });

    try {
      await _webSocketService.connect();
      if (_currentLocation != null) {
        final myLocation = Location(
          userID: 3,
          username: 'admin',
          lat: _currentLocation!.latitude,
          lng: _currentLocation!.longitude,
          timestamp: DateTime.now(),
        );
        _webSocketService.sendLocation(myLocation);
      }
    } catch (e) {
      setState(() {
        _error = 'Ошибка подключения: $e';
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _webSocketService.disconnect();
    super.dispose();
  }

  Future<void> _refreshMap() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });

    try {
      await _fetchCurrentLocation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Карта обновлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(child: Text('Ошибка: $_error'));
    }

    return Column(
      children: [
        // === КАРТА ===
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController, // ✅ Подключаем контроллер
                options: MapOptions(
                  initialCenter:
                      _currentLocation ?? const LatLng(43.2389, 76.8897),
                  initialZoom: 12.0,
                  minZoom: 5.0,
                  maxZoom: 18.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: AppConstants.cartoDbPositronUrl,
                    subdomains: AppConstants.cartoDbSubdomains,
                    retinaMode: RetinaMode.isHighDensity(context),
                  ),

                  // Моя позиция
                  if (_currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentLocation!,
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                BorderSide(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  // Онлайн пользователи
                  if (_onlineUsers.isNotEmpty)
                    MarkerLayer(
                      markers: _onlineUsers.map((u) {
                        return Marker(
                          point: LatLng(u.lat, u.lng),
                          width: 60,
                          height: 30,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 3,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              u.username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                                shadows: [
                                  Shadow(
                                    blurRadius: 1.0,
                                    color: Colors.black,
                                    offset: Offset(0.5, 0.5),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),

              // Кнопка обновления
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: _refreshMap,
                  tooltip: 'Обновить карту',
                  child: _isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.refresh, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        // === СПИСОК ПОДКЛЮЧЁННЫХ ===
        Expanded(
          flex: 2,
          child: Card(
            margin: const EdgeInsets.all(8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Онлайн: ${_onlineUsers.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      if (_isRefreshing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              size: 18, color: Colors.white),
                          onPressed: _refreshMap,
                          tooltip: 'Обновить',
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _onlineUsers.isEmpty
                      ? const Center(
                          child: Text(
                            'Нет подключённых пользователей',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _onlineUsers.length,
                          itemBuilder: (context, index) {
                            final user = _onlineUsers[index];
                            final timeAgo = _formatTimeAgo(user.timestamp);
                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    user.username[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                user.username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '📍 ${user.lat.toStringAsFixed(5)}, ${user.lng.toStringAsFixed(5)}'),
                                  Text('🕒 $timeAgo',
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              trailing: const Icon(Icons.circle,
                                  color: Colors.green, size: 12),
                              onTap: () {
                                // ✅ Центрировать карту на пользователе
                                _mapController.move(
                                  LatLng(user.lat, user.lng),
                                  15.0,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds} сек назад';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} мин назад';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ч назад';
    } else {
      return '${diff.inDays} дн назад';
    }
  }
}
