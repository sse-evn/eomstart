// lib/screens/admin/tabs/map_employee_map/employee_map_logic.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/models/user_shift_location.dart';
import 'package:micro_mobility_app/services/websocket/location_tracking_service.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

class EmployeeMapLogic {
  final BuildContext context;
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
  late LocationTrackingService locationTrackingService;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  late ShiftProvider _shiftProvider;
  void Function()? onStateChanged;
  bool _disposed = false;

  EmployeeMapLogic(this.context) {
    mapController = MapController();
    locationTrackingService =
        Provider.of<LocationTrackingService>(context, listen: false);
    _shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
  }

  void init() {
    if (_disposed) return;
    _shiftProvider.addListener(_onShiftProviderUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _initMap();
    });
  }

  void dispose() {
    _disposed = true;
    _shiftProvider.removeListener(_onShiftProviderUpdate);
    locationTrackingService.stopTracking();
    mapController.dispose();
  }

  void _onShiftProviderUpdate() {
    if (_disposed) return;
    locationTrackingService.updateUserInfo(
      userId: _shiftProvider.activeShift?.userId ?? 0,
      username: _shiftProvider.currentUsername ?? 'user',
    );
  }

  void _notify() {
    if (_disposed || onStateChanged == null) return;
    onStateChanged!();
  }

  Future<void> initMap() async {
    if (_disposed) return;
    isLoading = true;
    _notify();
    try {
      await _initMap();
    } catch (e) {
      if (!_disposed) {
        isLoading = false;
        error = e.toString();
        connectionError = true;
        connectionErrorMessage = e.toString();
        _notify();
      }
    }
  }

  void _updateUsers(List<Location> newUsers) {
    if (_disposed) return;
    users = newUsers;
    _notify();
  }

  void _updateShifts(List<UserShiftLocation> shifts) {
    if (_disposed) return;
    activeShifts = shifts;
    _notify();
  }

  void _updateConnectionStatus(bool isConnected) {
    if (_disposed) return;
    isWebSocketConnected = isConnected;
    _notify();
  }

  Future<void> _initMap() async {
    if (_disposed) return;
    try {
      await _fetchCurrentLocation();
      await locationTrackingService.init();
      locationTrackingService.updateUserInfo(
        userId: _shiftProvider.activeShift?.userId ?? 0,
        username: _shiftProvider.currentUsername ?? 'user',
      );
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    } catch (e) {
      if (!_disposed) {
        isLoading = false;
        error = e.toString();
        connectionError = true;
        connectionErrorMessage = e.toString();
        _notify();
      }
    }
  }

  Future<void> _fetchCurrentLocation() async {
    if (_disposed) return;
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (response.statusCode == 200 && !_disposed) {
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
    if (_disposed || isRefreshing) return;
    isRefreshing = true;
    _notify();
    try {
      await _fetchCurrentLocation();
      if (!_disposed && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Карта обновлена')),
        );
      }
    } catch (e) {
      if (!_disposed && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (!_disposed) {
        isRefreshing = false;
        _notify();
      }
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
