import 'dart:async';
import 'package:location/location.dart' as loc;
import '../../models/location.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance =
      LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  final loc.Location _locationService = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  Timer? _updateTimer;
  bool _isTracking = false;
  Location? _currentLocation;
  void Function(Location)? _onLocationUpdate;

  void setLocationUpdateCallback(void Function(Location) callback) {
    _onLocationUpdate = callback;
  }

  void updateUserInfo({required int userId, required String username}) {
    if (_currentLocation != null) {
      _currentLocation = Location(
        userID: userId,
        username: username,
        lat: _currentLocation!.lat,
        lng: _currentLocation!.lng,
        timestamp: DateTime.now(),
      );
      _onLocationUpdate?.call(_currentLocation!);
    }
  }

  Future<void> init() async {
    bool serviceEnabled = await _locationService.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _locationService.requestService();
      if (!serviceEnabled) return;
    }

    var permission = await _locationService.hasPermission();
    if (permission == loc.PermissionStatus.denied) {
      permission = await _locationService.requestPermission();
      if (permission != loc.PermissionStatus.granted) return;
    }

    _startTracking();
  }

  void _startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    _locationSubscription = _locationService.onLocationChanged.listen((data) {
      if (data.latitude != null && data.longitude != null) {
        _currentLocation = Location(
          userID: 0,
          username: '',
          lat: data.latitude!,
          lng: data.longitude!,
          timestamp: DateTime.now(),
        );
        _onLocationUpdate?.call(_currentLocation!);
      }
    });

    _updateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _onLocationUpdate?.call(_currentLocation!);
    });
  }

  void stopTracking() {
    if (!_isTracking) return;
    _isTracking = false;
    _locationSubscription?.cancel();
    _updateTimer?.cancel();
    _locationSubscription = null;
    _updateTimer = null;
  }

  Location? get currentLocation => _currentLocation;
  bool get isTracking => _isTracking;
}
