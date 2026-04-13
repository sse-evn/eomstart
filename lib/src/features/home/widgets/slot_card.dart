// ====== slot_card.dart (ПОЛНЫЙ, ИСПРАВЛЕННЫЙ, НЕ УПРОЩЕННЫЙ) ======

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_state.dart';
import 'package:micro_mobility_app/src/core/utils/time_utils.dart';
import 'package:micro_mobility_app/src/features/app/models/active_shift.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:micro_mobility_app/src/core/themes/colors.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'slot_setup_modal.dart';

class SlotCard extends StatelessWidget {
  const SlotCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShiftBloc, ShiftState>(
      builder: (context, state) {
        if (state is ShiftLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final theme = Theme.of(context);
        final isDarkMode = theme.brightness == Brightness.dark;
        
        ActiveShift? activeShift;
        if (state is ShiftActive) {
          activeShift = state.shift;
        }

        final hasActiveShift = activeShift != null;

        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                decoration: BoxDecoration(
                  gradient: hasActiveShift
                      ? LinearGradient(
                          colors: isDarkMode
                              ? [Colors.green[900]!, Colors.green[800]!]
                              : [
                                  const Color.fromARGB(255, 10, 80, 79),
                                  const Color.fromARGB(255, 63, 114, 66)
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    if (hasActiveShift)
                      _buildActiveShiftUI(activeShift, theme, isDarkMode)
                    else
                      _buildInactiveShiftUI(context, theme, isDarkMode),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatLocalTime(String isoString) {
    try {
      final utcTime = DateTime.parse(isoString);
      final localTime = utcTime.toLocal();
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '--:--';
    }
  }

  Widget _buildActiveShiftUI(
      ActiveShift activeShift, ThemeData theme, bool isDarkMode) {
    final String serverTime = activeShift.startTime != null
        ? '${activeShift.startTime!.hour.toString().padLeft(2, '0')}:${activeShift.startTime!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    final String slotTime = activeShift.slotTimeRange.isNotEmpty
        ? activeShift.slotTimeRange
        : 'Не указан';

    final duration = activeShift.startTime != null 
        ? DateTime.now().difference(activeShift.startTime!)
        : const Duration();
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '$hoursч $minutesм';

    final breakTime = BreakTimeUtils.getCurrentBreakTime();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'АКТИВНАЯ СМЕНА',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Вы на смене',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              _buildSelfiePreview(activeShift),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Flexible(
                  child:
                      _buildInfoItem('Начало', serverTime, theme, Colors.white),
                ),
                Flexible(
                  child:
                      _buildInfoItem('Длит.', durationStr, theme, Colors.white),
                ),
                Flexible(
                  child: _buildInfoItem('Слот', slotTime, theme, Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildBreakStatusUI(theme, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildBreakStatusUI(ThemeData theme, bool isDarkMode) {
    final status = BreakTimeUtils.getBreakStatus();
    final bool isInside = status['isInside'] == true;
    final String label = status['label'] ?? '';
    final String range = status['range'] ?? '';

    if (range.isEmpty && !isInside) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black26 : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.fastfood,
            size: 30,
            color: isInside ? Colors.greenAccent : Colors.white70,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  range,
                  style: TextStyle(
                    fontSize: 18,
                    color: isInside ? Colors.greenAccent : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isInside && status['remainingMinutes'] != null)
                  Text(
                    'Осталось: ${status['remainingMinutes']} мин',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSelfiePreview(ActiveShift activeShift) {
    String photoUrl;
    if (activeShift.selfie.startsWith('http')) {
      photoUrl = activeShift.selfie;
    } else {
      final baseUrl = AppConfig.mediaBaseUrl;
      final path = activeShift.selfie;
      photoUrl = baseUrl.endsWith('/') ? '$baseUrl$path' : '$baseUrl/$path';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 60,
        width: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: activeShift.selfie.isNotEmpty
            ? Image.network(
                photoUrl,
                loadingBuilder: (ctx, child, loading) =>
                    loading == null ? child : const CircularProgressIndicator(),
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.error, color: Colors.white),
                fit: BoxFit.cover,
              )
            : const Icon(Icons.person, color: Colors.white),
      ),
    );
  }

  Widget _buildInactiveShiftUI(
      BuildContext context, ThemeData theme, bool isDarkMode) {
    return InkWell(
      onTap: () => _openSlotSetupModal(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.green[900]!.withOpacity(0.3)
              : Colors.green[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDarkMode ? Colors.green[700]! : Colors.green[100]!,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.green[800]! : Colors.green[100]!,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_circle_fill,
                color: isDarkMode ? Colors.green[300]! : Colors.green[700]!,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Начать новую смену',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.green[100]! : Colors.green[800]!,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDarkMode ? Colors.green[300]! : Colors.green[600]!,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
      String title, String value, ThemeData theme, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: color.withOpacity(0.8), fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ✅ ИСПРАВЛЕНО: Правильный контекст для showModalBottomSheet
  // Используем context из build, а не из Consumer — это решает проблему "не открывается"
  Future<void> _openSlotSetupModal(BuildContext context) async {
    try {
      // 🚨 КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: Используем контекст, переданный в build, а не context из Consumer
      // Это гарантирует, что контекст имеет доступ к Navigator
      final result = await showModalBottomSheet(
        context: context, // ✅ ИСПРАВЛЕНО — ИСПОЛЬЗУЕМ ПРАВИЛЬНЫЙ CONTEXT
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) =>
            const SlotSetupModal(), // ✅ Статичный виджет, без контекста
      );

      if (result == true) {
        // Перезагружаем данные через Provider
        await Provider.of<ShiftProvider>(context, listen: false).loadShifts();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка открытия смены: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
