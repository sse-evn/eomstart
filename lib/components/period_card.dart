import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'info_row.dart';
import '../../providers/shift_provider.dart';

class PeriodCard extends StatelessWidget {
  const PeriodCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShiftProvider>();
    final shiftHistory = provider.shiftHistory;

    final totalShifts = shiftHistory.length;

    final totalMinutes = shiftHistory.fold<int>(0, (sum, shift) {
      if (shift.startTime != null && shift.endTime != null) {
        return sum + shift.endTime!.difference(shift.startTime!).inMinutes;
      }
      return sum;
    });

    final totalHours = totalMinutes ~/ 60;
    final remainingMinutes = totalMinutes % 60;
    final formattedTime =
        '$totalHours ч ${remainingMinutes.toString().padLeft(2, '0')} мин';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          const Text(
            'Отчет за период',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          InfoRow(label: 'Количество смен', value: totalShifts.toString()),
          InfoRow(label: 'Общее время работы', value: formattedTime),
        ],
      ),
    );
  }
}
