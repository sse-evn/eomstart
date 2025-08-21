// lib/models/location.dart
class Location {
  final int userID;
  final String username;
  final double lat;
  final double lng;
  final DateTime timestamp;

  Location({
    required this.userID,
    required this.username,
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      userID: json['user_id'] as int,
      username: json['username'] as String,
      lat: json['lat'] as double,
      lng: json['lng'] as double,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userID,
        'username': username,
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp.toIso8601String(),
      };
}
