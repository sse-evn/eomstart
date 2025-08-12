import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../modals/slot_setup_modal.dart';
import '../../../providers/shift_provider.dart';

class SlotCard extends StatelessWidget {
  const SlotCard({super.key});

  @override
  Widget build(BuildContext context) {
    final slotState = context.select((ShiftProvider p) => p.slotState);
    final activeDuration =
        context.select((ShiftProvider p) => p.activeDuration);

    if (slotState == SlotState.active) {
      final startTime =
          DateTime.now().subtract(Duration(seconds: activeDuration));
      final timeString = _formatDuration(activeDuration);
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green[700]!, Colors.green[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.green.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5)),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Активный слот',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Слот активен',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ]),
                GestureDetector(
                  onTap: () => _confirmEndSlot(context),
                  child: const CircleAvatar(
                    backgroundColor: Colors.red,
                    radius: 24,
                    child: Icon(Icons.power_settings_new, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfo('Слот активен',
                    '${DateFormat('HH:mm').format(startTime)} – сейчас'),
                _buildInfo('Время работы', timeString),
              ],
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () => _openSlotSetupModal(context),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 8)
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.play_circle_fill,
                    color: Colors.green[700], size: 32),
                const SizedBox(width: 12),
                const Text('Начать слот',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildInfo(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
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
        content: const Text('Вы уверены?'),
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
