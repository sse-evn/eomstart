// lib/screens/admin/admin_promo_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/services/promo_api_service.dart';

class AdminPromoScreen extends StatefulWidget {
  const AdminPromoScreen({super.key});

  @override
  State<AdminPromoScreen> createState() => _AdminPromoScreenState();
}

class _AdminPromoScreenState extends State<AdminPromoScreen> {
  final PromoApiService _service = PromoApiService();
  List<Map<String, dynamic>> _promoCodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPromoCodes();
  }

  Future<void> _loadPromoCodes() async {
    try {
      final rawList = await _service.getAdminPromoCodes();
      final List<Map<String, dynamic>> promos = rawList
          .where((e) => e is Map<String, dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      if (mounted) {
        setState(() {
          _promoCodes = promos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreatePromoDialog() async {
    final idController = TextEditingController();
    final dateController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final titleController = TextEditingController();
    final descController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Создать промокод'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: idController,
                  decoration: const InputDecoration(labelText: 'ID промокода')),
              TextField(
                  controller: dateController,
                  decoration:
                      const InputDecoration(labelText: 'Дата (ГГГГ-ММ-ДД)')),
              TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Заголовок')),
              TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                      labelText: 'Описание (опционально)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: Navigator.of(ctx).pop, child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final id = idController.text.trim();
              final date = dateController.text.trim();
              final title = titleController.text.trim();
              if (id.isEmpty || date.isEmpty || title.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Все поля обязательны'),
                      backgroundColor: Colors.orange),
                );
                return;
              }

              Navigator.of(ctx).pop();

              try {
                await _service.createPromoCode(
                  id: id,
                  date: date,
                  title: title,
                  description: descController.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Промокод создан!'),
                        backgroundColor: Colors.green),
                  );
                  _loadPromoCodes();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Ошибка: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignDialog(String promoId) async {
    final userIdController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Назначить промокод'),
        content: TextField(
          controller: userIdController,
          decoration: const InputDecoration(labelText: 'ID пользователя'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
              onPressed: Navigator.of(ctx).pop, child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final userIdStr = userIdController.text.trim();
              if (userIdStr.isEmpty) return;

              final userId = int.tryParse(userIdStr);
              if (userId == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Некорректный ID пользователя'),
                      backgroundColor: Colors.orange),
                );
                return;
              }

              Navigator.of(ctx).pop();

              try {
                await _service.assignPromoToUser(promoId, userId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Промокод назначен!'),
                        backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Ошибка: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Назначить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление промокодами'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreatePromoDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _promoCodes.isEmpty
              ? const Center(child: Text('Нет промокодов'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _promoCodes.length,
                  itemBuilder: (context, index) {
                    final promo = _promoCodes[index];
                    final id = promo['id']?.toString() ?? '';
                    final dateStr = promo['date']?.toString() ?? '';
                    final title = promo['title']?.toString() ?? '';
                    final description = promo['description']?.toString() ?? '';

                    final date = DateTime.tryParse(dateStr);
                    final displayDate = date != null
                        ? DateFormat('EEEE, dd MMMM yyyy', 'ru_RU').format(date)
                        : dateStr;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ID: $id',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(displayDate,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(title, style: const TextStyle(fontSize: 16)),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(description,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 14)),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: () => _showAssignDialog(id),
                                child: const Text('Назначить пользователю'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
