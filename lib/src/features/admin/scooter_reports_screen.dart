import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  
  List<dynamic> _reports = [];
  bool _isLoading = true;
  String? _error;

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
      
      final reports = await _apiService.getScooterReports(token);
      setState(() {
        _reports = reports;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
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

    if (_reports.isEmpty) {
      return const Center(child: Text('Нет отчетов'));
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          final brand = report['brand'] ?? 'Неизвестно';
          final scooterNum = report['scooter_number'] ?? '';
          final employeeName = report['employee_name'] ?? '';
          final employeeUsername = report['employee_username'] ?? '';
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

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '$employeeName (@$employeeUsername)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Бренд: $brand • Самокат: $scooterNum', style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Тип отчета: $reportType', style: const TextStyle(fontSize: 14)),
                  if (lat != null && lon != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openMap(lat!, lon!),
                        icon: const Icon(Icons.location_on, color: Colors.blue),
                        label: const Text('Показать на карте'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text(
                      '📍 Координаты не найдены',
                      style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
