import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/screens/admin/shifts_list/shift_details_screen.dart';
import 'package:micro_mobility_app/utils/time_utils.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  ShiftHistoryScreenState createState() => ShiftHistoryScreenState();
}

class ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<ActiveShift>> _shiftsFuture;

  @override
  void initState() {
    super.initState();
    _shiftsFuture = _fetchEndedShifts();
  }

  Future<List<ActiveShift>> _fetchEndedShifts() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final url = Uri.parse('${AppConfig.apiBaseUrl}/admin/ended-shifts');
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
        return jsonList.map((json) => ActiveShift.fromJson(json)).toList();
      } else {
        throw Exception('Ошибка загрузки истории: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> refresh() async {
    setState(() {
      _shiftsFuture = _fetchEndedShifts();
    });
  }

  Map<String, List<ActiveShift>> _groupShiftsByDate(List<ActiveShift> shifts) {
    final Map<String, List<ActiveShift>> grouped = {};
    for (final shift in shifts) {
      if (shift.endTimeString != null && shift.endTimeString!.isNotEmpty) {
        final dateKey = shift.endTimeString!.split('T').first;
        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add(shift);
      }
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
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

  Widget _buildShiftCard(ActiveShift shift) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ShiftDetailsScreen(shift: shift)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: shift.selfie.isNotEmpty
                    ? NetworkImage(
                        '${AppConfig.mediaBaseUrl}${shift.selfie.trim()}')
                    : null,
                child: shift.selfie.isEmpty ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shift.username,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Зона: ${shift.zone}'),
                    Text(
                      'Время: ${extractTimeFromIsoString(shift.startTimeString)} – ${extractTimeFromIsoString(shift.endTimeString)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: FutureBuilder<List<ActiveShift>>(
        future: _shiftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }

          final shifts = snapshot.data ?? [];
          if (shifts.isEmpty) {
            return const Center(child: Text('Нет завершённых смен'));
          }

          final grouped = _groupShiftsByDate(shifts);

          return ListView(
            children: [
              for (final entry in grouped.entries)
                Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.grey[200],
                      child: Text(
                        _formatDate(entry.key),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ...entry.value.map(_buildShiftCard),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

// class _ShiftDetailsScreen extends StatelessWidget {
//   final ActiveShift shift;
//   const _ShiftDetailsScreen({required this.shift});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Детали смены')),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Имя: ${shift.username}'),
//             Text('Позиция: ${shift.position}'),
//             Text('Зона: ${shift.zone}'),
//             Text('Начало: ${shift.startTimeString}'),
//             Text('Конец: ${shift.endTimeString}'),
//           ],
//         ),
//       ),
//     );
//   }
// }
