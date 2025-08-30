import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'calendar_widget.dart';
import 'info_row.dart';
import 'period_card.dart';
import 'bot_stats_card.dart';
import '../../providers/shift_provider.dart';
import '../../models/shift_data.dart';

class ReportCard extends StatefulWidget {
  const ReportCard({super.key});

  @override
  State<ReportCard> createState() => _ReportCardState();
}

enum ReportMode { day, period, bot }

class _ReportCardState extends State<ReportCard> {
  ReportMode _currentMode = ReportMode.day;
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShiftProvider>();
    final shiftHistory = provider.shiftHistory;

    final selectedDay = provider.selectedDate;
    final shiftData = shiftHistory.firstWhereOrNull((s) =>
        s.date.year == selectedDay.year &&
        s.date.month == selectedDay.month &&
        s.date.day == selectedDay.day);

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
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToggleMode(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _isRefreshing
                    ? null
                    : () async {
                        setState(() => _isRefreshing = true);
                        try {
                          if (_currentMode == ReportMode.bot) {
                            await provider.fetchBotStats();
                          } else {
                            await provider.loadShifts();
                          }
                        } catch (e) {
                          debugPrint('Refresh failed: $e');
                        } finally {
                          if (mounted) {
                            setState(() => _isRefreshing = false);
                          }
                        }
                      },
              ),
            ],
          ),
          _isRefreshing
              ? const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: Colors.green,
                )
              : const SizedBox(height: 2),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: _buildContentForMode(
                _currentMode, shiftData, calendarDays, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleMode() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentMode = ReportMode.day),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: _currentMode == ReportMode.day
                        ? const LinearGradient(
                            colors: [
                              Color.fromARGB(255, 18, 120, 118),
                              Color.fromARGB(255, 63, 114, 66),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: _currentMode == ReportMode.day
                        ? null
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: _currentMode == ReportMode.day
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      child: const Text('День'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentMode = ReportMode.period),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: _currentMode == ReportMode.period
                        ? const LinearGradient(
                            colors: [
                              Color.fromARGB(255, 18, 120, 118),
                              Color.fromARGB(255, 63, 114, 66),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: _currentMode == ReportMode.period
                        ? null
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: _currentMode == ReportMode.period
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      child: const Text('Период'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentMode = ReportMode.bot),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: _currentMode == ReportMode.bot
                        ? const LinearGradient(
                            colors: [
                              Color.fromARGB(255, 18, 120, 118),
                              Color.fromARGB(255, 63, 114, 66),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: _currentMode == ReportMode.bot
                        ? null
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: _currentMode == ReportMode.bot
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      child: const Text('Бот'),
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
        return const BotStatsCard(key: ValueKey('bot-mode'));
    }
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
            offset: Offset(0, 4),
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
