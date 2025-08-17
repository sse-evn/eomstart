import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'calendar_widget.dart';
import 'info_row.dart';
import 'period_card.dart';
// === ДОБАВЛЕНО: Импорт виджета для статистики бота ===
import 'bot_stats_card.dart';
import '../../providers/shift_provider.dart';
import '../../models/shift_data.dart';

class ReportCard extends StatefulWidget {
  const ReportCard({super.key});

  @override
  State<ReportCard> createState() => _ReportCardState();
}

// === ИЗМЕНЕНО: Добавлено третье состояние ===
enum ReportMode { day, period, bot }

class _ReportCardState extends State<ReportCard> {
  // === ИЗМЕНЕНО: Используем enum вместо bool ===
  ReportMode _currentMode = ReportMode.day;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShiftProvider>();
    final shiftHistory = provider.shiftHistory;

    // Найти данные за выбранный день
    final shiftData = shiftHistory.firstWhereOrNull((s) =>
        s.date.year == provider.selectedDate.year &&
        s.date.month == provider.selectedDate.month &&
        s.date.day == provider.selectedDate.day);

    // Генерация дней для календаря (текущий день по центру)
    final now = DateTime.now();
    final calendarDays =
        List.generate(9, (i) => now.subtract(Duration(days: 4 - i)));

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToggleMode(), // Обновленный переключатель
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            // === ИЗМЕНЕНО: Логика переключения между тремя видами ===
            child: _buildContentForMode(
                _currentMode, shiftData, calendarDays, provider),
          ),
        ],
      ),
    );
  }

  // === ДОБАВЛЕНО: Метод для построения контента в зависимости от режима ===
  Widget _buildContentForMode(
    ReportMode mode,
    ShiftData? shiftData,
    List<DateTime> calendarDays,
    ShiftProvider provider,
  ) {
    switch (mode) {
      case ReportMode.day:
        return Column(
          key: const ValueKey('day-mode'),
          children: [
            CalendarWidget(
              days: calendarDays,
              selectedDate: provider.selectedDate,
              onDateSelected: provider.selectDate,
            ),
            const SizedBox(height: 20),
            shiftData != null ? _buildShiftDetails(shiftData) : _buildNoData(),
          ],
        );
      case ReportMode.period:
        return const PeriodCard(key: ValueKey('period-mode'));
      case ReportMode.bot:
        // === ДОБАВЛЕНО: Виджет статистики бота ===
        return const BotStatsCard(key: ValueKey('bot-mode'));
    }
  }

  // === ИЗМЕНЕНО: Обновленный переключатель с тремя кнопками ===
  Widget _buildToggleMode() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Кнопка "День"
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentMode = ReportMode.day),
              child: Container(
                decoration: BoxDecoration(
                  color: _currentMode == ReportMode.day
                      ? Colors.green
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'День',
                    style: TextStyle(
                      color: _currentMode == ReportMode.day
                          ? Colors.white
                          : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Кнопка "Период"
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentMode = ReportMode.period),
              child: Container(
                decoration: BoxDecoration(
                  color: _currentMode == ReportMode.period
                      ? Colors.green
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Период',
                    style: TextStyle(
                      color: _currentMode == ReportMode.period
                          ? Colors.white
                          : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // === ДОБАВЛЕНО: Кнопка "Бот" ===
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentMode = ReportMode.bot),
              child: Container(
                decoration: BoxDecoration(
                  color: _currentMode == ReportMode.bot
                      ? Colors.green
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Бот',
                    style: TextStyle(
                      color: _currentMode == ReportMode.bot
                          ? Colors.white
                          : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Данные за день',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: Colors.grey),
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
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text(
          'Данные за этот день отсутствуют',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
