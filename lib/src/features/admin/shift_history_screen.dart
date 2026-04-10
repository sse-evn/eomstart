import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart' as AppConfig;
import 'package:micro_mobility_app/src/core/config/google_sheets_config.dart';
import 'package:micro_mobility_app/src/features/app/models/active_shift.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:micro_mobility_app/src/core/utils/time_utils.dart';
import 'package:micro_mobility_app/src/features/admin/shifts_list/shift_details_screen.dart';

class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
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
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw Exception('Токен не найден');
    
    return await _apiService.getEndedShifts(token);
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
        final utcTime = DateTime.parse(shift.endTimeString!);
        final localDate = utcTime.toLocal();
        final dateKey =
            '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add(shift);
      }
    }
    return Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
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
      return '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.$year';
    } catch (e) {
      return dateKey;
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
    return '$hours ч $minutes мин';
  }

  double _calculatePayment(ActiveShift shift) {
    final duration = _calculateDuration(shift);
    final hours = duration.inHours + duration.inMinutes.remainder(60) / 60.0;
    return hours * GoogleSheetsConfig.hourlyRate;
  }

  String _formatLocalTime(String isoString) {
    return TimeUtils.formatTime(isoString);
  }

  Widget _buildShiftCard(ActiveShift shift) {
    if (shift.startTimeString == null || shift.endTimeString == null) return const SizedBox();
    
    return Card(
      color: Theme.of(context).colorScheme.secondary,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ShiftDetailsScreen(shift: shift)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shift.username,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${shift.position} • ${shift.zone}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${_formatLocalTime(shift.startTimeString!)} – ${_formatLocalTime(shift.endTimeString!)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToGoogleSheets(List<ActiveShift> shifts) async {
    if (shifts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет данных для выгрузки')));
      return;
    }
    setState(() => _isExporting = true);
    try {
      final List<List<String>> data = [
        [
          'Имя',
          'Позиция',
          'Зона',
          'Начало',
          'Конец',
          'Длительность',
        ]
      ];
      for (final shift in shifts) {
        final duration = _calculateDuration(shift);
        final startLocal = DateTime.parse(shift.startTimeString!).toLocal();
        final startDate =
            '${startLocal.day.toString().padLeft(2, '0')}.${startLocal.month.toString().padLeft(2, '0')}.${startLocal.year}';
        data.add([
          shift.username,
          shift.position,
          shift.zone,
          '$startDate ${_formatLocalTime(shift.startTimeString!)}',
          _formatLocalTime(shift.endTimeString!),
          _formatDuration(duration),
        ]);
      }
      final response = await http.post(
        Uri.parse(GoogleSheetsConfig.googleSheetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': data}),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Данные отправлены в Google Таблицу!'),
          backgroundColor: Colors.green,
        ));
      } else {
        throw Exception('Ошибка: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Ошибка: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _setupAutoExport() {
    final now = DateTime.now();
    var nextRun = DateTime(now.year, now.month, now.day,
        GoogleSheetsConfig.autoExportHour, GoogleSheetsConfig.autoExportMinute);
    if (now.isAfter(nextRun)) nextRun = nextRun.add(const Duration(days: 1));
    final delay = nextRun.difference(now);
    _autoExportTimer = Timer(delay, () async {
      final shifts = await _shiftsFuture;
      if (shifts.isNotEmpty) await _exportToGoogleSheets(shifts);
      _setupAutoExport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          _formatDate(entry.key),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white),
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
