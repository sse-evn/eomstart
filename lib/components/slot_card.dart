import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import '../../providers/shift_provider.dart';
import '../modals/slot_setup_modal.dart';

class SlotCard extends StatefulWidget {
  const SlotCard({super.key});

  @override
  State<SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<SlotCard> with TickerProviderStateMixin {
  Timer? _timer;
  bool _isLoading = false;
  bool _showError = false;
  String _errorMessage = '';
  bool _isDataLoaded = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadInitialData();
    _startTimer();
  }

  Future<void> _loadInitialData() async {
    try {
      await Provider.of<ShiftProvider>(context, listen: false).loadShifts();
      setState(() => _isDataLoaded = true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка загрузки данных: ${e.toString()}';
        _showError = true;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (mounted) {
        try {
          await Provider.of<ShiftProvider>(context, listen: false).loadShifts();
          setState(() {});
        } catch (e) {
          setState(() {
            _errorMessage = 'Ошибка синхронизации: ${e.toString()}';
            _showError = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShiftProvider>(
      builder: (context, provider, child) {
        final theme = Theme.of(context);
        final screenWidth = MediaQuery.of(context).size.width;
        final isDarkMode = theme.brightness == Brightness.dark;

        final ActiveShift? activeShift = provider.activeShift;
        final bool hasActiveShift = activeShift != null;

        if (!_isDataLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (_showError) _buildErrorBanner(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    width: screenWidth * 0.9,
                    decoration: BoxDecoration(
                      gradient: hasActiveShift
                          ? LinearGradient(
                              colors: isDarkMode
                                  ? [Colors.green[900]!, Colors.green[800]!]
                                  : [
                                      const Color(0xFF4CAF50),
                                      const Color(0xFF2E7D32)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      border: hasActiveShift
                          ? Border.all(color: Colors.green[700]!, width: 2)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          if (hasActiveShift)
                            _buildActiveShiftUI(activeShift, theme, isDarkMode)
                          else
                            _buildInactiveShiftUI(context, theme, isDarkMode),
                          const SizedBox(height: 20),
                          _buildShiftReport(provider, theme, isDarkMode),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveShiftUI(
      ActiveShift activeShift, ThemeData theme, bool isDarkMode) {
    if (activeShift.startTimeString == null || activeShift.startTime == null) {
      return const Text(
        'Ошибка: Данные активной смены не определены',
        style: TextStyle(color: Colors.white),
      );
    }

    final duration = DateTime.now().difference(activeShift.startTime!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final timeString = '$hours ч $minutes мин';

    final serverTime = extractTimeFromIsoString(activeShift.startTimeString);

    return Column(
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
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Вы на смене',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            FloatingActionButton(
              backgroundColor: Colors.red[400],
              mini: true,
              tooltip: 'Завершить смену',
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.power_settings_new, color: Colors.white),
              onPressed: _isLoading ? null : () => _confirmEndSlot(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.green[100]!.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem('Начало', serverTime, theme, Colors.white),
              _buildInfoItem('Время работы', timeString, theme, Colors.white),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInactiveShiftUI(
      BuildContext context, ThemeData theme, bool isDarkMode) {
    return InkWell(
      onTap: () => _openSlotSetupModal(context),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
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
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.green[800]! : Colors.green[100]!,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right,
                color: isDarkMode ? Colors.green[300]! : Colors.green[600]!,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftReport(
      ShiftProvider provider, ThemeData theme, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.report,
            size: 24,
            color: isDarkMode ? Colors.grey[400]! : Colors.grey[600]!,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.shiftHistory.isEmpty
                  ? 'Нет данных о предыдущих сменах'
                  : 'Последняя смена: ${DateFormat.yMd().format(provider.shiftHistory.last.date)}',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[300]! : Colors.grey[800]!,
              ),
            ),
          ),
        ],
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
              ?.copyWith(color: color.withOpacity(0.8)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: () => setState(() => _showError = false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEndSlot(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить смену?'),
        content: const Text('Вы уверены, что хотите завершить текущую смену?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await Provider.of<ShiftProvider>(context, listen: false).endSlot();
      } catch (e) {
        setState(() {
          _errorMessage = 'Ошибка при завершении смены: ${e.toString()}';
          _showError = true;
        });
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openSlotSetupModal(BuildContext context) async {
    try {
      final result = await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => const SlotSetupModal(),
      );

      if (result == true && mounted) {
        await Provider.of<ShiftProvider>(context, listen: false).loadShifts();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка при старте смены: ${e.toString()}';
        _showError = true;
      });
    }
  }
}
