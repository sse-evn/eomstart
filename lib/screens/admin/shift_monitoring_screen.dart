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

      final response = await http.get(
        Uri.parse('https://eom-sharing.duckdns.org/api/admin/active-shifts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic jsonResponse = jsonDecode(response.body);
        final List<dynamic> jsonList = jsonResponse is List ? jsonResponse : [];
        return jsonList.map((json) => ActiveShift.fromJson(json)).toList();
      } else {
        throw Exception('Ошибка загрузки: ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки активных смен: $e');
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _shiftsFuture = _fetchActiveShifts();
    });
  }

  Map<String, List<ActiveShift>> _groupShiftsByDate(List<ActiveShift> shifts) {
    final Map<String, List<ActiveShift>> grouped = {};
    for (final shift in shifts) {
      final dateKey = shift.startTime.toIso8601String().split('T').first;
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(shift);
    }
    return grouped;
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Сегодня';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      return 'Вчера';
    }
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Активные смены'),
        backgroundColor: Colors.blue,
        elevation: 1,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ActiveShift>>(
          future: _shiftsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Ошибка: ${snapshot.error}',
                  style: TextStyle(color: Colors.red),
                ),
              );
            }

            final shifts = snapshot.data!;
            if (shifts.isEmpty) {
              return const Center(child: Text('Нет активных смен'));
            }

            final grouped = _groupShiftsByDate(shifts);

            return ListView(
              children: grouped.entries.map((entry) {
                final date = entry.key;
                final shiftsForDay = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        _formatDate(date),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    ...shiftsForDay.map((shift) {
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ShiftDetailsScreen(shift: shift),
                            ),
                          );
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipOval(
                                  child: shift.selfie.isNotEmpty
                                      ? Image.network(
                                          'https://eom-sharing.duckdns.org${shift.selfie}',
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            width: 60,
                                            height: 60,
                                            color: Colors.grey[300],
                                            child: const Icon(Icons.person,
                                                color: Colors.grey),
                                          ),
                                        )
                                      : Container(
                                          width: 60,
                                          height: 60,
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.person,
                                              color: Colors.grey),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shift.username,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Позиция: ${shift.position}',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 14),
                                      ),
                                      Text(
                                        'Зона: ${shift.zone}',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 14),
                                      ),
                                      Text(
                                        'Слот: ${shift.slotTimeRange}',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 14),
                                      ),
                                      Text(
                                        'Начало: ${TimeFormat(shift.startTime).formatTimeDate()}',
                                        style: const TextStyle(
                                            color: Colors.green, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.circle,
                                    color: Colors.green, size: 12),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

extension TimeFormat on DateTime {
  String formatTimeDate() {
    final date =
        '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}';
    final time =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
