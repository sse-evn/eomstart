import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../providers/shift_provider.dart';
import '../../models/location.dart';
import 'global_websocket_service.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance =
      LocationTrackingService._internal();
  static final _storage = FlutterSecureStorage();

  factory LocationTrackingService() {
    return _instance;
  }

  LocationTrackingService._internal();

  final loc.Location _locationService = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  Timer? _updateTimer;
  bool _isTracking = false;
  Location? _currentLocation;

  Future<void> init(BuildContext context) async {
    bool serviceEnabled;
    loc.PermissionStatus permissionGranted;

    serviceEnabled = await _locationService.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _locationService.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await _locationService.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _locationService.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    _startTracking(context);
  }

  void _startTracking(BuildContext context) {
    if (_isTracking) return;

    _isTracking = true;

    _locationSubscription = _locationService.onLocationChanged
        .listen((loc.LocationData locationData) {
      if (locationData.latitude != null && locationData.longitude != null) {
        _currentLocation = Location(
          userID: 0,
          username: '',
          lat: locationData.latitude!,
          lng: locationData.longitude!,
          timestamp: DateTime.now(),
        );

        _updateLocationInGlobalService(context);
      }
    });

    _updateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_currentLocation != null) {
        _updateLocationInGlobalService(context);
      }
    });
  }

  void _updateLocationInGlobalService(BuildContext context) {
    if (_currentLocation == null) return;

    try {
      final provider = Provider.of<ShiftProvider>(context, listen: false);
      final username = provider.currentUsername ?? 'user';
      final userId = provider.activeShift?.userId ?? 0;

      _currentLocation = Location(
        userID: userId,
        username: username,
        lat: _currentLocation!.lat,
        lng: _currentLocation!.lng,
        timestamp: DateTime.now(),
      );

      GlobalWebSocketService().updateCurrentLocation(_currentLocation!);
    } catch (e) {
      print('Error updating location in global service: $e');
    }
  }

  void stopTracking() {
    if (!_isTracking) return;

    _isTracking = false;

    _locationSubscription?.cancel();
    _updateTimer?.cancel();
  }

  Location? get currentLocation => _currentLocation;

  bool get isTracking => _isTracking;
}
