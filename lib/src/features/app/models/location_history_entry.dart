import 'package:latlong2/latlong.dart';

class LocationHistoryEntry {
  final LatLng position;
  final DateTime timestamp;
  final double? battery;

  LocationHistoryEntry({
    required this.position,
    required this.timestamp,
    this.battery,
  });
}
