import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';

class DailyReportsTab extends StatefulWidget {
  const DailyReportsTab({super.key});

  @override
  State<DailyReportsTab> createState() => _DailyReportsTabState();
}

class _DailyReportsTabState extends State<DailyReportsTab> {
  final _storage = const FlutterSecureStorage();
  bool _isLoading = true;
  String _reportText = '';
  String _error = '';

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    // Default to last 7 days
    _endDate = DateTime.now();
    _startDate = _endDate!.subtract(const Duration(days: 7));
    _fetchReport();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchReport();
    }
  }

  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      String queryParams = '';
      if (_startDate != null && _endDate != null) {
        final startStr = '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}';
        final endStr = '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}';
        queryParams = '?start_date=$startStr&end_date=$endStr';
      }

      final url = Uri.parse('${AppConfig.apiBaseUrl}/admin/scooter-reports-summary$queryParams');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decoded);
        setState(() {
          _reportText = data['report'] ?? 'Нет данных';
        });
      } else {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportToExcel() async {
    if (_startDate == null || _endDate == null) return;
    
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final startStr = "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}";
      final endStr = "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}";
      final url = Uri.parse('${AppConfig.apiBaseUrl}/admin/scooter-reports/excel?start_date=$startStr&end_date=$endStr');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/scooter_reports_$startStr.xlsx');
        await file.writeAsBytes(response.bodyBytes);
        
        if (mounted) {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Отчет по самокатам с $startStr по $endStr',
          );
        }
      } else {
        throw Exception('Ошибка загрузки Excel: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('Произошла ошибка', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _fetchReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final dateLabel = _startDate != null && _endDate != null
        ? '${_startDate!.day.toString().padLeft(2, '0')}.${_startDate!.month.toString().padLeft(2, '0')} — ${_endDate!.day.toString().padLeft(2, '0')}.${_endDate!.month.toString().padLeft(2, '0')}'
        : 'Выберите период';

    // Заголовок и иконка
    final headerInfo = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.analytics, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сводка по сменам',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'Агрегированные данные',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );

    // Кнопки управления
    final headerActions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: isSmallScreen ? WrapAlignment.start : WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: _selectDateRange,
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(dateLabel),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _reportText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Отчет скопирован в буфер обмена'),
                backgroundColor: Colors.green,
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Скопировать'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        FilledButton.icon(
          onPressed: _exportToExcel,
          icon: const Icon(Icons.table_view, size: 18),
          label: const Text('Экспорт в Excel'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green[700],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );

    // Парсинг текста в карточки
    final chunks = _reportText.split('\n\n').where((s) => s.trim().isNotEmpty).toList();

    return Column(
      children: [
        // Панель управления (Top Bar)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
            ),
          ),
          child: isSmallScreen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerInfo,
                    const SizedBox(height: 16),
                    headerActions,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: headerInfo),
                    const SizedBox(width: 16),
                    headerActions,
                  ],
                ),
        ),
        
        // Основной контент (Карточки)
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
            width: double.infinity,
            child: _reportText.isEmpty
                ? const Center(child: Text('Нет данных для отображения'))
                : ListView.builder(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 32),
                    itemCount: chunks.length,
                    itemBuilder: (context, index) {
                      final chunk = chunks[index].trim();
                      
                      // Определяем стиль карточки по контенту
                      bool isAnalytics = chunk.startsWith('📊') || chunk.startsWith('📈') || chunk.startsWith('🔧') || chunk.startsWith('🏆');
                      bool isSummary = chunk.startsWith('Итог по сервисам');
                      bool isDate = chunk.startsWith('📅');

                      Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
                      if (isAnalytics || isSummary) {
                        cardColor = isDark ? const Color(0xFF252525) : const Color(0xFFF0F4F8); // Выделяем аналитику
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: const BoxConstraints(maxWidth: 1000),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                          ),
                        ),
                        child: SelectableText(
                          chunk,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            height: 1.6,
                            color: isDark ? Colors.grey[300] : Colors.grey[800],
                            fontWeight: (isAnalytics || isSummary) && !isDate ? FontWeight.w500 : FontWeight.normal,
                          ),
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
