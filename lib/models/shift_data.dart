class ShiftData {
  final DateTime date;
  final String selectedSlot;
  final String workedTime;
  final String workPeriod;
  final String transportStatus;
  final int newTasks;
  final bool isActive; // ✅ Добавлено
  final String startTime; // ✅ Добавлено (в виде строки ISO)

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
      newTasks: json['new_tasks'] ?? 0,
      isActive: json['is_active'] as bool? ?? false,
      startTime:
          json['start_time'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}
