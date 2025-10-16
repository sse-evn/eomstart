// lib/screens/admin/shifts_list/shift_details_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/config.dart' show AppConfig;
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';
import 'package:micro_mobility_app/utils/time_utils.dart';
import 'package:micro_mobility_app/config/google_sheets_config.dart';

class ShiftDetailsScreen extends StatefulWidget {
  final ActiveShift shift;

  const ShiftDetailsScreen({required this.shift, Key? key}) : super(key: key);

  @override
  State<ShiftDetailsScreen> createState() => _ShiftDetailsScreenState();
}

class _ShiftDetailsScreenState extends State<ShiftDetailsScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  String? _currentUserRole;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final profile = await _apiService.getUserProfile(token);
      final role = (profile['role'] ?? 'user').toString().toLowerCase();

      if (mounted) {
        setState(() {
          _currentUserRole = role;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    }
  }

  // ✅ Принудительное завершение смены
  Future<void> _forceEndShift() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '⚠️ Завершить смену?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Вы уверены, что хотите завершить смену для "${widget.shift.username}"? Это действие нельзя отменить.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Да, завершить',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.forceEndShift(token, widget.shift.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Смена успешно завершена'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
        Provider.of<ShiftProvider>(context, listen: false).loadShifts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: ${e.toString().split('.').first}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Расчёт длительности
  Duration? _getDuration() {
    if (widget.shift.startTimeString == null) return null;
    final start = DateTime.parse(widget.shift.startTimeString!);
    final end = widget.shift.endTimeString != null
        ? DateTime.parse(widget.shift.endTimeString!)
        : DateTime.now();
    return end.difference(start);
  }

  // ✅ Форматирование длительности
  String _formatDuration(Duration? duration) {
    if (duration == null) return '–';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours ч $minutes мин';
  }

  // ✅ Расчёт оплаты
  String _calculatePayment() {
    final duration = _getDuration();
    if (duration == null) return '–';

    final hours = duration.inHours + duration.inMinutes.remainder(60) / 60.0;
    final payment = hours * GoogleSheetsConfig.hourlyRate;
    return '${payment.toStringAsFixed(0)} ${GoogleSheetsConfig.currency}';
  }

  // ✅ Формат даты (используем готовую функцию из time_utils)
  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '–';
    return extractDateFromIsoString(isoString);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final primaryColor = theme.primaryColor;

    final bool isEnded = widget.shift.endTimeString != null;
    final Color statusColor = isEnded ? Colors.green : Colors.orange;
    final duration = _getDuration();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Детали смены',
          style: textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: primaryColor,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 🧑‍💼 Карточка пользователя
                    _buildUserCard(context, theme, primaryColor, isEnded,
                        statusColor, duration),

                    const SizedBox(height: 24),

                    // 📸 Фото с начала смены
                    _buildSelfieSection(context, theme),

                    const SizedBox(height: 24),

                    // 📊 Основная информация
                    _buildInfoSection(context, theme, primaryColor),

                    const SizedBox(height: 24),

                    // 💰 Расчёт оплаты
                    _buildPaymentSection(
                        context, theme, primaryColor, duration),

                    const SizedBox(height: 24),

                    // ⚠️ Админ-действия
                    if (_currentUserRole == 'superadmin')
                      _buildAdminAction(primaryColor),
                  ]),
                ),
              ),
            ],
          ),
          if (_isLoading)
            IgnorePointer(
              ignoring: true,
              child: Container(
                color: Colors.black.withOpacity(0.2),
                child: const Center(
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(),
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

  Widget _buildUserCard(
    BuildContext context,
    ThemeData theme,
    Color primaryColor,
    bool isEnded,
    Color statusColor,
    Duration? duration,
  ) {
    final photoUrl = '${AppConfig.mediaBaseUrl}${widget.shift.selfie}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.grey[300],
            backgroundImage: NetworkImage(photoUrl),
            child: widget.shift.selfie.isEmpty
                ? const Icon(Icons.person, size: 40, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.shift.username,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.shift.position} • ${widget.shift.zone}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor, width: 1),
                      ),
                      child: Text(
                        isEnded ? 'Завершена' : 'Активна',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfieSection(BuildContext context, ThemeData theme) {
    final photoUrl = '${AppConfig.mediaBaseUrl}${widget.shift.selfie}';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Фото с начала смены',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => Dialog(
                  backgroundColor: Colors.black,
                  insetPadding: const EdgeInsets.all(20),
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        child: Image.network(
                          photoUrl,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                                child: CircularProgressIndicator());
                          },
                          errorBuilder: (_, __, ___) => const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error, color: Colors.red, size: 48),
                              Text('Фото недоступно',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 40,
                        right: 20,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Image.network(
                photoUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  color: Colors.grey[200],
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      Text('Фото не загружено',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
      BuildContext context, ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Информация о смене',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Позиция', widget.shift.position, primaryColor),
          _buildInfoRow('Зона', widget.shift.zone, primaryColor),
          _buildInfoRow(
              'Слот времени', widget.shift.slotTimeRange, primaryColor),
          _buildInfoRow('Дата начала',
              _formatDate(widget.shift.startTimeString), primaryColor),
          _buildInfoRow(
              'Время начала',
              extractTimeFromIsoString(widget.shift.startTimeString),
              primaryColor),
          if (widget.shift.endTimeString != null)
            _buildInfoRow(
                'Время окончания',
                extractTimeFromIsoString(widget.shift.endTimeString),
                primaryColor),
          _buildInfoRow(
              'ID сотрудника', widget.shift.userId.toString(), primaryColor),
        ],
      ),
    );
  }

  Widget _buildPaymentSection(BuildContext context, ThemeData theme,
      Color primaryColor, Duration? duration) {
    if (duration == null) return Container();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Расчёт оплаты',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
              'Длительность', _formatDuration(duration), Colors.green),
          _buildInfoRow(
            'Ставка',
            '${GoogleSheetsConfig.hourlyRate.toStringAsFixed(0)} ${GoogleSheetsConfig.currency}/час',
            Colors.green,
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.green[300]),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Итого к оплате',
            _calculatePayment(),
            Colors.green[800]!,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
              softWrap: true,
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminAction(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            '⚠️ Только для суперадмина',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _forceEndShift,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: Text(
                _isLoading ? 'Завершение...' : 'Принудительно завершить смену',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
