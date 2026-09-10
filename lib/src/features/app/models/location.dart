// // lib/models/location.dart
import 'package:latlong2/latlong.dart' show LatLng;

class EmployeeLocation {
  final bool hasPosition;
  final String trackingStatus;
  final bool statusConfirmed;
  final String userId;
  final String? name;
  final LatLng position;
  final double? battery;
  final DateTime timestamp;
  final String? avatarUrl;
  final double? speed;

  EmployeeLocation({
    this.hasPosition = true,
    this.trackingStatus = 'ok',
    this.statusConfirmed = false,
    required this.userId,
    this.name,
    required this.position,
    this.battery,
    required this.timestamp,
    this.avatarUrl,
    this.speed,
  });

  String get trackingLabel {
    String label;
    switch (trackingStatus) {
      case 'gps_disabled':
        label = 'GPS выключен';
        break;
      case 'permission_denied':
        label = 'Нет разрешения GPS';
        break;
      case 'no_fix':
        label = 'Нет свежей координаты';
        break;
      case 'poor_accuracy':
        label = 'Низкая точность GPS';
        break;
      case 'no_data':
        label = 'Координаты не получены';
        break;
      case 'stale':
        return 'Гео давно не обновлялось';
      default:
        return DateTime.now().difference(timestamp) <
                    const Duration(minutes: 3) &&
                hasPosition
            ? 'Гео обновляется'
            : 'Гео давно не обновлялось';
    }
    return statusConfirmed ? label : '$label · проверяем';
  }

  bool get geoHealthy =>
      hasPosition &&
      trackingStatus == 'ok' &&
      DateTime.now().difference(timestamp) < const Duration(minutes: 3);
}
