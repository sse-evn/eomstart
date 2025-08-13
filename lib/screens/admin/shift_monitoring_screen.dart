// lib/screens/admin/shift_monitoring_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart';

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
        final List<dynamic> jsonList = jsonDecode(response.body);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Активные смены'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ActiveShift>>(
          future: _shiftsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Ошибка: ${snapshot.error}'));
            }

            final shifts = snapshot.data!;
            if (shifts.isEmpty) {
              return const Center(child: Text('Нет активных смен'));
            }

            return ListView.builder(
              itemCount: shifts.length,
              itemBuilder: (context, index) {
                final shift = shifts[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.access_time, color: Colors.green),
                    title: Text(
                      shift.username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Слот: ${shift.slotTimeRange}'),
                        Text('Зона: ${shift.zone}'),
                        Text('Позиция: ${shift.position}'),
                        Text('Старт: ${shift.startTime.formatTimeDate()}'),
                      ],
                    ),
                    trailing:
                        const Icon(Icons.check_circle, color: Colors.green),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// Вспомогательное расширение
extension TimeFormat on DateTime {
  String formatTimeDate() {
    final date =
        '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}';
    final time =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
