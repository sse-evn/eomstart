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
      userID: json['user_id'],
      username: json['username'],
      lat: json['lat'],
      lng: json['lng'],
      timestamp: DateTime.parse(json['timestamp']),
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
