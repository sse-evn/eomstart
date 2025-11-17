// ====== AdminPromoScreen.dart (ОБНОВЛЕНО С КНОПКОЙ И ПОИСКОМ ДЛЯ АУДИТА) ======

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/services/promo_api_service.dart';

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
  List<dynamic>?
      _claimedPromos; // Будет содержать {user: ..., promo_codes: {...}, created_at: ...}
  Map<String, dynamic>? _activeBrand;
  String? _selectedBrand;
  DateTime? _endDate;

  // --- НОВЫЕ ПЕРЕМЕННЫЕ ---
  bool _showClaimedPromos = false; // Управляет видимостью списка
  String _searchQuery = ''; // Для поиска по имени

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _loadStats();
    await _loadClaimedPromos(); // Теперь загружает и даты
    await _loadActiveBrand();
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
      if (mounted && e.statusCode != 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Ошибка загрузки выданных промокодов: ${e.message}'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {}
  }

  Future<void> _loadActiveBrand() async {
    try {
      final data = await _service.getActivePromoBrand();
      if (mounted) setState(() => _activeBrand = data);
    } catch (e) {}
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
              content: Text('Промокоды загружены и обработаны!'),
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
                        content: Text('Промокоды загружены и обработаны!'),
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

  Future<void> _activateBrand() async {
    if (_selectedBrand == null || _endDate == null) return;

    final now = DateTime.now();
    final difference = _endDate!.difference(now).inDays;
    final daysToSet = difference > 0 ? difference : 1;

    setState(() {
      _isLoading = true;
    });

    try {
      await _service.setActivePromoBrand(_selectedBrand!, days: daysToSet);
      await _loadActiveBrand();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Активировано!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearActiveBrand() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _service.clearActivePromoBrand();
      await _loadActiveBrand();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ограничение снято')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
                  // Активный бренд
                  const Text('Активный бренд:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_activeBrand != null)
                    Card(
                      child: ListTile(
                        leading: Icon(_getBrandIcon(_activeBrand!['brand'])),
                        title: Text('Только ${_activeBrand!['brand']}'),
                        subtitle: Text('До ${_activeBrand!['expires_at']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          onPressed: _clearActiveBrand,
                        ),
                      ),
                    )
                  else
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('Все бренды доступны'),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Форма активации
                  const Text('Активировать бренд:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedBrand,
                    items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBrand = v),
                    decoration:
                        const InputDecoration(labelText: 'Выберите бренд'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    readOnly: true,
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime(2030),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          _endDate = pickedDate;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Дата окончания активности',
                      hintText: _endDate == null
                          ? 'Выберите дату'
                          : _endDate!.toLocal().toString().split(' ')[0],
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                  ),
                  if (_endDate != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Будет активно примерно ${_endDate!.difference(DateTime.now()).inDays.abs()} дней.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _selectedBrand != null && _endDate != null
                        ? _activateBrand
                        : null,
                    child: const Text('Активировать бренд'),
                  ),
                  const SizedBox(height: 24),

                  // Загрузка промокодов (с уточнением)
                  const Text('Загрузить промокоды:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text(
                    'Загрузите Excel/CSV файл с одной колонкой "Промокод".\n'
                    'Бренд будет определен автоматически по формату кода.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
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

                  // Статистика (Свободные промокоды)
                  const Text('Свободные промокоды:',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_stats == null)
                    const Center(child: Text('Загрузка...'))
                  else
                    _buildDetailedStats(),
                  const SizedBox(height: 24),

                  // --- НОВЫЙ БЛОК: КНОПКА И СПИСОК ВЫДАННЫХ ПРОМОКОДОВ ---

                  // Кнопка для показа/скрытия списка
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _showClaimedPromos = !_showClaimedPromos;
                            });
                          },
                          icon: Icon(_showClaimedPromos
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down),
                          label: Text(
                            _showClaimedPromos
                                ? 'Скрыть выданные промокоды'
                                : 'Показать выданные промокоды',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Поле поиска (видимо только если список открыт)
                  if (_showClaimedPromos) ...[
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Поиск по имени пользователя',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Список выданных промокодов (видимый только при _showClaimedPromos == true)
                  if (_showClaimedPromos) ...[
                    const Text('Выданные промокоды:',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_claimedPromos == null)
                      const Center(child: Text('Загрузка...'))
                    else if (_claimedPromos!.isEmpty)
                      const Center(child: Text('Нет выданных промокодов'))
                    else
                      _buildClaimedPromosListByDate(), // Новый метод
                  ],

                  const SizedBox(height: 24),
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
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Бренд')),
                    DataColumn(label: Text('Свободно')),
                    DataColumn(label: Text('Формат кода')),
                  ],
                  rows: [
                    _buildBrandRow('JET', summary['JET'] ?? 0, 'GT9-XXXXXX'),
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
                        columnSpacing: 16,
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
        DataCell(Row(
          children: [
            Icon(_getBrandIcon(brand), size: 18),
            const SizedBox(width: 8),
            Text(brand),
          ],
        )),
        DataCell(Text('$count')),
        DataCell(Text(format)),
      ],
    );
  }

  // --- НОВЫЙ МЕТОД: ГРУППИРОВКА ПО ДАТАМ С ПОИСКОМ ---
  Widget _buildClaimedPromosListByDate() {
    // Фильтруем пользователей по поисковому запросу
    final filteredUsers = <Map<String, dynamic>>[];

    for (final item in _claimedPromos!) {
      if (item is Map<String, dynamic> &&
          item['promo_codes'] != null &&
          (item['promo_codes'] as Map).isNotEmpty) {
        // Получаем имя пользователя
        final username = (item['username'] as String?)?.toLowerCase() ?? '';
        final firstName = (item['first_name'] as String?)?.toLowerCase() ?? '';

        // Проверяем, соответствует ли пользователь поисковому запросу
        if (_searchQuery.isEmpty ||
            username.contains(_searchQuery) ||
            firstName.contains(_searchQuery)) {
          filteredUsers.add(item);
        }
      }
    }

    // Если нет результатов поиска, показываем сообщение
    if (filteredUsers.isEmpty && _searchQuery.isNotEmpty) {
      return const Center(
        child: Text(
          'Ничего не найдено',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Группируем отфильтрованных пользователей по дате выдачи
    final groupedByDate = <String, List<Map<String, dynamic>>>{};

    for (final item in filteredUsers) {
      // Получаем дату выдачи
      final createdAtStr = item['created_at'] as String?;
      if (createdAtStr != null) {
        final date = DateTime.parse(createdAtStr).toLocal();
        final dateKey = date.toIso8601String().split('T')[0];

        if (!groupedByDate.containsKey(dateKey)) {
          groupedByDate[dateKey] = [];
        }
        groupedByDate[dateKey]!.add(item);
      }
    }

    // Создаем список карточек по датам
    final dateWidgets = <Widget>[];

    // Сортируем ключи (даты) по убыванию (новые сверху)
    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (final dateKey in sortedDates) {
      final usersForDate = groupedByDate[dateKey]!;
      // Форматируем дату для отображения
      final displayDate =
          DateFormat('dd.MM.yyyy').format(DateTime.parse(dateKey));
      // Определяем название дня недели
      final dayOfWeek =
          DateFormat('EEEE', 'ru_RU').format(DateTime.parse(dateKey));
      final headerText = '$displayDate ($dayOfWeek)';

      dateWidgets.add(
        Container(
          margin: const EdgeInsets.only(top: 16, bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            headerText,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );

      for (final user in usersForDate) {
        dateWidgets.add(
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
                      in (user['promo_codes'] as Map<String, dynamic>).entries)
                    if (entry.value is List && (entry.value as List).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(_getBrandIcon(entry.key), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${entry.key}: ${(entry.value as List).join(", ")}',
                                style: const TextStyle(fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
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
    }

    return Column(children: dateWidgets);
  }

  // Вспомогательная функция для иконок брендов
  IconData _getBrandIcon(String brand) {
    switch (brand) {
      case 'JET':
        return Icons.electric_scooter;
      case 'YANDEX':
        return Icons.map;
      case 'WHOOSH':
        return Icons.directions_bike;
      case 'BOLT':
        return Icons.bolt;
      default:
        return Icons.help;
    }
  }
}
