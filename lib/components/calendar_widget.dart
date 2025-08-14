// lib/components/calendar_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CalendarWidget extends StatelessWidget {
  final List<DateTime> days;
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;

  const CalendarWidget({
    Key? key,
    required this.days,
    required this.selectedDate,
    required this.onDateSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days.map((day) {
        final isSelected = day.year == selectedDate.year &&
            day.month == selectedDate.month &&
            day.day == selectedDate.day;

        return Expanded(
          child: GestureDetector(
            onTap: () => onDateSelected(day),
            child: SizedBox(
              height: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E', 'ru').format(day).toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateFormat('d').format(day),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
