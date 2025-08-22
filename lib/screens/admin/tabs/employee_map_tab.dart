// lib/screens/admin/tabs/employee_map_tab.dart
import 'dart:async';
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
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

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
  late MapController _mapController;
  Timer? _locationUpdateTimer;

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
      await _connectWebSocket();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
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
          setState(() => _currentLocation = LatLng(lat, lng));
        }
      }
    } catch (e) {
      debugPrint('Ошибка получения локации: $e');
    }
  }

  Future<void> _connectWebSocket() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      if (mounted) {
        setState(() => _error = 'Токен не найден');
      }
      return;
    }

    // === ПОЛУЧАЕМ РЕАЛЬНЫЕ ДАННЫЕ ИЗ PROVIDER ===
    final provider = Provider.of<ShiftProvider>(context, listen: false);
    final username = provider.currentUsername ?? 'admin';
    final userId = provider.activeShift?.userId ?? 3;

    _webSocketService = WebSocketService(onLocationsUpdated: (users) {
      if (mounted) {
        setState(() => _onlineUsers = users);
      }
    });

    try {
      await _webSocketService.connect();

      // Запускаем периодическую отправку
      _startPeriodicLocationUpdates(userId, username);

      // Отправляем начальную позицию
      if (_currentLocation != null) {
        final myLocation = Location(
          userID: userId,
          username: username,
          lat: _currentLocation!.latitude,
          lng: _currentLocation!.longitude,
          timestamp: DateTime.now(),
        );
        _webSocketService.sendLocation(myLocation);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Ошибка подключения: $e');
      }
    }
  }

  void _startPeriodicLocationUpdates(int userId, String username) {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 15), (timer) async {
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

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _mapController.dispose();
    _webSocketService.disconnect();
    super.dispose();
  }

  Future<void> _refreshMap() async {
    if (_isRefreshing || !mounted) return;
    setState(() => _isRefreshing = true);

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
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) return Center(child: Text('Ошибка: $_error'));

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
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
    if (diff.inSeconds < 60) return '${diff.inSeconds} сек назад';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }
}
