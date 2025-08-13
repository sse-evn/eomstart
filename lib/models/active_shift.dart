class ActiveShift {
  final int id;
  final String username;
  final String slotTimeRange;
  final String position;
  final String zone;
  final DateTime startTime;
  final bool isActive;
  final String selfie; // Добавлено

  ActiveShift({
    required this.id,
    required this.username,
    required this.slotTimeRange,
    required this.position,
    required this.zone,
    required this.startTime,
    required this.isActive,
    required this.selfie,
  });

  factory ActiveShift.fromJson(Map<String, dynamic> json) {
    return ActiveShift(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      username: json['username']?.toString() ?? '',
      slotTimeRange: json['slot_time_range']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      selfie: json['selfie'] ?? '',
      startTime: DateTime.tryParse(json['start_time']?.toString() ?? '') ??
          DateTime.now(),
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active']?.toString().toLowerCase() == 'true'),
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
