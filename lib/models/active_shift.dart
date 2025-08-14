// models/active_shift.dart
class ActiveShift {
  final int id;
  final int userId;
  final String username;
  final String slotTimeRange;
  final String position;
  final String zone;
  final DateTime? startTime;
  final bool isActive;
  final String selfie;

  ActiveShift({
    required this.id,
    required this.userId,
    required this.username,
    required this.slotTimeRange,
    required this.position,
    required this.zone,
    this.startTime,
    required this.isActive,
    required this.selfie,
  });

  factory ActiveShift.fromJson(Map<String, dynamic> json) {
    print('🔧 ActiveShift.fromJson called with: $json');

    DateTime? parsedStartTime;
    if (json['start_time'] != null) {
      if (json['start_time'] is String) {
        parsedStartTime = DateTime.tryParse(json['start_time']);
      } else if (json['start_time'] is DateTime) {
        parsedStartTime = json['start_time'];
      }
    }

    return ActiveShift(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse('${json['user_id']}') ?? 0,
      username: json['username']?.toString() ?? '',
      slotTimeRange: json['slot_time_range']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      selfie: json['selfie']?.toString() ?? '',
      startTime: parsedStartTime,
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active']?.toString().toLowerCase() == 'true'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'slot_time_range': slotTimeRange,
      'position': position,
      'zone': zone,
      'start_time': startTime?.toIso8601String(),
      'is_active': isActive,
      'selfie': selfie,
    };
  }
}
