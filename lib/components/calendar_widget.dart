// lib/screens/dashboard/components/calendar_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CalendarWidget extends StatelessWidget {
  final List<DateTime> days;
  final DateTime selectedDate;
  final void Function(DateTime) onDateSelected;

  const CalendarWidget({
    super.key,
    required this.days,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days.map((date) {
        final isActive = date.year == selectedDate.year &&
            date.month == selectedDate.month &&
            date.day == selectedDate.day;
        return GestureDetector(
          onTap: () => onDateSelected(date),
          child: Column(
            children: [
              Text(DateFormat('EE', 'ru').format(date),
                  style: TextStyle(
                      color: isActive ? Colors.green[700] : Colors.black54,
                      fontSize: 12)),
              const SizedBox(height: 5),
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                    color: isActive ? Colors.green[700] : Colors.transparent,
                    borderRadius: BorderRadius.circular(10)),
                child: Center(
                  child: Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                        color: isActive ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
