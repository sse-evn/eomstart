class ShiftData {
  final DateTime date;
  final String selectedSlot;
  final String workedTime;
  final String workPeriod;
  final String transportStatus;
  final int newTasks;

  ShiftData({
    required this.date,
    required this.selectedSlot,
    required this.workedTime,
    required this.workPeriod,
    required this.transportStatus,
    required this.newTasks,
  });

  factory ShiftData.fromJson(Map<String, dynamic> json) {
    return ShiftData(
      date: DateTime.parse(json['date']),
      selectedSlot: json['selected_slot'],
      workedTime: json['worked_time'],
      workPeriod: json['work_period'],
      transportStatus: json['transport_status'],
      newTasks: json['new_tasks'],
    );
  }
}
