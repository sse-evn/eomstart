// lib/components/report_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'calendar_widget.dart';
import 'info_row.dart';
import 'period_card.dart';
import '../../providers/shift_provider.dart';
import '../../models/shift_data.dart';

class ReportCard extends StatefulWidget {
  const ReportCard({super.key});

  @override
  State<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  bool _isDayMode = true;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShiftProvider>();
    final shiftHistory = provider.shiftHistory;

    final ShiftData? shiftData = shiftHistory.firstWhereOrNull((s) =>
        s.date.year == provider.selectedDate.year &&
        s.date.month == provider.selectedDate.month &&
        s.date.day == provider.selectedDate.day);

    final now = DateTime.now();
    final calendarDays =
        List.generate(9, (i) => now.subtract(Duration(days: 4 - i)));

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildToggleMode(),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isDayMode
                ? Column(
                    key: const ValueKey<bool>(true),
                    children: [
                      CalendarWidget(
                        days: calendarDays,
                        selectedDate: provider.selectedDate,
                        onDateSelected: provider.selectDate,
                      ),
                      const SizedBox(height: 20),
                      shiftData != null
                          ? _buildShiftDetails(shiftData)
                          : _buildNoData(),
                    ],
                  )
                : const PeriodCard(
                    key: ValueKey<bool>(false),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleMode() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isDayMode = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _isDayMode ? Colors.green[600] : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Center(
                  child: Text(
                    'День',
                    style: TextStyle(
                      color: _isDayMode ? Colors.white : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isDayMode = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_isDayMode ? Colors.green[600] : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Center(
                  child: Text(
                    'Период',
                    style: TextStyle(
                      color: !_isDayMode ? Colors.white : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftDetails(ShiftData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          const Divider(),
          InfoRow(label: 'По задачнику ТС', value: data.newTasks.toString()),
          InfoRow(label: 'Выбранный слот', value: data.selectedSlot),
          InfoRow(label: 'Время работы', value: data.workedTime),
          InfoRow(label: 'Период работы', value: data.workPeriod),
        ],
      ),
    );
  }

  Widget _buildNoData() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Center(
        child: Text(
          'Отчет по смене отсутствует',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
