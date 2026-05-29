import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ScooterReportsScreen extends StatefulWidget {
  const ScooterReportsScreen({super.key});

  @override
  State<ScooterReportsScreen> createState() => _ScooterReportsScreenState();
}

class _ScooterReportsScreenState extends State<ScooterReportsScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  Map<String, List<dynamic>> _groupedReports = {};
  Map<String, String> _userNames = {};
  
  bool _isLoading = true;
  String? _error;
  
  // 'shift' (за всю смену), '1h' (за последний час), '3h' (за последние 3 часа)
  String _timeFilter = 'shift';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Не авторизован');
      
      final activeShifts = await _apiService.getActiveShifts(token);
      final reports = await _apiService.getScooterReports(token);
      
      Map<String, List<dynamic>> grouped = {};
      Map<String, String> names = {};
      
      // Сначала добавим всех активных скаутов на смене
      for (var shift in activeShifts) {
        final username = shift.username.isNotEmpty ? shift.username : 'unknown';
        grouped[username] = [];
        names[username] = username;
      }
      
      // Затем добавим отчеты (если скаут уже добавлен, отчеты прикрепятся к нему)
      for (var r in reports) {
        final username = r['employee_username']?.toString() ?? 'unknown';
        final name = r['employee_name']?.toString() ?? 'Неизвестный';
        
        if (!grouped.containsKey(username)) {
          grouped[username] = [];
        }
        grouped[username]!.add(r);
        
        // Обновим имя, если оно пришло из отчета (оно полнее)
        if (names[username] == username || !names.containsKey(username)) {
          names[username] = name;
        }
      }
      
      if (!mounted) return;
      setState(() {
        _groupedReports = grouped;
        _userNames = names;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openMap(double lat, double lon) async {
    final url = Uri.parse('https://yandex.ru/maps/?pt=$lon,$lat&z=17&l=map');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть карту')),
        );
      }
    }
  }
  
  List<dynamic> _getFilteredReports(List<dynamic> reports) {
    if (_timeFilter == 'shift') return reports;
    final now = DateTime.now();
    return reports.where((report) {
      final createdAtStr = report['created_at'] ?? '';
      if (createdAtStr.isEmpty) return false;
      try {
        final dt = DateTime.parse(createdAtStr).toLocal();
        final diff = now.difference(dt);
        if (_timeFilter == '1h') return diff.inHours < 1;
        if (_timeFilter == '3h') return diff.inHours < 3;
      } catch (e) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportToCSV() async {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // BOM для Excel
    buffer.writeln('Имя,Никнейм,Время,Бренд,Номер самоката,Тип отчета,Координаты');
    
    final usernames = _groupedReports.keys.toList();
    for (var username in usernames) {
      final name = _userNames[username] ?? username;
      final reports = _groupedReports[username]!;
      final filteredReports = _getFilteredReports(reports);

      for (var report in filteredReports) {
        final brand = report['brand'] ?? '';
        final scooterNum = report['scooter_number'] ?? '';
        final reportType = report['report_type'] ?? '';
        final createdAtStr = report['created_at'] ?? '';
        
        String timeStr = '';
        if (createdAtStr.isNotEmpty) {
          try {
             timeStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(createdAtStr).toLocal());
          } catch (_) {}
        }
        
        final lat = report['lat']?.toString() ?? '';
        final lon = report['lon']?.toString() ?? '';
        final coords = (lat.isNotEmpty && lon.isNotEmpty) ? '$lat,$lon' : 'Нет';
        
        buffer.writeln('"$name","@$username","$timeStr","$brand","$scooterNum","$reportType","$coords"');
      }
    }
    
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/scooter_reports.csv');
      await file.writeAsString(buffer.toString(), flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Отчеты по самокатам');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadReports,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final usernames = _groupedReports.keys.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _timeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Фильтр по времени',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'shift', child: Text('За всю смену')),
                    DropdownMenuItem(value: '1h', child: Text('За последний час')),
                    DropdownMenuItem(value: '3h', child: Text('За последние 3 часа')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _timeFilter = val;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _exportToCSV,
                icon: const Icon(Icons.download),
                label: const Text('Excel'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadReports,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: usernames.length,
              itemBuilder: (context, index) {
                final username = usernames[index];
                final allReports = _groupedReports[username]!;
                final filteredReports = _getFilteredReports(allReports);
                final name = _userNames[username] ?? username;

                // Если фильтр строгий, и у пользователя 0 подходящих отчетов, мы его все равно показываем,
                // чтобы было видно бездельников.

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ExpansionTile(
                    title: Text(
                      '$name (@$username)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      'Отчетов: ${filteredReports.length}',
                      style: TextStyle(
                        color: filteredReports.isEmpty ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: filteredReports.map((report) {
                      final brand = report['brand'] ?? 'Неизвестно';
                      final scooterNum = report['scooter_number'] ?? '';
                      final reportType = report['report_type'] ?? '';
                      final createdAtStr = report['created_at'] ?? '';
                      
                      String timeStr = createdAtStr;
                      if (createdAtStr.isNotEmpty) {
                        try {
                          final dt = DateTime.parse(createdAtStr).toLocal();
                          timeStr = DateFormat('dd.MM.yyyy HH:mm').format(dt);
                        } catch (e) {
                          // ignore
                        }
                      }

                      double? lat;
                      double? lon;
                      if (report['lat'] != null) lat = (report['lat'] as num).toDouble();
                      if (report['lon'] != null) lon = (report['lon'] as num).toDouble();

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Бренд: $brand • $scooterNum',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  timeStr,
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Тип отчета: $reportType', style: const TextStyle(fontSize: 14)),
                            if (lat != null && lon != null) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openMap(lat!, lon!),
                                  icon: const Icon(Icons.location_on, color: Colors.blue, size: 18),
                                  label: const Text('Показать на карте'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              const Text(
                                '📍 Координаты не найдены',
                                style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
