import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:micro_mobility_app/src/core/services/promo_api_service.dart';

class PromoListScreen extends StatefulWidget {
  const PromoListScreen({super.key});

  @override
  State<PromoListScreen> createState() => _PromoListScreenState();
}

class _PromoListScreenState extends State<PromoListScreen> {
  final PromoApiService _service = PromoApiService();
  List<dynamic> _codes = [];
  List<dynamic> _filteredCodes = [];
  bool _isLoading = true;
  String _selectedBrand = 'Все';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _service.getPromoCodesList();
      if (mounted) {
        setState(() {
          _codes = data;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredCodes = _codes.where((item) {
        final brand = item['brand'] ?? '';
        final code = (item['promo_code'] ?? '').toString().toLowerCase();

        final matchesBrand = _selectedBrand == 'Все' || brand == _selectedBrand;
        final matchesSearch =
            _searchQuery.isEmpty || code.contains(_searchQuery);

        return matchesBrand && matchesSearch;
      }).toList();
    });
  }

  Future<void> _deleteCode(int id, String codeStr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить промокод?'),
        content: Text('Промокод "$codeStr" будет удален из базы навсегда.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deletePromoCode(codeStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Удалено'), backgroundColor: Colors.green));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Фильтры
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск кода...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) {
                      _searchQuery = v.toLowerCase();
                      _applyFilters();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _selectedBrand,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    items: ['Все', 'JET', 'YANDEX', 'WHOOSH', 'BOLT']
                        .map((b) => DropdownMenuItem(
                            value: b,
                            child:
                                Text(b, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        _selectedBrand = v;
                        _applyFilters();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          if (!_isLoading)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Найдено: ${_filteredCodes.length}',
                    style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),

          // Список
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCodes.isEmpty
                    ? const Center(
                        child: Text('Ничего не найдено',
                            style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredCodes.length,
                          itemBuilder: (ctx, i) {
                            final item = _filteredCodes[i];
                            final isClaimed = item['is_claimed'] == true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                title: Row(
                                  children: [
                                    Text(item['brand'] ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isClaimed
                                            ? Colors.red.withOpacity(0.1)
                                            : Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isClaimed ? 'Выдан' : 'Свободен',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isClaimed
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      item['promo_code'] ?? '',
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Годен до: ${item['valid_until'] ?? '-'}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy,
                                          size: 20, color: Colors.grey),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(
                                            text: item['promo_code'] ?? ''));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text('Скопировано')));
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 20, color: Colors.red),
                                      onPressed: () => _deleteCode(
                                          item['id'], item['promo_code']),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
