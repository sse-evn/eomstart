// lib/screens/admin/admin_promo_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:micro_mobility_app/services/promo_api_service.dart';
import 'package:micro_mobility_app/main.dart' as app;
import 'package:micro_mobility_app/utils/auth_utils.dart' as app show logout;

class AdminPromoScreen extends StatelessWidget {
  const AdminPromoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PromoManagementContent();
  }
}

class PromoManagementContent extends StatefulWidget {
  const PromoManagementContent({super.key});

  @override
  State<PromoManagementContent> createState() => _PromoManagementContentState();
}

class _PromoManagementContentState extends State<PromoManagementContent> {
  final PromoApiService _service = PromoApiService();
  bool _isLoading = false;
  Map<String, dynamic>? _stats;
  List<dynamic>? _claimedPromos;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _loadStats();
    await _loadClaimedPromos();
  }

  Future<void> _loadStats() async {
    try {
      final data = await _service.getPromoStats();
      if (mounted) setState(() => _stats = data);
    } on PromoApiServiceException catch (e) {
      if (mounted) {
        if (e.statusCode == 401) {
          _handleUnauthorized();
        } else if (e.statusCode == 403) {
          _handleForbidden();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Ошибка статистики: ${e.message}'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadClaimedPromos() async {
    try {
      final data = await _service.getClaimedPromos();
      if (mounted) setState(() => _claimedPromos = data);
    } on PromoApiServiceException catch (e) {
      // Не показываем ошибку - просто не отображаем данные
      if (mounted && e.statusCode != 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Ошибка загрузки выданных промокодов: ${e.message}'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      // Игнорируем
    }
  }

  Future<void> _uploadExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result == null) return;

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();

    setState(() {
      _isLoading = true;
    });

    try {
      await _service.uploadPromoFile(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Промокоды загружены!'),
              backgroundColor: Colors.green),
        );
        _loadAllData();
      }
    } on PromoApiServiceException catch (e) {
      if (mounted) {
        if (e.statusCode == 401) {
          _handleUnauthorized();
        } else if (e.statusCode == 403) {
          _handleForbidden();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Ошибка: ${e.message}'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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

  Future<void> _uploadFromGoogleSheet() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ссылка на Google Таблицу'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              hintText: 'https://docs.google.com/spreadsheets/d/...'),
        ),
        actions: [
          TextButton(
              onPressed: Navigator.of(ctx).pop, child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              Navigator.of(ctx).pop();

              setState(() {
                _isLoading = true;
              });

              try {
                await _service.uploadPromoFromGoogleSheet(url);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Промокоды загружены!'),
                        backgroundColor: Colors.green),
                  );
                  _loadAllData();
                }
              } on PromoApiServiceException catch (e) {
                if (mounted) {
                  if (e.statusCode == 401) {
                    _handleUnauthorized();
                  } else if (e.statusCode == 403) {
                    _handleForbidden();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Ошибка: ${e.message}'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              }
            },
            child: const Text('Загрузить'),
          ),
        ],
      ),
    );
  }

  void _handleUnauthorized() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Сессия истекла. Требуется вход'),
          backgroundColor: Colors.red),
    );
  }

  void _handleForbidden() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Доступ запрещён: нужны права администратора'),
          backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Управление промокодами')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Загрузка промокодов
                  const Text('Загрузить промокоды:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _uploadExcel,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Загрузить Excel'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _uploadFromGoogleSheet,
                    icon: const Icon(Icons.link),
                    label: const Text('Из Google Таблицы'),
                  ),

                  const SizedBox(height: 24),

                  // Статистика по остаткам
                  const Text('Свободные промокоды:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_stats == null)
                    const Center(child: Text('Загрузка...'))
                  else ...[
                    _buildDetailedStats(),
                  ],

                  const SizedBox(height: 24),

                  // Выданные промокоды
                  const Text('Выданные промокоды:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_claimedPromos == null)
                    const Center(child: Text('Загрузка...'))
                  else if (_claimedPromos!.isEmpty)
                    const Center(child: Text('Нет выданных промокодов'))
                  else
                    _buildClaimedPromosList(),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailedStats() {
    final summaryRaw = _stats?['summary'];
    final summary = summaryRaw is Map
        ? Map<String, int>.from(summaryRaw)
        : {'JET': 0, 'YANDEX': 0, 'WHOOSH': 0, 'BOLT': 0};

    final byDateRaw = _stats?['by_date'];
    final byDate =
        byDateRaw is List ? byDateRaw.cast<Map<String, dynamic>>() : [];

    return Column(
      children: [
        // Общая сводка
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Всего свободно:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Бренд')),
                    DataColumn(label: Text('Свободно')),
                    DataColumn(label: Text('Формат кода')),
                  ],
                  rows: [
                    _buildBrandRow('JET', summary['JET'] ?? 0, 'GT10-XXXXXX'),
                    _buildBrandRow(
                        'YANDEX', summary['YANDEX'] ?? 0, 'ocf/ocm + цифры'),
                    _buildBrandRow(
                        'WHOOSH', summary['WHOOSH'] ?? 0, 'WSH_XXXXXX'),
                    _buildBrandRow('BOLT', summary['BOLT'] ?? 0, 'BOLTXXXXXX'),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // По датам
        if (byDate.isNotEmpty) ...[
          const Text('По датам окончания:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          for (final item in byDate)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Действительны до: ${item['valid_until']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (item['counts'] is Map) ...[
                      DataTable(
                        columns: const [
                          DataColumn(label: Text('Бренд')),
                          DataColumn(label: Text('Количество')),
                        ],
                        rows: [
                          for (final brand in [
                            'JET',
                            'YANDEX',
                            'WHOOSH',
                            'BOLT'
                          ])
                            if ((item['counts'] as Map).containsKey(brand))
                              DataRow(
                                cells: [
                                  DataCell(Text(brand)),
                                  DataCell(Text(
                                      '${(item['counts'] as Map)[brand]}')),
                                ],
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  DataRow _buildBrandRow(String brand, int count, String format) {
    return DataRow(
      cells: [
        DataCell(Text(brand)),
        DataCell(Text('$count')),
        DataCell(Text(format)),
      ],
    );
  }

  Widget _buildClaimedPromosList() {
    return Column(
      children: [
        for (final user in _claimedPromos!)
          if (user is Map<String, dynamic> &&
              user['promo_codes'] != null &&
              (user['promo_codes'] as Map).isNotEmpty)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${user['username'] ?? 'Пользователь'} (${user['first_name'] ?? ''})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    for (final entry
                        in (user['promo_codes'] as Map<String, dynamic>)
                            .entries)
                      if (entry.value is List &&
                          (entry.value as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${entry.key}: ${(entry.value as List).join(", ")}',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
