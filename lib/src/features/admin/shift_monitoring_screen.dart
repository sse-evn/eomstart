import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:micro_mobility_app/src/features/app/models/active_shift.dart';
import 'package:micro_mobility_app/src/features/admin/shifts_list/shift_details_screen.dart';

class ShiftMonitoringScreen extends StatefulWidget {
  const ShiftMonitoringScreen({super.key});

  @override
  ShiftMonitoringScreenState createState() => ShiftMonitoringScreenState();
}

class ShiftMonitoringScreenState extends State<ShiftMonitoringScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<ActiveShift>> _shiftsFuture;

  @override
  void initState() {
    super.initState();
    _shiftsFuture = _fetchActiveShifts();
  }

  Future<List<ActiveShift>> _fetchActiveShifts() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw Exception('Токен не найден');

    final url = Uri.parse('${AppConfig.apiBaseUrl}/admin/active-shifts');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final dynamic jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
      final List<dynamic> jsonList = jsonResponse is List ? jsonResponse : [];
      return jsonList.map((json) => ActiveShift.fromJson(json)).toList();
    } else {
      String errorMessage = 'Ошибка загрузки';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error'] ?? errorMessage;
      } catch (e) {}
      throw Exception('$errorMessage: ${response.statusCode}');
    }
  }

  Future<void> refresh() async {
    setState(() {
      _shiftsFuture = _fetchActiveShifts();
    });
  }

  Map<String, List<ActiveShift>> _groupShiftsByDate(List<ActiveShift> shifts) {
    final Map<String, List<ActiveShift>> grouped = {};
    for (final shift in shifts) {
      if (shift.startTimeString != null && shift.startTimeString!.isNotEmpty) {
        try {
          final utcTime = DateTime.parse(shift.startTimeString!);
          final localDate = utcTime.toLocal();
          final dateKey =
              '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
          grouped.putIfAbsent(dateKey, () => []);
          grouped[dateKey]!.add(shift);
        } catch (e) {}
      }
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final sortedMap = <String, List<ActiveShift>>{};
    for (final key in sortedKeys) {
      sortedMap[key] = grouped[key]!;
    }
    return sortedMap;
  }

  String _formatDate(String dateKey) {
    try {
      final parts = dateKey.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final shiftDate = DateTime(year, month, day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      if (shiftDate.isAtSameMomentAs(today)) return 'Сегодня';
      if (shiftDate.isAtSameMomentAs(yesterday)) return 'Вчера';
      return '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.${year}';
    } catch (e) {
      return dateKey;
    }
  }

  String _getShiftType(DateTime localStartTime) {
    final timeInMinutes = localStartTime.hour * 60 + localStartTime.minute;
    if (timeInMinutes >= 420 && timeInMinutes < 900) return 'morning';
    if (timeInMinutes >= 900 && timeInMinutes < 1380) return 'evening';
    return 'other';
  }

  Map<String, List<ActiveShift>> _groupShiftsByTimeOfDay(
      List<ActiveShift> shifts) {
    final morning = <ActiveShift>[];
    final evening = <ActiveShift>[];
    final other = <ActiveShift>[];

    for (final shift in shifts) {
      if (shift.startTimeString != null) {
        final utcTime = DateTime.parse(shift.startTimeString!);
        final localTime = utcTime.toLocal();
        final type = _getShiftType(localTime);
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
                fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }

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
                          color: Colors.white),
                    ),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white),
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

  String _formatLocalTime(String isoString) {
    try {
      final utcTime = DateTime.parse(isoString);
      final localTime = utcTime.toLocal();
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '--:--';
    }
  }

  Widget _buildShiftCard(ActiveShift shift) {
    final photoUrl =
        '${AppConfig.mediaBaseUrl}${shift.selfie.trim()}?t=${DateTime.now().millisecondsSinceEpoch}';

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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.grey,
                backgroundImage:
                    shift.selfie.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: shift.selfie.isEmpty
                    ? const Icon(Icons.person, size: 30)
                    : null,
              ),
              const SizedBox(width: 16),
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
                    if (shift.startTimeString != null)
                      Text(
                        'Начало: ${_formatLocalTime(shift.startTimeString!)}',
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

  final Map<String, bool> _expandedDays = {};

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: FutureBuilder<List<ActiveShift>>(
        future: _shiftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.green));
          } else if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }

          final shifts = snapshot.data ?? [];
          if (shifts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Активных смен нет',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  Text('Скауты еще не начали работу',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            );
          }

          final groupedShifts = _groupShiftsByDate(shifts);

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ...groupedShifts.entries
                    .map((entry) => _buildDateHeader(entry.key, entry.value))
                    .toList(),
              ],
            ),
          );
        },
      ),
    );
  }
}
