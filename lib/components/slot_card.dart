import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import '../../providers/shift_provider.dart';
import '../modals/slot_setup_modal.dart';
import '../../utils/time_utils.dart';
import '../config/config.dart';

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
      if (mounted) {
        setState(() => _isDataLoaded = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка загрузки данных: ${e.toString()}';
          _showError = true;
        });
      }
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
        final isDarkMode = theme.brightness == Brightness.dark;
        final activeShift = provider.activeShift;
        final hasActiveShift = activeShift != null;

        if (!_isDataLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            if (_showError) _buildErrorBanner(),
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
                                  const Color.fromARGB(255, 10, 80, 79)!,
                                  const Color.fromARGB(255, 63, 114, 66)!
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey,
                      spreadRadius: 1,
                      blurRadius: 12,
                      offset: const Offset(4, 4),
                    ),
                  ],
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveShiftUI(
      ActiveShift activeShift, ThemeData theme, bool isDarkMode) {
    final String serverTime = activeShift.startTimeString != null
        ? extractTimeFromIsoString(activeShift.startTimeString!)
        : '--:--';

    final String slotTime = activeShift.slotTimeRange.isNotEmpty
        ? activeShift.slotTimeRange
        : 'Не указан';

    if (activeShift.startTimeString == null) {
      return Text(
        'Время начала неизвестно',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
      );
    }

    final startTime = DateTime.parse(activeShift.startTimeString!);
    final duration = DateTime.now().difference(startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '${hours}ч ${minutes}м';

    return Column(
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
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.red[400],
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : const Icon(Icons.power_settings_new,
                      color: Colors.white, size: 20),
            ),
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
        _buildSelfiePreview(activeShift),
      ],
    );
  }

  Widget _buildSelfiePreview(ActiveShift activeShift) {
    final photoUrl = '${AppConfig.mediaBaseUrl}${activeShift.selfie}';

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
              onPressed: () {
                if (mounted) {
                  setState(() => _showError = false);
                }
              },
            ),
          ],
        ),
      ),
    );
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
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка: ${e.toString()}';
          _showError = true;
        });
      }
    }
  }
}
