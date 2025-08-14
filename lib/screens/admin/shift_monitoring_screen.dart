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
      // Добавляем проверку на null
      if (shift.startTime != null) {
        final dateKey = shift.startTime!.toIso8601String().split('T').first;
        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add(shift);
      }
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
        backgroundColor: Colors.green[700],
        elevation: 4,
        foregroundColor: Colors.white,
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
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final shifts = snapshot.data!;
            if (shifts.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Нет активных смен',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            final grouped = _groupShiftsByDate(shifts);

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.grey[50]!,
                    Colors.white,
                  ],
                ),
              ),
              child: ListView(
                children: grouped.entries.map((entry) {
                  final date = entry.key;
                  final shiftsForDay = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text(
                          _formatDate(date),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                      ...shiftsForDay.map((shift) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ShiftDetailsScreen(shift: shift),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // Фото сотрудника
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: Colors.green[100]!,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: shift.selfie.isNotEmpty
                                            ? Image.network(
                                                'https://eom-sharing.duckdns.org${shift.selfie}',
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                loadingBuilder: (context, child,
                                                    loadingProgress) {
                                                  if (loadingProgress == null)
                                                    return child;
                                                  return Container(
                                                    width: 60,
                                                    height: 60,
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              30),
                                                    ),
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2),
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    Container(
                                                  width: 60,
                                                  height: 60,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            30),
                                                  ),
                                                  child: const Icon(
                                                    Icons.person,
                                                    color: Colors.grey,
                                                    size: 30,
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                width: 60,
                                                height: 60,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[200],
                                                  borderRadius:
                                                      BorderRadius.circular(30),
                                                ),
                                                child: const Icon(
                                                  Icons.person,
                                                  color: Colors.grey,
                                                  size: 30,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
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
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _buildInfoChip('Позиция',
                                              shift.position, Colors.blue),
                                          const SizedBox(height: 4),
                                          _buildInfoChip(
                                              'Зона', shift.zone, Colors.green),
                                          const SizedBox(height: 4),
                                          _buildInfoChip(
                                              'Слот',
                                              shift.slotTimeRange,
                                              Colors.orange),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Начало: ${shift.startTime != null ? TimeFormat(shift.startTime!).formatTimeDate() : 'Нет данных'}',
                                            style: TextStyle(
                                              color: Colors.green[700],
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.green[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.circle,
                                        color: Colors.green,
                                        size: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
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
