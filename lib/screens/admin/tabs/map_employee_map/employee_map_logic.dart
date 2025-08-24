// lib/screens/employee_map_logic.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/models/user_shift_location.dart';
import 'package:micro_mobility_app/services/websocket/global_websocket_service.dart';
import 'package:micro_mobility_app/services/websocket/location_tracking_service.dart';
import 'package:provider/provider.dart';

class EmployeeMapLogic {
  final BuildContext context;

  // --- State ---
  LatLng? currentLocation;
  List<UserShiftLocation> activeShifts = [];
  List<Location> users = [];
  bool isLoading = true;
  String error = '';
  bool isRefreshing = false;
  late MapController mapController;
  bool connectionError = false;
  String connectionErrorMessage = '';
  bool isWebSocketConnected = false;

  // Services
  late GlobalWebSocketService globalWebSocketService;
  late LocationTrackingService locationTrackingService;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  // Callback to notify UI
  void Function()? onStateChanged;

  EmployeeMapLogic(this.context) {
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
    mapController.dispose();
  }

  void _notify() {
    if (onStateChanged != null && onStateChanged is Function()) {
      onStateChanged!();
    }
  }

  Future<void> initMap() async {
    isLoading = true;
    _notify();
    try {
      await _initMap(); // вызывает приватную реализацию
    } catch (e) {
      isLoading = false;
      error = e.toString();
      connectionError = true;
      connectionErrorMessage = e.toString();
      _notify();
    }
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

  Future<void> _initMap() async {
    try {
      await _fetchCurrentLocation();
      await locationTrackingService.init(context);
      isLoading = false;
      _notify();
    } catch (e) {
      isLoading = false;
      error = e.toString();
      connectionError = true;
      connectionErrorMessage = e.toString();
      _notify();
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        if (lat != null && lng != null) {
          currentLocation = LatLng(lat, lng);
          _notify();
        }
      }
    } catch (e) {
      debugPrint('Ошибка получения локации: $e');
    }
  }

  Future<void> refreshMap() async {
    if (isRefreshing) return;
    isRefreshing = true;
    _notify();
    try {
      await _fetchCurrentLocation();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Карта обновлена')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      isRefreshing = false;
      _notify();
    }
  }

  String formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds} сек назад';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }

  Color getStatusColor(UserShiftLocation shift) {
    if (!shift.hasLocation) return Colors.grey;
    final now = DateTime.now();
    final diff = now.difference(shift.timestamp!);
    if (diff.inMinutes < 5) return Colors.green;
    if (diff.inMinutes < 15) return Colors.yellow;
    return Colors.orange;
  }
}
