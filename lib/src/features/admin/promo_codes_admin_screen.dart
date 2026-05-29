import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/src/core/services/promo_api_service.dart';
import 'package:micro_mobility_app/src/features/admin/bolt_accounts_admin_screen.dart';
import 'package:micro_mobility_app/src/features/admin/promo_list_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminPromoScreen extends StatefulWidget {
  const AdminPromoScreen({super.key});

  @override
  State<AdminPromoScreen> createState() => _AdminPromoScreenState();
}

class _AdminPromoScreenState extends State<AdminPromoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Material(
          color: primaryColor,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Управление', icon: Icon(Icons.local_offer, size: 18)),
              Tab(text: 'База кодов', icon: Icon(Icons.list_alt, size: 18)),
              Tab(text: 'Bolt Аккаунты', icon: Icon(Icons.bolt, size: 18)),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(color: Colors.white, width: 2.0),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              PromoManagementContent(),
              PromoListScreen(),
              BoltAccountsAdminScreen(),
            ],
          ),
        ),
      ],
    );
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
  Map<String, dynamic>? _activeBrand;
  String? _selectedBrand;
  DateTimeRange? _activeBrandDateRange;
  DateTime? _selectedValidUntil; // Дата окончания, выбранная для загрузки файла

  // --- НОВАЯ ПЕРЕМЕННАЯ ---
  String? _selectedBrandForUpload; // Бренд, выбранный для загрузки файла

  String _searchQuery = ''; // Для поиска по имени
  Map<String, String> _brandFormats = {}; // Форматы промокодов

  DateTime? _historyStartDate =
      DateTime.now().subtract(const Duration(days: 7));
  DateTime? _historyEndDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _loadStats();
    await _loadClaimedPromos();
    await _loadActiveBrand();
    await _loadBrandFormats();
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
    }
  }

  Future<void> _exportToCSV() async {
    final promos = _getFilteredHistory();
    if (promos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Нет данных для экспорта за выбранный период')),
        );
      }
      return;
    }

    final buffer = StringBuffer();
    // CSV Header (с BOM для корректного отображения кириллицы в Excel)
    buffer.write('\uFEFF');
    buffer.writeln('Дата,Время,Никнейм,Имя,Бренд,Промокоды');

    for (final item in promos) {
      if (item is Map<String, dynamic> &&
          item['promo_codes'] != null &&
          (item['promo_codes'] as Map).isNotEmpty) {
        final dateStr = item['created_at'] as String? ?? '';
        var date = '';
        var time = '';
        if (dateStr.isNotEmpty) {
          final parsed = DateTime.tryParse(dateStr);
          if (parsed != null) {
            date = DateFormat('dd.MM.yyyy').format(parsed);
            time = DateFormat('HH:mm').format(parsed);
          } else {
            date = dateStr.split('T')[0];
          }
        }
        final username = item['username']?.toString() ?? '';
        final firstName = item['first_name']?.toString() ?? '';

        final codesMap = item['promo_codes'] as Map<String, dynamic>;
        for (final entry in codesMap.entries) {
          if (entry.value is List && (entry.value as List).isNotEmpty) {
            final brand = entry.key;
            final codes = (entry.value as List).join('; ');
            buffer.writeln('$date,$time,$username,$firstName,$brand,$codes');
          }
        }
      }
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/eom_promo_history.csv');
      await file.writeAsString(buffer.toString(), flush: true);

      await Share.shareXFiles([XFile(file.path)],
          text: 'История выдачи промокодов EOM');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
      }
    }
  }

  Future<void> _copyDailyReport() async {
    final promos = _getFilteredHistory();
    if (promos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет данных для копирования')),
        );
      }
      return;
    }

    final buffer = StringBuffer();

    for (final item in promos) {
      if (item is Map<String, dynamic> &&
          item['promo_codes'] != null &&
          (item['promo_codes'] as Map).isNotEmpty) {
        final username = item['username']?.toString() ?? '';
        final phone = item['phone']?.toString() ?? '';
        final codesMap = item['promo_codes'] as Map<String, dynamic>;

        for (final entry in codesMap.entries) {
          if (entry.value is List && (entry.value as List).isNotEmpty) {
            final brand = entry.key;
            final codes = (entry.value as List).join(', ');
            buffer.writeln('🎫 ВЫДАН ПРОМОКОД');
            buffer.writeln('👤 @$username');
            if (phone.isNotEmpty) {
              buffer.writeln('📱 $phone');
            }
            buffer.writeln('🛴 $brand');
            buffer.writeln('🔑 $codes');
            buffer.writeln();
          }
        }
      }
    }

    if (buffer.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Отчет скопирован в буфер обмена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _loadActiveBrand() async {
    try {
      final data = await _service.getActivePromoBrand();
      if (mounted) setState(() => _activeBrand = data);
    } catch (e) {}
  }

  Future<void> _loadBrandFormats() async {
    try {
      final data = await _service.getBrandFormats();
      if (mounted) setState(() => _brandFormats = data);
    } catch (e) {
      debugPrint('Error loading brand formats: $e');
    }
  }

  void _showBrandFormatsDialog() {
    final controllers = <String, TextEditingController>{};
    for (var brand in ['JET', 'YANDEX', 'WHOOSH', 'BOLT']) {
      controllers[brand] =
          TextEditingController(text: _brandFormats[brand] ?? '');
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Типы промокодов'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: controllers.entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: e.value,
                      decoration: InputDecoration(
                        labelText: 'Формат для ${e.key}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                for (var brand in controllers.keys) {
                  await _service.updateBrandFormat(
                      brand, controllers[brand]!.text);
                }
                await _loadBrandFormats();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Форматы обновлены')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: Colors.red));
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    if (result == null) return;

    String? dialogBrand;
    String? dialogSubtype;
    DateTimeRange? dialogDateRange;

    final selectedData = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Выберите бренд и дату'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: dialogBrand,
                items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setDialogState(() {
                  dialogBrand = v;
                  dialogSubtype = null; // Сбрасываем при смене бренда
                }),
                decoration:
                    const InputDecoration(labelText: 'Бренд промокодов'),
              ),
              if (dialogBrand == 'YANDEX') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: dialogSubtype,
                  items: const [
                    DropdownMenuItem(
                        value: null,
                        child: Text('⚡️ Автоопределение (Смешанный файл)')),
                    DropdownMenuItem(
                        value: 'start', child: Text('🔴 Бесплатный старт ')),
                    DropdownMenuItem(
                        value: 'minutes', child: Text('🟢 Бесплатные минуты ')),
                  ],
                  onChanged: (v) => setDialogState(() => dialogSubtype = v),
                  decoration: const InputDecoration(labelText: 'Тип промокода'),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                readOnly: true,
                onTap: () async {
                  final pickedRange = await showDateRangePicker(
                    context: ctx,
                    initialDateRange: DateTimeRange(
                      start: DateTime.now(),
                      end: DateTime.now().add(const Duration(days: 7)),
                    ),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime(2030),
                  );
                  if (pickedRange != null) {
                    setDialogState(() => dialogDateRange = pickedRange);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Период действия',
                  hintText: dialogDateRange == null
                      ? 'Выберите даты'
                      : '${dialogDateRange!.start.toLocal().toString().split(' ')[0]} - ${dialogDateRange!.end.toLocal().toString().split(' ')[0]}',
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                if (dialogBrand != null && dialogDateRange != null) {
                  Navigator.pop(ctx, {
                    'brand': dialogBrand!,
                    'validFrom': dialogDateRange!.start.toIso8601String().split('T')[0],
                    'validUntil': dialogDateRange!.end.toIso8601String().split('T')[0],
                    if (dialogSubtype != null) 'subtype': dialogSubtype!,
                  });
                }
              },
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      ),
    );

    if (selectedData == null) return;

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();

    setState(() => _isLoading = true);

    try {
      await _service.uploadPromoFile(
        bytes,
        brand: selectedData['brand']!,
        validFrom: selectedData['validFrom']!,
        validUntil: selectedData['validUntil']!,
        subtype: selectedData['subtype'],
      );

      if (mounted) {
        final subtypeLabel = selectedData['subtype'] == 'start'
            ? ' (старт)'
            : selectedData['subtype'] == 'minutes'
                ? ' (минуты)'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Промокоды ${selectedData['brand']}$subtypeLabel загружены!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAllData();
      }
    } on PromoApiServiceException catch (e) {
      if (!mounted) return;

      if (e.statusCode == 401) {
        _handleUnauthorized();
      } else if (e.statusCode == 403) {
        _handleForbidden();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки файла: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadFromGoogleSheet() async {
    final controller = TextEditingController();
    String? dialogBrand;
    String? dialogSubtype;
    DateTimeRange? dialogDateRange;

    final urlData = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Загрузка из Google Таблицы'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Ссылка на таблицу',
                    hintText: 'https://docs.google.com/spreadsheets/d/...',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: dialogBrand,
                  items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setDialogState(() {
                    dialogBrand = v;
                    dialogSubtype = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Бренд'),
                ),
                if (dialogBrand == 'YANDEX') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: dialogSubtype,
                    items: const [
                      DropdownMenuItem(
                          value: null,
                          child: Text('⚡️ Автоопределение (Смешанный файл)')),
                      DropdownMenuItem(
                          value: 'start',
                          child: Text('🔴 Бесплатный старт (начинается с 2)')),
                      DropdownMenuItem(
                          value: 'minutes',
                          child: Text('🟢 Бесплатные минуты (начинается с 3)')),
                    ],
                    onChanged: (v) => setDialogState(() => dialogSubtype = v),
                    decoration:
                        const InputDecoration(labelText: 'Тип промокода'),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  readOnly: true,
                  onTap: () async {
                    final pickedRange = await showDateRangePicker(
                      context: ctx,
                      initialDateRange: DateTimeRange(
                        start: DateTime.now(),
                        end: DateTime.now().add(const Duration(days: 7)),
                      ),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime(2030),
                    );
                    if (pickedRange != null) {
                      setDialogState(() => dialogDateRange = pickedRange);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Период действия',
                    hintText: dialogDateRange == null
                        ? 'Выберите даты'
                        : '${dialogDateRange!.start.toLocal().toString().split(' ')[0]} - ${dialogDateRange!.end.toLocal().toString().split(' ')[0]}',
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty &&
                    dialogBrand != null &&
                    dialogDateRange != null) {
                  Navigator.pop(ctx, {
                    'url': controller.text.trim(),
                    'brand': dialogBrand!,
                    'validFrom': dialogDateRange!.start.toIso8601String().split('T')[0],
                    'validUntil': dialogDateRange!.end.toIso8601String().split('T')[0],
                    if (dialogSubtype != null) 'subtype': dialogSubtype!,
                  });
                }
              },
              child: const Text('Загрузить'),
            ),
          ],
        ),
      ),
    );

    if (urlData == null) return;

    setState(() => _isLoading = true);
    try {
      await _service.uploadPromoFromGoogleSheet(
        urlData['url']!,
        brand: urlData['brand']!,
        validFrom: urlData['validFrom']!,
        validUntil: urlData['validUntil']!,
        subtype: urlData['subtype'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Промокоды из Google Таблицы загружены!'),
            backgroundColor: Colors.green,
          ),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearPromoCodes() async {
    String? dialogBrand;
    DateTime? dialogDate;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Очистка промокодов ⚠️',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Будут удалены ТОЛЬКО НЕВЫДАННЫЕ промокоды.',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: dialogBrand,
                items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                    .map((b) => DropdownMenuItem(
                        value: b,
                        child: Text(b,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))))
                    .toList(),
                onChanged: (v) => setDialogState(() => dialogBrand = v),
                decoration: const InputDecoration(
                  labelText: 'Бренд промокодов',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                readOnly: true,
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (pickedDate != null) {
                    setDialogState(() => dialogDate = pickedDate);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Дата окончания (опционально)',
                  hintText: dialogDate == null
                      ? 'Удалить все даты'
                      : dialogDate!.toLocal().toString().split(' ')[0],
                  suffixIcon: dialogDate != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              setDialogState(() => dialogDate = null),
                        )
                      : const Icon(Icons.calendar_today),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (dialogBrand != null) {
                  Navigator.pop(ctx, {
                    'brand': dialogBrand!,
                    if (dialogDate != null)
                      'validUntil': dialogDate!.toIso8601String().split('T')[0],
                  });
                }
              },
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      final deletedCount = await _service.clearPromoCodes(
        brand: result['brand']!,
        validUntil: result['validUntil'],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Успешно удалено невыданных промокодов: $deletedCount'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка очистки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _activateBrand() async {
    if (_selectedBrand == null || _activeBrandDateRange == null) return;
    
    // Create expiration date at the end of the selected day
    final startsAt = _activeBrandDateRange!.start.toIso8601String().split('T')[0];
    final expiresAt = DateTime(_activeBrandDateRange!.end.year, _activeBrandDateRange!.end.month, _activeBrandDateRange!.end.day, 23, 59, 59).toIso8601String();
    
    setState(() {
      _isLoading = true;
    });
    try {
      await _service.setActivePromoBrand(_selectedBrand!, startsAt: startsAt, expiresAt: expiresAt);
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

  Future<void> _claimPromoManual() async {
    String? selectedBrand;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Получить промокод вручную'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Промокод будет выдан вам в без смены.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedBrand,
                items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedBrand = v),
                decoration: const InputDecoration(labelText: 'Выберите бренд'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                if (selectedBrand != null) Navigator.pop(ctx, selectedBrand);
              },
              child: const Text('Получить'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      final res = await _service.claimPromoManual(result);
      final codes = (res['promo_codes'] as List).join(', ');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('✅ Успешно'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Бренд: $result\nВаш(и) промокод(ы):'),
                const SizedBox(height: 8),
                SelectableText(
                  codes,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: codes));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Промокод скопирован в буфер обмена'),
                        backgroundColor: Colors.green),
                  );
                },
                child: const Text('Скопировать',
                    style: TextStyle(color: Colors.green)),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('ОК')),
            ],
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchAndDeletePromo() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поиск промокода'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              hintText: 'Введите промокод', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;
              Navigator.pop(ctx);
              await _showPromoDetails(controller.text.trim());
            },
            child: const Text('Найти'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPromoDetails(String code) async {
    setState(() => _isLoading = true);
    Map<String, dynamic>? data;
    try {
      data = await _service.searchPromoCode(code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = false);

    if (!mounted || data == null) return;

    final isClaimed = data['is_claimed'] == true;
    final info = StringBuffer();
    info.writeln('Код: ${data['promo_code']}');
    info.writeln('Бренд: ${data['brand']}');
    info.writeln('Годен до: ${data['valid_until']}');
    if (data.containsKey('subtype')) {
      info.writeln('Подтип: ${data['subtype']}');
    }
    info.writeln('\nСтатус: ${isClaimed ? "🔴 Выдан" : "🟢 Свободен"}');

    if (isClaimed) {
      info.writeln('Кому выдан: ${data['username']} (${data['first_name']})');
      info.writeln('Дата выдачи: ${data['claimed_at']}');
    }

    final deleteConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Информация о промокоде'),
        content: SelectableText(info.toString()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Закрыть')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить из БД'),
          ),
        ],
      ),
    );

    if (deleteConfirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _service.deletePromoCode(code);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Промокод удален'), backgroundColor: Colors.green));
          _loadAllData();
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              displacement: 20,
              color: Colors.green,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildSectionHeader(
                      'Текущее состояние', Icons.dashboard_customize_outlined),
                  _buildActiveBrandCard(isDarkMode),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                      'Активация ограничений', Icons.bolt_outlined),
                  _buildActivationForm(isDarkMode),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                      'Пополнение базы', Icons.cloud_upload_outlined),
                  _buildUploadActions(isDarkMode),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                      'Ручное управление', Icons.admin_panel_settings_outlined),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _claimPromoManual,
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: const Text('Взять без смены'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.withOpacity(0.1),
                            foregroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _searchAndDeletePromo,
                          icon: const Icon(Icons.manage_search_outlined),
                          label: const Text('Поиск кода'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple.withOpacity(0.1),
                            foregroundColor: Colors.purple,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                    'Статистика остатков',
                    Icons.analytics_outlined,
                    trailing: IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          size: 18, color: Colors.grey),
                      onPressed: _showBrandFormatsDialog,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  if (_stats == null)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator()))
                  else
                    _buildDetailedStats(isDarkMode),
                  const SizedBox(height: 24),
                  _buildSectionHeader(
                      'История выдачи', Icons.history_edu_outlined),
                  _buildClaimedPromosSection(isDarkMode),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.grey))),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildActiveBrandCard(bool isDarkMode) {
    if (_activeBrand == null || _activeBrand!['brand'] == 'NONE') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withOpacity(0.05)
              : Colors.red.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.block,
                color: Colors.red, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Выдача отключена',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                  Text('Ни один бренд не установлен, выдача невозможна',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final brand = _activeBrand!['brand'] as String;
    final brandColor = _getBrandColor(brand);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [brandColor.withOpacity(0.15), brandColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: brandColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: brandColor.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(_getBrandIcon(brand), color: brandColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Активен только $brand',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18)),
                    Text('Действует до ${_activeBrand!['expires_at']}',
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _clearActiveBrand,
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivationForm(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color:
                isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedBrand,
            items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text(b,
                        style: const TextStyle(fontWeight: FontWeight.bold))))
                .toList(),
            onChanged: (v) => setState(() => _selectedBrand = v),
            decoration: InputDecoration(
              labelText: 'Выберите бренд',
              prefixIcon: const Icon(Icons.branding_watermark_outlined),
              filled: true,
              fillColor:
                  isDarkMode ? Colors.black.withOpacity(0.2) : Colors.grey[50],
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            readOnly: true,
            onTap: () async {
              final pickedRange = await showDateRangePicker(
                context: context,
                initialDateRange: DateTimeRange(
                  start: DateTime.now(),
                  end: DateTime.now().add(const Duration(days: 7)),
                ),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime(2030),
              );
              if (pickedRange != null) setState(() => _activeBrandDateRange = pickedRange);
            },
            decoration: InputDecoration(
              labelText: 'Период действия ограничения',
              hintText: _activeBrandDateRange == null
                  ? 'Выберите даты'
                  : '${DateFormat('dd.MM.yy').format(_activeBrandDateRange!.start)} - ${DateFormat('dd.MM.yy').format(_activeBrandDateRange!.end)}',
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              filled: true,
              fillColor:
                  isDarkMode ? Colors.black.withOpacity(0.2) : Colors.grey[50],
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedBrand != null && _activeBrandDateRange != null
                  ? _activateBrand
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Установить ограничение',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadActions(bool isDarkMode) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _uploadExcel,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.description_outlined,
                      color: Colors.green, size: 32),
                  SizedBox(height: 12),
                  Text('Excel / CSV',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: _uploadFromGoogleSheet,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.grid_on_outlined, color: Colors.blue, size: 32),
                  SizedBox(height: 12),
                  Text('Google Sheets',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: _clearPromoCodes,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.delete_sweep_outlined,
                      color: Colors.red, size: 32),
                  SizedBox(height: 12),
                  Text('Очистить',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: _historyStartDate != null && _historyEndDate != null
          ? DateTimeRange(start: _historyStartDate!, end: _historyEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now()),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (range != null) {
      setState(() {
        _historyStartDate = range.start;
        _historyEndDate = range.end;
      });
    }
  }

  Widget _buildClaimedPromosSection(bool isDarkMode) {
    if (_claimedPromos == null) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }

    final dateText = _historyStartDate != null && _historyEndDate != null
        ? '${DateFormat('dd.MM.yy').format(_historyStartDate!)} - ${DateFormat('dd.MM.yy').format(_historyEndDate!)}'
        : 'Период не выбран';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _pickDateRange,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.05)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range,
                          size: 20, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dateText,
                          style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.green),
                onPressed: _exportToCSV,
                tooltip: 'Скачать отчет Excel (CSV)',
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.blue),
                onPressed: _copyDailyReport,
                tooltip: 'Скопировать отчет для Telegram',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color:
                isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Поиск по сотруднику...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
        ),
        const SizedBox(height: 16),
        _buildClaimedPromosListByDate(),
      ],
    );
  }

  Widget _buildDetailedStats(bool isDarkMode) {
    final summaryRaw = _stats?['summary'];
    final summary = summaryRaw is Map
        ? Map<String, int>.from(summaryRaw)
        : {'JET': 0, 'YANDEX': 0, 'WHOOSH': 0, 'BOLT': 0};

    final yandexStart = summary['YANDEX_START'] ?? 0;
    final yandexMinutes = summary['YANDEX_MINUTES'] ?? 0;
    final hasYandexSubtypes = yandexStart > 0 || yandexMinutes > 0;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color:
                isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStatRow('JET', summary['JET'] ?? 0,
                    _brandFormats['JET'] ?? 'GT9-XXXXXX', isDarkMode),
                const Divider(height: 24),
                _buildStatRow('YANDEX', summary['YANDEX'] ?? 0,
                    _brandFormats['YANDEX'] ?? 'ocf/ocm + цифры', isDarkMode),
                if (hasYandexSubtypes) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 46),
                    child: Column(
                      children: [
                        _buildSubtypeRow('🔴 Старт', yandexStart, Colors.red),
                        const SizedBox(height: 4),
                        _buildSubtypeRow(
                            '🟢 Минуты', yandexMinutes, Colors.green),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 24),
                _buildStatRow('WHOOSH', summary['WHOOSH'] ?? 0,
                    _brandFormats['WHOOSH'] ?? 'WSH_XXXXXX', isDarkMode),
                const Divider(height: 24),
                _buildStatRow('BOLT', summary['BOLT'] ?? 0,
                    _brandFormats['BOLT'] ?? 'BOLTXXXXXX', isDarkMode),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtypeRow(String label, int count, Color color) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: count > 0
                ? color.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count',
              style: TextStyle(
                  color: count > 0 ? color : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildStatRow(
      String brand, int count, String format, bool isDarkMode) {
    final color = _getBrandColor(brand);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(_getBrandIcon(brand), color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(brand,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
              Text(format,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: count > 0
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: TextStyle(
                  color: count > 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
      ],
    );
  }

  List<dynamic> _getFilteredHistory() {
    final promos = _claimedPromos ?? [];
    return promos.where((item) {
      if (item is! Map<String, dynamic>) return false;

      if (item['promo_codes'] == null || (item['promo_codes'] as Map).isEmpty)
        return false;

      // Фильтр по дате
      final createdAtStr = item['created_at'] as String?;
      if (createdAtStr != null &&
          _historyStartDate != null &&
          _historyEndDate != null) {
        final parsed = DateTime.tryParse(createdAtStr);
        if (parsed != null) {
          final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
          final startOnly = DateTime(_historyStartDate!.year,
              _historyStartDate!.month, _historyStartDate!.day);
          final endOnly = DateTime(_historyEndDate!.year,
              _historyEndDate!.month, _historyEndDate!.day);
          if (dateOnly.isBefore(startOnly) || dateOnly.isAfter(endOnly)) {
            return false;
          }
        }
      }

      // Фильтр по поиску
      if (_searchQuery.isNotEmpty) {
        final username = (item['username'] as String?)?.toLowerCase() ?? '';
        final firstName = (item['first_name'] as String?)?.toLowerCase() ?? '';
        if (!username.contains(_searchQuery) &&
            !firstName.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // --- НОВЫЙ МЕТОД: ГРУППИРОВКА ПО ДАТАМ С ПОИСКОМ ---
  Widget _buildClaimedPromosListByDate() {
    final filteredUsers = _getFilteredHistory();

    if (filteredUsers.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('За этот период пусто или ничего не найдено',
                  style: TextStyle(color: Colors.grey))));
    }

    final groupedByDate = <String, List<Map<String, dynamic>>>{};
    for (final item in filteredUsers) {
      final createdAtStr = item['created_at'] as String?;
      if (createdAtStr != null) {
        final dateKey = createdAtStr.split('T')[0];
        if (!groupedByDate.containsKey(dateKey)) groupedByDate[dateKey] = [];
        groupedByDate[dateKey]!.add(item);
      }
    }

    final sortedDates = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        for (final dateKey in sortedDates) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                    DateFormat('dd MMMM yyyy', 'ru_RU')
                        .format(DateTime.parse(dateKey)),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: Colors.grey,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
          for (final user in groupedByDate[dateKey]!)
            _buildClaimedUserCard(user),
        ],
      ],
    );
  }

  Widget _buildClaimedUserCard(Map<String, dynamic> user) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDarkMode
                ? Colors.white.withOpacity(0.05)
                : Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text('${user['username'] ?? 'User'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              if (user['first_name'] != null)
                Text(' • ${user['first_name']}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
          if (user['phone'] != null && user['phone'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_android, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Text('${user['phone']}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          for (final entry
              in (user['promo_codes'] as Map<String, dynamic>).entries)
            if (entry.value is List && (entry.value as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_getBrandIcon(entry.key),
                        size: 14, color: _getBrandColor(entry.key)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${(entry.value as List).join(", ")}',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Color _getBrandColor(String brand) {
    switch (brand.toUpperCase()) {
      case 'JET':
        return Colors.yellow[700]!;
      case 'YANDEX':
        return const Color(0xFFFFCC00);
      case 'WHOOSH':
        return Colors.orange;
      case 'BOLT':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  IconData _getBrandIcon(String brand) {
    switch (brand.toUpperCase()) {
      case 'JET':
        return Icons.electric_scooter;
      case 'YANDEX':
        return Icons.map;
      case 'WHOOSH':
        return Icons.directions_bike;
      case 'BOLT':
        return Icons.bolt;
      default:
        return Icons.help_outline;
    }
  }
}
