import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/src/core/services/promo_api_service.dart';

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
  Map<String, dynamic>? _activeBrand;
  String? _selectedBrand;
  DateTime? _endDate;
  DateTime? _selectedValidUntil; // Дата окончания, выбранная для загрузки файла


  // --- НОВАЯ ПЕРЕМЕННАЯ ---
  String? _selectedBrandForUpload; // Бренд, выбранный для загрузки файла

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
    await _loadClaimedPromos();
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
    }
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
    allowedExtensions: ['xlsx', 'xls', 'csv'],
  );
  if (result == null) return;

  // Диалог должен вернуть Map<String, String>
  final selectedData = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Выберите бренд и дату'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedBrandForUpload,
            items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                .toList(),
            onChanged: (v) => setState(() => _selectedBrandForUpload = v),
            decoration: const InputDecoration(labelText: 'Бренд промокодов'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            readOnly: true,
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime(2030),
              );
              if (pickedDate != null) {
                setState(() {
                  _selectedValidUntil = pickedDate;
                });
              }
            },
            decoration: InputDecoration(
              labelText: 'Дата окончания действия',
              hintText: _selectedValidUntil == null
                  ? 'Выберите дату'
                  : _selectedValidUntil!.toLocal().toString().split(' ')[0],
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
            if (_selectedBrandForUpload != null &&
                _selectedValidUntil != null) {
              Navigator.pop(ctx, {
                'brand': _selectedBrandForUpload!,
                'validUntil': _selectedValidUntil!
                    .toIso8601String()
                    .split('T')[0], // YYYY-MM-DD
              });
            }
          },
          child: const Text('Подтвердить'),
        ),
      ],
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
      validUntil: selectedData['validUntil']!,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Промокоды загружены и обработаны!'),
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

    final urlData = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                initialValue: _selectedBrandForUpload,
                items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT']
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedBrandForUpload = v),
                decoration: const InputDecoration(labelText: 'Бренд'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                readOnly: true,
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2030),
                  );
                  if (pickedDate != null) {
                    setState(() => _selectedValidUntil = pickedDate);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Дата окончания',
                  hintText: _selectedValidUntil == null
                      ? 'Выберите дату'
                      : _selectedValidUntil!.toLocal().toString().split(' ')[0],
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty &&
                  _selectedBrandForUpload != null &&
                  _selectedValidUntil != null) {
                Navigator.pop(ctx, {
                  'url': controller.text.trim(),
                  'brand': _selectedBrandForUpload!,
                  'validUntil': _selectedValidUntil!.toIso8601String().split('T')[0],
                });
              }
            },
            child: const Text('Загрузить'),
          ),
        ],
      ),
    );

    if (urlData == null) return;

    setState(() => _isLoading = true);
    try {
      await _service.uploadPromoFromGoogleSheet(
        urlData['url']!,
        brand: urlData['brand']!,
        validUntil: urlData['validUntil']!,
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
            SnackBar(content: Text('Ошибка: ${e.message}'), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildSectionHeader('Текущее состояние', Icons.dashboard_customize_outlined),
                  _buildActiveBrandCard(isDarkMode),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('Активация ограничений', Icons.bolt_outlined),
                  _buildActivationForm(isDarkMode),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('Пополнение базы', Icons.cloud_upload_outlined),
                  _buildUploadActions(isDarkMode),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('Статистика остатков', Icons.analytics_outlined),
                  if (_stats == null)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  else
                    _buildDetailedStats(isDarkMode),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader('История выдачи', Icons.history_edu_outlined),
                  _buildClaimedPromosSection(isDarkMode),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.green),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActiveBrandCard(bool isDarkMode) {
    if (_activeBrand == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.green.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Все бренды доступны', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('Ограничения по брендам сейчас не установлены', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
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
                decoration: BoxDecoration(color: brandColor.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(_getBrandIcon(brand), color: brandColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Активен только $brand', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    Text('Действует до ${_activeBrand!['expires_at']}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _clearActiveBrand,
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
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
        border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedBrand,
            items: ['JET', 'YANDEX', 'WHOOSH', 'BOLT'].map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
            onChanged: (v) => setState(() => _selectedBrand = v),
            decoration: InputDecoration(
              labelText: 'Выберите бренд',
              prefixIcon: const Icon(Icons.branding_watermark_outlined),
              filled: true,
              fillColor: isDarkMode ? Colors.black.withOpacity(0.2) : Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            readOnly: true,
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime(2030),
              );
              if (pickedDate != null) setState(() => _endDate = pickedDate);
            },
            decoration: InputDecoration(
              labelText: 'Дата окончания',
              hintText: _endDate == null ? 'Выберите дату' : DateFormat('dd.MM.yyyy').format(_endDate!),
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              filled: true,
              fillColor: isDarkMode ? Colors.black.withOpacity(0.2) : Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedBrand != null && _endDate != null ? _activateBrand : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Установить ограничение', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  Icon(Icons.description_outlined, color: Colors.green, size: 32),
                  SizedBox(height: 12),
                  Text('Excel / CSV', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
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
                  Text('Google Sheets', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClaimedPromosSection(bool isDarkMode) {
    if (_claimedPromos == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
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
    final summary = summaryRaw is Map ? Map<String, int>.from(summaryRaw) : {'JET': 0, 'YANDEX': 0, 'WHOOSH': 0, 'BOLT': 0};
    
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStatRow('JET', summary['JET'] ?? 0, 'GT9-XXXXXX', isDarkMode),
                const Divider(height: 24),
                _buildStatRow('YANDEX', summary['YANDEX'] ?? 0, 'ocf/ocm + цифры', isDarkMode),
                const Divider(height: 24),
                _buildStatRow('WHOOSH', summary['WHOOSH'] ?? 0, 'WSH_XXXXXX', isDarkMode),
                const Divider(height: 24),
                _buildStatRow('BOLT', summary['BOLT'] ?? 0, 'BOLTXXXXXX', isDarkMode),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String brand, int count, String format, bool isDarkMode) {
    final color = _getBrandColor(brand);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(_getBrandIcon(brand), color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(brand, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              Text(format, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: count > 0 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count', 
            style: TextStyle(
              color: count > 0 ? Colors.green : Colors.red, 
              fontWeight: FontWeight.bold, 
              fontSize: 14
            )),
        ),
      ],
    );
  }

  // --- НОВЫЙ МЕТОД: ГРУППИРОВКА ПО ДАТАМ С ПОИСКОМ ---
  Widget _buildClaimedPromosListByDate() {
    final filteredUsers = <Map<String, dynamic>>[];
    final promos = _claimedPromos ?? [];
    for (final item in promos) {
      if (item is Map<String, dynamic> && item['promo_codes'] != null && (item['promo_codes'] as Map).isNotEmpty) {
        final username = (item['username'] as String?)?.toLowerCase() ?? '';
        final firstName = (item['first_name'] as String?)?.toLowerCase() ?? '';
        if (_searchQuery.isEmpty || username.contains(_searchQuery) || firstName.contains(_searchQuery)) {
          filteredUsers.add(item);
        }
      }
    }

    if (filteredUsers.isEmpty && _searchQuery.isNotEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Ничего не найдено', style: TextStyle(color: Colors.grey))));
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

    final sortedDates = groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        for (final dateKey in sortedDates) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Text(DateFormat('dd MMMM yyyy', 'ru_RU').format(DateTime.parse(dateKey)), 
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.grey, letterSpacing: 0.5)),
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
        border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text('${user['username'] ?? 'User'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (user['first_name'] != null) Text(' • ${user['first_name']}', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in (user['promo_codes'] as Map<String, dynamic>).entries)
            if (entry.value is List && (entry.value as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_getBrandIcon(entry.key), size: 14, color: _getBrandColor(entry.key)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${(entry.value as List).join(", ")}',
                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
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
      case 'JET': return Colors.yellow[700]!;
      case 'YANDEX': return const Color(0xFFFFCC00);
      case 'WHOOSH': return Colors.orange;
      case 'BOLT': return Colors.green;
      default: return Colors.blue;
    }
  }

  IconData _getBrandIcon(String brand) {
    switch (brand.toUpperCase()) {
      case 'JET': return Icons.electric_scooter;
      case 'YANDEX': return Icons.map;
      case 'WHOOSH': return Icons.directions_bike;
      case 'BOLT': return Icons.bolt;
      default: return Icons.help_outline;
    }
  }
}
