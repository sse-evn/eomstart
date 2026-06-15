import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shift_provider.dart';
import 'dart:ui' as ui;
import '../../../core/services/advice_service.dart';

class DashboardInterestingThings extends StatelessWidget {
  const DashboardInterestingThings({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final advice = AdviceService.getDailyAdvice();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            tr(context, 'СОВЕТЫ', 'КЕҢЕСТЕР'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface.withOpacity(0.5),
              letterSpacing: 1.5,
            ),
          ),
        ),
        SizedBox(height: 8),
        _buildTipCard(context, advice),
        SizedBox(height: 12),
        _buildLastReportCard(context),
      ],
    );
  }

  Widget _buildTipCard(BuildContext context, DailyAdvice advice) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          // Glass background
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.1),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.lightbulb_outline_rounded,
                      color: colorScheme.primary),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'Совет дня', 'Күн кеңесі'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        tr(context, advice.text, advice.translation ?? advice.text),
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastReportCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ShiftProvider>();
    final lastReportTime = provider.lastReportTime;

    if (lastReportTime == null) return const SizedBox.shrink();

    final timeStr = '${lastReportTime.hour.toString().padLeft(2, '0')}:${lastReportTime.minute.toString().padLeft(2, '0')}:${lastReportTime.second.toString().padLeft(2, '0')}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          // Glass background
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.1),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.check_circle_outline,
                      color: colorScheme.primary),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'Отчёт доставлен', 'Есеп жеткізілді'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${tr(context, 'Последняя отправка:', 'Соңғы жіберілген уақыт:')} в $timeStr',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
