// lib/screens/admin/shifts_list/shift_history_screen.dart

import 'dart:async' show Timer;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/config.dart' as AppConfig;
import 'package:micro_mobility_app/config/google_sheets_config.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:micro_mobility_app/screens/admin/shifts_list/shift_details_screen.dart';
import 'package:micro_mobility_app/utils/time_utils.dart';
import 'package:intl/intl.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<ActiveShift>> _shiftsFuture;
  bool _isExporting = false;
  Timer? _autoExportTimer;

  @override
  void initState() {
    super.initState();
    _shiftsFuture = _fetchEndedShifts();
    _setupAutoExport();
  }

  @override
  void dispose() {
    _autoExportTimer?.cancel();
    super.dispose();
  }

  Future<List<ActiveShift>> _fetchEndedShifts() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final url =
          Uri.parse('${AppConfig.AppConfig.apiBaseUrl}/admin/ended-shifts');
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
        throw Exception('Ошибка загрузки: ${response.statusCode}');
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

  Duration _calculateDuration(ActiveShift shift) {
    final start = DateTime.parse(shift.startTimeString!);
    final end = DateTime.parse(shift.endTimeString!);
    return end.difference(start);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '$hours ч ${minutes} мин';
  }

  double _calculatePayment(ActiveShift shift) {
    final duration = _calculateDuration(shift);
    final hours = duration.inHours + duration.inMinutes.remainder(60) / 60.0;
    return hours * GoogleSheetsConfig.hourlyRate;
  }

  Widget _buildShiftCard(ActiveShift shift) {
    final duration = _calculateDuration(shift);
    final payment = _calculatePayment(shift);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShiftDetailsScreen(shift: shift),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Фото
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.grey[300],
                backgroundImage: shift.selfie.isNotEmpty
                    ? NetworkImage(
                        '${AppConfig.AppConfig.mediaBaseUrl}${shift.selfie.trim()}')
                    : null,
                child: shift.selfie.isEmpty
                    ? const Icon(Icons.person, color: Colors.white)
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
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${shift.position} • ${shift.zone}',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${extractTimeFromIsoString(shift.startTimeString)} – ${extractTimeFromIsoString(shift.endTimeString)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Оплата
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${payment.toStringAsFixed(0)} ${GoogleSheetsConfig.currency}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Экспорт в Google Sheets
  Future<void> _exportToGoogleSheets(List<ActiveShift> shifts) async {
    if (shifts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет данных для выгрузки')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final List<List<String>> data = [
        [
          'Имя',
          'Позиция',
          'Зона',
          'Начало',
          'Конец',
          'Длительность',
          'Оплата (₸)'
        ]
      ];

      for (final shift in shifts) {
        final duration = _calculateDuration(shift);
        final hours =
            duration.inHours + duration.inMinutes.remainder(60) / 60.0;
        final payment =
            (hours * GoogleSheetsConfig.hourlyRate).toStringAsFixed(0);

        data.add([
          shift.username,
          shift.position,
          shift.zone,
          '${_formatDate(shift.startTimeString!)} ${extractTimeFromIsoString(shift.startTimeString)}',
          extractTimeFromIsoString(shift.endTimeString),
          _formatDuration(duration),
          payment,
        ]);
      }

      final response = await http.post(
        Uri.parse(GoogleSheetsConfig.googleSheetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': data}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Данные отправлены в Google Таблицу!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Ошибка: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ошибка: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // ✅ Автоматическая выгрузка в 00:30
  void _setupAutoExport() {
    final now = DateTime.now();
    var nextRun = DateTime(
      now.year,
      now.month,
      now.day,
      GoogleSheetsConfig.autoExportHour,
      GoogleSheetsConfig.autoExportMinute,
    );

    if (now.isAfter(nextRun)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final delay = nextRun.difference(now);
    _autoExportTimer = Timer(delay, () async {
      final shifts = await _shiftsFuture;
      if (shifts.isNotEmpty) {
        await _exportToGoogleSheets(shifts);
      }
      _setupAutoExport(); // Перезапуск на завтра
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История смен', style: TextStyle(fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        elevation: 4,
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            onPressed: _isExporting
                ? null
                : () async {
                    final shifts = await _shiftsFuture;
                    await _exportToGoogleSheets(shifts);
                  },
            tooltip: 'Выгрузить в Google Таблицу',
          ),
          const SizedBox(width: 8),
        ],
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
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
                            horizontal: 16, vertical: 12),
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.green[700],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatDate(entry.key),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      ...entry.value.map(_buildShiftCard),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
