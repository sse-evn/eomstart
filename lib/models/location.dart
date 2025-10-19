// // lib/models/location.dart
import 'package:latlong2/latlong.dart' show LatLng;


class EmployeeLocation {
  final String userId;
  final String? name;
  final LatLng position;
  final double? battery;
  final DateTime timestamp;
  final String? avatarUrl;

  EmployeeLocation({
    required this.userId,
    this.name,
    required this.position,
    this.battery,
    required this.timestamp,
    this.avatarUrl,
  });
}