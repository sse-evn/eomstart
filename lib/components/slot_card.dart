// lib/screens/dashboard/components/slot_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../modals/slot_setup_modal.dart';
import '../../../providers/shift_provider.dart';

class SlotCard extends StatelessWidget {
  const SlotCard({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Только нужные поля — не перестраиваем весь экран
    final slotState = context.select((ShiftProvider p) => p.slotState);
    final activeDuration =
        context.select((ShiftProvider p) => p.activeDuration);

    if (slotState == SlotState.active) {
      final startTime =
          DateTime.now().subtract(Duration(seconds: activeDuration));
      final timeString = _formatDuration(activeDuration);

      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.green[700],
          borderRadius: BorderRadius.circular(15.0),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Активный слот',
                        style:
                            TextStyle(color: Colors.green[100], fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Слот активен',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                GestureDetector(
                  onTap: () => _confirmEndSlot(context),
                  child: const Icon(Icons.power_settings_new,
                      color: Colors.white, size: 40),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white54),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfo(
                    'Слот активен',
                    '${DateFormat('HH:mm').format(startTime)} – сейчас',
                    Colors.white),
                _buildInfo('Время работы', timeString, Colors.white),
              ],
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () => _openSlotSetupModal(context),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15.0),
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, color: Colors.green[700]),
                  const SizedBox(width: 10),
                  Text('Начать слот',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700])),
                ],
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildInfo(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 14)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}ч ${m}мин';
  }

  void _confirmEndSlot(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить слот?'),
        content: const Text('Вы уверены? Это действие нельзя отменить.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ShiftProvider>().endSlot();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
  }

  void _openSlotSetupModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const SlotSetupModal(),
    );
  }
}
