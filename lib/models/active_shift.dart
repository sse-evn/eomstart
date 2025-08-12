// lib/models/active_shift.dart

class ActiveShift {
  final int id;
  final String username;
  final String slotTimeRange;
  final String position;
  final String zone;
  final DateTime startTime;
  final bool isActive;

  ActiveShift({
    required this.id,
    required this.username,
    required this.slotTimeRange,
    required this.position,
    required this.zone,
    required this.startTime,
    required this.isActive,
  });

  factory ActiveShift.fromJson(Map<String, dynamic> json) {
    return ActiveShift(
      id: json['id'] as int,
      username: json['username'] as String,
      slotTimeRange: json['slot_time_range'] as String,
      position: json['position'] as String,
      zone: json['zone'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      isActive: json['is_active'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'slot_time_range': slotTimeRange,
      'position': position,
      'zone': zone,
      'start_time': startTime.toIso8601String(),
      'is_active': isActive,
    };
  }
}
