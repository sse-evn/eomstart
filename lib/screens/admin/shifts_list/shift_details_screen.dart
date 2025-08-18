// lib/screens/admin/shifts_list/shift_details_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/services/api_service.dart';
// Импорт для работы с временными зонами
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:provider/provider.dart'; // Добавлено
import 'package:micro_mobility_app/providers/shift_provider.dart'; // Добавлено

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

  Future<void> _forceEndShift() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить смену сотрудника?'),
        content: Text(
            'Вы уверены, что хотите завершить смену для "${widget.shift.username}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да, завершить',
                style: TextStyle(color: Colors.red)),
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

      // Показываем успех и закрываем экран
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Смена завершена'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // Вернём true, если нужно обновить список

        // Обновляем данные в ShiftProvider
        Provider.of<ShiftProvider>(context, listen: false).loadShifts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали смены'),
        backgroundColor: Colors.blue,
        elevation: 1,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Сотрудник
                  const Text(
                    'Сотрудник:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.shift.username,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Фото
                  const Text(
                    'Фото смены',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => Dialog(
                          backgroundColor: Colors.black,
                          child: Stack(
                            children: [
                              InteractiveViewer(
                                child: Image.network(
                                  'https://eom-sharing.duckdns.org${widget.shift.selfie}', // Исправлено
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  },
                                  errorBuilder: (_, __, ___) => const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.error,
                                          color: Colors.red, size: 48),
                                      Text('Фото не загружено',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 20,
                                right: 20,
                                child: IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          'https://eom-sharing.duckdns.org${widget.shift.selfie}', // Исправлено
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                                child: CircularProgressIndicator());
                          },
                          errorBuilder: (_, __, ___) => const Icon(Icons.person,
                              size: 100, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Информация о смене
                  const Text(
                    'Информация о смене',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildInfoRow('Позиция', widget.shift.position),
                  _buildInfoRow('Зона', widget.shift.zone),
                  _buildInfoRow('Слот времени', widget.shift.slotTimeRange),
                  // Используем форматирование времени с секундами напрямую из startTime
                  _buildInfoRow(
                      'Начало смены',
                      widget.shift.startTime != null
                          ? widget.shift.startTime!.formatTimeDateWithSeconds()
                          : 'Нет данных'),
                  _buildInfoRow(
                      'ID сотрудника', widget.shift.userId.toString()),

                  const SizedBox(height: 32),

                  // Кнопка завершения (только для superadmin)
                  if (_currentUserRole == 'superadmin')
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _forceEndShift,
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(
                          _isLoading ? 'Завершение...' : 'Завершить смену'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130, // Увеличил ширину для размещения "Начало смены:"
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// Расширение для форматирования времени с секундами
extension TimeFormat on DateTime {
  String formatTimeDateWithSeconds() {
    final date =
        '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}';
    final time =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
