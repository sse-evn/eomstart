import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SlotManagementTab extends StatefulWidget {
  const SlotManagementTab({super.key});

  @override
  State<SlotManagementTab> createState() => _SlotManagementTabState();
}

class _SlotManagementTabState extends State<SlotManagementTab> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  List<Map<String, dynamic>> _slots = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSlots();
  }

  Future<void> _fetchSlots() async {
    setState(() => _isLoading = true);
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

    try {
      final response = await _apiService.getAdminSlots(token);
      if (mounted) {
        setState(() {
          _slots = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки слотов: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleSlot(int id, bool isActive) async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

    try {
      await _apiService.toggleAdminSlot(token, id, isActive);
      _fetchSlots();
    } catch (e) {
      debugPrint('Ошибка переключения слота: $e');
    }
  }

  Future<void> _deleteSlot(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление слота'),
        content: const Text('Вы уверены, что хотите удалить этот слот?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Удалить', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

    try {
      await _apiService.deleteAdminSlot(token, id);
      _fetchSlots();
    } catch (e) {
      debugPrint('Ошибка удаления слота: $e');
    }
  }

  void _showAddSlotDialog() {
    final TextEditingController startController = TextEditingController();
    final TextEditingController endController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Новый слот (ЧЧ:ММ)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: startController,
                decoration: const InputDecoration(labelText: 'Начало (например, 07:00)', hintText: '07:00'),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: endController,
                decoration: const InputDecoration(labelText: 'Конец (например, 15:00)', hintText: '15:00'),
                keyboardType: TextInputType.datetime,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final start = startController.text.trim();
                final end = endController.text.trim();
                if (start.isEmpty || end.isEmpty) return;

                final range = '$start-$end';
                final token = await _storage.read(key: 'jwt_token');
                if (token == null) return;

                try {
                  await _apiService.createAdminSlot(token, range);
                  Navigator.pop(ctx);
                  _fetchSlots();
                } catch (e) {
                  debugPrint('Ошибка создания слота: $e');
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSlotDialog,
        backgroundColor: Colors.green,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 80), // bottom padding for FAB
            itemCount: _slots.length,
            itemBuilder: (context, index) {
              final slot = _slots[index];
              final id = slot['id'] as int;
              final range = slot['slot_time_range'] as String;
              final isActive = slot['is_active'] as bool;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Theme.of(context).cardColor.withOpacity(0.9),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    child: Icon(Icons.access_time, color: isActive ? Colors.green : Colors.grey),
                  ),
                  title: Text(range, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text(isActive ? 'Слот активен' : 'Слот выключен', style: TextStyle(color: isActive ? Colors.green : Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isActive,
                        activeColor: Colors.green,
                        onChanged: (val) => _toggleSlot(id, val),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteSlot(id),
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
