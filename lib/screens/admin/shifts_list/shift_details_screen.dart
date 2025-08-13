// lib/screens/shift_details_screen.dart

import 'package:flutter/material.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/screens/admin/shift_monitoring_screen.dart';

class ShiftDetailsScreen extends StatelessWidget {
  final ActiveShift shift;

  const ShiftDetailsScreen({required this.shift, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали смены'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Фото
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: shift.selfie.isNotEmpty
                  ? Image.network(
                      'https://eom-sharing.duckdns.org${shift.selfie}',
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: 200,
                        color: Colors.grey[300],
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      height: 200,
                      color: Colors.grey[300],
                      child: const Icon(Icons.person, color: Colors.grey),
                    ),
            ),
            const SizedBox(height: 16),

            // Информация
            Text(
              shift.username,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),

            // Дополнительная информация
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Позиция: ${shift.position}',
                  style: const TextStyle(color: Colors.grey),
                ),
                Text(
                  'Зона: ${shift.zone}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 4),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Слот: ${shift.slotTimeRange}',
                  style: const TextStyle(color: Colors.grey),
                ),
                Text(
                  'Начало: ${shift.startTime.formatTimeDate()}',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
