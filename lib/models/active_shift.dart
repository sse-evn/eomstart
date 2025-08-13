class ActiveShift {
  final int id;
  final int userId;
  final String username;
  final String slotTimeRange;
  final String position;
  final String zone;
  final DateTime startTime;
  final bool isActive;
  final String selfie;

  ActiveShift({
    required this.id,
    required this.userId,
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
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse('${json['user_id']}') ?? 0,
      username: json['username']?.toString() ?? '',
      slotTimeRange: json['slot_time_range']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      selfie: json['selfie']?.toString() ?? '',
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
      'user_id': userId,
      'username': username,
      'slot_time_range': slotTimeRange,
      'position': position,
      'zone': zone,
      'start_time': startTime.toIso8601String(),
      'is_active': isActive,
      'selfie': selfie,
    };
  }
}

class ShiftData {
  final DateTime date;
  final String selectedSlot;
  final String workedTime;
  final String workPeriod;
  final String transportStatus;
  final int newTasks;
  final bool isActive;
  final String startTime;

  ShiftData({
    required this.date,
    required this.selectedSlot,
    required this.workedTime,
    required this.workPeriod,
    required this.transportStatus,
    required this.newTasks,
    required this.isActive,
    required this.startTime,
  });

  factory ShiftData.fromJson(Map<String, dynamic> json) {
    return ShiftData(
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      selectedSlot: json['selected_slot']?.toString() ?? '',
      workedTime: json['worked_time']?.toString() ?? '',
      workPeriod: json['work_period']?.toString() ?? '',
      transportStatus:
          json['transport_status']?.toString() ?? 'Транспорт не указан',
      newTasks: json['new_tasks'] is int
          ? json['new_tasks'] as int
          : int.tryParse('${json['new_tasks']}') ?? 0,
      isActive: json['is_active'] is bool ? json['is_active'] as bool : false,
      startTime: json['start_time'] is String
          ? json['start_time'] as String
          : DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'selected_slot': selectedSlot,
      'worked_time': workedTime,
      'work_period': workPeriod,
      'transport_status': transportStatus,
      'new_tasks': newTasks,
      'is_active': isActive,
      'start_time': startTime,
    };
  }
}
