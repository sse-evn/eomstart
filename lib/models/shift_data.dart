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
      startTime:
          json['start_time']?.toString() ?? DateTime.now().toIso8601String(),
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
