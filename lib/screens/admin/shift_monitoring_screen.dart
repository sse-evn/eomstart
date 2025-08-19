// lib/screens/admin/shift_monitoring_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config.dart'; // Конфиг
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/screens/admin/shifts_list/shift_details_screen.dart';
import 'package:micro_mobility_app/utils/time_utils.dart';

class ShiftMonitoringScreen extends StatefulWidget {
  const ShiftMonitoringScreen({super.key});

  @override
  State<ShiftMonitoringScreen> createState() => _ShiftMonitoringScreenState();
}

class _ShiftMonitoringScreenState extends State<ShiftMonitoringScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<ActiveShift>> _shiftsFuture;

  // Состояние сворачивания дней
  final Map<String, bool> _expandedDays = {};

  @override
  void initState() {
    super.initState();
    _shiftsFuture = _fetchActiveShifts();
    debugPrint('🚀 Запуск мониторинга смен...');
  }

  Future<List<ActiveShift>> _fetchActiveShifts() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final url = Uri.parse('${AppConfig.apiBaseUrl}/admin/active-shifts');
      debugPrint('🌐 GET $url');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic jsonResponse =
            jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> jsonList = jsonResponse is List ? jsonResponse : [];
        final List<ActiveShift> shifts =
            jsonList.map((json) => ActiveShift.fromJson(json)).toList();
        debugPrint('✅ Загружено ${shifts.length} активных смен');
        return shifts;
      } else {
        String errorMessage = 'Ошибка загрузки';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error'] ?? errorMessage;
        } catch (e) {
          debugPrint('❌ Ошибка парсинга тела: $e');
        }
        throw Exception('$errorMessage: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔴 Ошибка загрузки смен: $e');
      if (e is http.ClientException ||
          e.toString().contains('SocketException')) {
        throw Exception('Нет соединения с интернетом');
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    debugPrint('🔄 Обновление списка...');
    setState(() {
      _shiftsFuture = _fetchActiveShifts();
    });
  }

  Map<String, List<ActiveShift>> _groupShiftsByDate(List<ActiveShift> shifts) {
    final Map<String, List<ActiveShift>> grouped = {};
    for (final shift in shifts) {
      if (shift.startTimeString != null && shift.startTimeString!.isNotEmpty) {
        try {
          final dateKey = shift.startTimeString!.split('T').first;
          grouped.putIfAbsent(dateKey, () => []);
          grouped[dateKey]!.add(shift);
        } catch (e) {
          debugPrint('⚠️ Ошибка при группировке по дате: $e');
        }
      }
    }

    // Сортировка: новые даты сверху
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final sortedMap = <String, List<ActiveShift>>{};
    for (final key in sortedKeys) {
      sortedMap[key] = grouped[key]!;
    }

    debugPrint('📅 Найдено дней: ${sortedMap.length}');
    return sortedMap;
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final shiftDate = DateTime(date.year, date.month, date.day);

      if (shiftDate.isAtSameMomentAs(today)) return 'Сегодня';
      if (shiftDate.isAtSameMomentAs(yesterday)) return 'Вчера';
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      return isoDate;
    }
  }

  String _calculateDuration(DateTime startTime) {
    final now = DateTime.now();
    final difference = now.difference(startTime);
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    return hours > 0 ? '${hours}ч ${minutes}м' : '${minutes}м';
  }

  // Определение типа смены по времени начала
  String _getShiftType(DateTime startTime) {
    final timeInMinutes = startTime.hour * 60 + startTime.minute;

    if (timeInMinutes >= 420 && timeInMinutes < 900)
      return 'morning'; // 07:00–14:59
    if (timeInMinutes >= 900 && timeInMinutes < 1380)
      return 'evening'; // 15:00–22:59
    return 'other'; // Вне графика
  }

  Map<String, List<ActiveShift>> _groupShiftsByTimeOfDay(
      List<ActiveShift> shifts) {
    final morning = <ActiveShift>[];
    final evening = <ActiveShift>[];
    final other = <ActiveShift>[];

    for (final shift in shifts) {
      if (shift.startTime != null) {
        final type = _getShiftType(shift.startTime!);
        switch (type) {
          case 'morning':
            morning.add(shift);
            break;
          case 'evening':
            evening.add(shift);
            break;
          default:
            other.add(shift);
        }
      }
    }

    return {
      'morning': morning,
      'evening': evening,
      'other': other,
    };
  }

  // Заголовок типа смены с иконкой и цветом
  Widget _buildShiftTypeHeader(String type, int count) {
    String label;
    IconData icon;
    Color bgColor, textColor;

    switch (type) {
      case 'morning':
        label = '🌅 Утренняя смена';
        icon = Icons.wb_sunny;
        bgColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green[700]!;
        break;
      case 'evening':
        label = '🌆 Вечерняя смена';
        icon = Icons.nightlight_round;
        bgColor = Colors.orange.withOpacity(0.1);
        textColor = Colors.orange[700]!;
        break;
      default:
        label = '⚠️ Вне графика';
        icon = Icons.warning;
        bgColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey[700]!;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // Заголовок дня с возможностью сворачивания
  Widget _buildDateHeader(String dateKey, List<ActiveShift> shiftsForDay) {
    final isExpanded = _expandedDays[dateKey] ?? true;
    final dateLabel = _formatDate(dateKey);
    final total = shiftsForDay.length;

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
          decoration: BoxDecoration(
            color: Colors.green[700],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandedDays[dateKey] = !(_expandedDays[dateKey] ?? true);
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$dateLabel ($total)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 8),
          ..._buildShiftsGroupedByType(shiftsForDay),
        ],
      ],
    );
  }

  List<Widget> _buildShiftsGroupedByType(List<ActiveShift> shifts) {
    final grouped = _groupShiftsByTimeOfDay(shifts);
    final widgets = <Widget>[];

    if (grouped['morning']!.isNotEmpty) {
      widgets.add(_buildShiftTypeHeader('morning', grouped['morning']!.length));
      widgets.addAll(grouped['morning']!.map(_buildShiftCard));
    }

    if (grouped['evening']!.isNotEmpty) {
      widgets.add(_buildShiftTypeHeader('evening', grouped['evening']!.length));
      widgets.addAll(grouped['evening']!.map(_buildShiftCard));
    }

    if (grouped['other']!.isNotEmpty) {
      widgets.add(_buildShiftTypeHeader('other', grouped['other']!.length));
      widgets.addAll(grouped['other']!.map(_buildShiftCard));
    }

    return widgets;
  }

  Widget _buildShiftCard(ActiveShift shift) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShiftDetailsScreen(shift: shift),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Фото
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.grey,
                backgroundImage: shift.selfie.isNotEmpty
                    ? NetworkImage(
                        '${AppConfig.mediaBaseUrl}${shift.selfie.trim()}')
                    : null,
                child: shift.selfie.isEmpty
                    ? const Icon(Icons.person, size: 30)
                    : null,
              ),
              const SizedBox(width: 16),

              // Информация
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shift.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text('Позиция: ${shift.position}',
                        style: const TextStyle(fontSize: 13)),
                    Text('Зона: ${shift.zone}',
                        style: const TextStyle(fontSize: 13)),
                    if (shift.startTimeString != null &&
                        shift.startTimeString!.isNotEmpty)
                      Text(
                        'Начало: ${extractTimeFromIsoString(shift.startTimeString!)}',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                  ],
                ),
              ),

              const Icon(Icons.play_circle_outline,
                  color: Colors.green, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.work_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Активных смен нет',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          Text(
            'Скауты еще не начали работу',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    String message = 'Ошибка';
    if (error is Exception) {
      message = error.toString().replaceAll('Exception:', '').trim();
    }
    debugPrint('🔴 Ошибка: $message');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 2,
        leading: null,
        automaticallyImplyLeading:
            false, // 🔥 Ключевое: отключаем автоматическое добавление кнопки
// 🟢 Убираем кнопку "назад"
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<ActiveShift>>(
            future: _shiftsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.green),
                );
              } else if (snapshot.hasError) {
                return _buildErrorState(snapshot.error!);
              }

              final shifts = snapshot.data ?? [];
              if (shifts.isEmpty) return _buildEmptyState();

              final groupedShifts = _groupShiftsByDate(shifts);

              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    ...groupedShifts.entries.map((entry) {
                      return _buildDateHeader(entry.key, entry.value);
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
