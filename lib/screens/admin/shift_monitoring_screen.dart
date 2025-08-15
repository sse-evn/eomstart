// lib/screens/admin/shift_monitoring_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/screens/admin/shifts_list/shift_details_screen.dart';

class ShiftMonitoringScreen extends StatefulWidget {
  const ShiftMonitoringScreen({super.key});

  @override
  State<ShiftMonitoringScreen> createState() => _ShiftMonitoringScreenState();
}

class _ShiftMonitoringScreenState extends State<ShiftMonitoringScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<ActiveShift>> _shiftsFuture;

  @override
  void initState() {
    super.initState();
    _shiftsFuture = _fetchActiveShifts();
  }

  Future<List<ActiveShift>> _fetchActiveShifts() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      // ✅ Исправлен URL (убраны пробелы)
      final response = await http.get(
        Uri.parse('https://eom-sharing.duckdns.org/api/admin/active-shifts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic jsonResponse = jsonDecode(
            utf8.decode(response.bodyBytes)); // Декодируем с учетом UTF-8
        final List<dynamic> jsonList = jsonResponse is List ? jsonResponse : [];
        return jsonList.map((json) => ActiveShift.fromJson(json)).toList();
      } else {
        // Попытка получить сообщение об ошибке из тела ответа
        String errorMessage = 'Ошибка загрузки';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error'] ?? errorMessage;
        } catch (e) {
          // Игнорируем ошибку парсинга тела ошибки
        }
        throw Exception('$errorMessage: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки активных смен: $e');
      // Показываем более дружелюбное сообщение пользователю
      if (e is http.ClientException ||
          e.toString().contains('SocketException')) {
        throw Exception('Нет соединения с интернетом');
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _shiftsFuture = _fetchActiveShifts();
    });
  }

  // --- Вспомогательные методы для построения UI ---

  Map<String, List<ActiveShift>> _groupShiftsByDate(List<ActiveShift> shifts) {
    final Map<String, List<ActiveShift>> grouped = {};
    for (final shift in shifts) {
      if (shift.startTime != null) {
        try {
          // Используем только дату для группировки
          final dateKey = DateTime(shift.startTime!.year,
                  shift.startTime!.month, shift.startTime!.day)
              .toIso8601String()
              .split('T')
              .first;
          grouped.putIfAbsent(dateKey, () => []);
          grouped[dateKey]!.add(shift);
        } catch (e) {
          debugPrint('Ошибка обработки даты для смены: $e');
          // Можно добавить в отдельную группу "Без даты"
        }
      }
    }
    return grouped;
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final shiftDate = DateTime(date.year, date.month, date.day);

      if (shiftDate.isAtSameMomentAs(today)) {
        return 'Сегодня';
      } else if (shiftDate.isAtSameMomentAs(yesterday)) {
        return 'Вчера';
      } else {
        return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
      }
    } catch (e) {
      debugPrint('Ошибка форматирования даты: $e');
      return isoDate; // Возвращаем исходную строку в случае ошибки
    }
  }

  String _calculateDuration(DateTime startTime) {
    try {
      final now = DateTime.now();
      final difference = now.difference(startTime);

      final hours = difference.inHours;
      final minutes = difference.inMinutes.remainder(60);

      if (hours > 0) {
        return '${hours}ч ${minutes}м';
      } else {
        return '${minutes}м';
      }
    } catch (e) {
      debugPrint('Ошибка вычисления длительности: $e');
      return '...';
    }
  }

  Widget _buildDateHeader(String dateKey) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.green[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _formatDate(dateKey),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildShiftCard(ActiveShift shift) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShiftDetailsScreen(shift: shift),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.grey[300],
              foregroundColor: Colors.grey,
              backgroundImage: shift.selfie.isNotEmpty
                  // ✅ Исправлен URL (убраны пробелы)
                  ? NetworkImage(
                      'https://eom-sharing.duckdns.org${shift.selfie}')
                  : null,
              child: shift.selfie.isEmpty
                  ? const Icon(Icons.person, size: 30)
                  : null,
            ),
            title: Text(
              shift.username,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Позиция: ${shift.position}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Зона: ${shift.zone}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Слот: ${shift.slotTimeRange}',
                  style: const TextStyle(fontSize: 14),
                ),
                if (shift.startTime != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Начало: ${shift.startTime != null ? _formatTime(shift.startTime!) : 'Нет данных'}',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.timer, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'Длит.: ${shift.startTime != null ? _calculateDuration(shift.startTime!) : '...'}',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: const Icon(
              Icons.play_circle,
              color: Colors.green,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.work_history_outlined,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'Активных смен нет',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Скауты еще не начали свои смены',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    String message = 'Произошла ошибка';
    if (error is Exception) {
      message = error.toString().replaceAll('Exception:', '').trim();
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], // Мягкий фон
      appBar: AppBar(
        title: const Text(
          'Мониторинг смен',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<ActiveShift>>(
            future: _shiftsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.green));
              } else if (snapshot.hasError) {
                return _buildErrorState(snapshot.error!);
              }

              final shifts = snapshot.data ?? [];
              if (shifts.isEmpty) {
                return _buildEmptyState();
              }

              final groupedShifts = _groupShiftsByDate(shifts);

              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16), // Отступ снизу
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8), // Небольшой отступ сверху
                    ...groupedShifts.entries.expand((entry) {
                      final dateKey = entry.key;
                      final shiftsForDay = entry.value;

                      return [
                        _buildDateHeader(dateKey),
                        ...shiftsForDay.map(_buildShiftCard),
                      ];
                    }).toList(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
