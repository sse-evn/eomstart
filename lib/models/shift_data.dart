class ShiftData {
  final DateTime date;

  final String selectedSlot;
  final String workedTime;
  final String workPeriod;
  final String transportStatus;
  final int newTasks; // Должен быть int
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
      date: DateTime.parse(json['date']),
      selectedSlot: json['selected_slot'] ?? '',
      workedTime: json['worked_time'] ?? '',
      workPeriod: json['work_period'] ?? '',
      transportStatus: json['transport_status'] ?? 'Транспорт не указан',
      newTasks:
          json['new_tasks'] is int ? json['new_tasks'] : 0, // Защита от null
      isActive: json['is_active'] is bool
          ? json['is_active']
          : false, // Защита от null
      startTime: json['start_time'] is String
          ? json['start_time']
          : DateTime.now().toIso8601String(), // Защита от null
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
