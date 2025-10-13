import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:latlong2/latlong.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/models/user_shift_location.dart';
import 'package:micro_mobility_app/services/websocket/location_tracking_service.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';
import 'package:geolocator/geolocator.dart'; // 🔹 Добавлен geolocator

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

  /// Получает текущее местоположение через GPS (geolocator)
  Future<void> _fetchCurrentLocation() async {
    if (_disposed) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Служба геолокации отключена на устройстве.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception(
              'Доступ к местоположению запрещён. Разрешите в настройках.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Доступ к местоположению запрещён навсегда. Измените в настройках устройства.');
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        currentLocation = LatLng(position.latitude, position.longitude);
        _notify();
      } else {
        throw Exception('Недостаточно прав для доступа к местоположению.');
      }
    } catch (e) {
      debugPrint('Ошибка GPS-геолокации: $e');
      if (!_disposed) {
        connectionError = true;
        connectionErrorMessage = e.toString();
        // Не устанавливаем isLoading = false здесь, чтобы не сломать логику initMap
        // Ошибку обработает вызывающий код
        rethrow; // чтобы initMap поймал ошибку
      }
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
          SnackBar(content: Text('Ошибка обновления: ${e.toString()}')),
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
