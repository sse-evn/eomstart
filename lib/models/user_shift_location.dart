// lib/models/user_shift_location.dart
class UserShiftLocation {
  final int userId;
  final String username;
  final String position;
  final String zone;
  final DateTime startTime;
  final double? lat;
  final double? lng;
  final DateTime? timestamp;
  final bool hasLocation;

  UserShiftLocation({
    required this.userId,
    required this.username,
    required this.position,
    required this.zone,
    required this.startTime,
    this.lat,
    this.lng,
    this.timestamp,
    required this.hasLocation,
  });

  factory UserShiftLocation.fromJson(Map<String, dynamic> json) {
    return UserShiftLocation(
      userId: json['user_id'],
      username: json['username'],
      position: json['position'],
      zone: json['zone'],
      startTime: DateTime.parse(json['start_time']),
      lat: json['lat']?.toDouble(),
      lng: json['lng']?.toDouble(),
      timestamp:
          json['timestamp'] != null ? DateTime.parse(json['timestamp']) : null,
      hasLocation: json['has_location'] ?? false,
    );
  }
}
