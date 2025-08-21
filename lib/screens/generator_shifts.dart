// lib/screens/generatorshift.dart
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GeneratorShiftScreen extends StatefulWidget {
  const GeneratorShiftScreen({super.key});

  @override
  State<GeneratorShiftScreen> createState() => _GeneratorShiftScreenState();
}

class _GeneratorShiftScreenState extends State<GeneratorShiftScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  DateTime _date = DateTime.now();
  int _morningCount = 0;
  int _eveningCount = 0;
  List<ActiveShift> _availableScouts = [];
  List<int> _selectedScoutIds = [];

  @override
  void initState() {
    super.initState();
    _loadScouts();
  }

  Future<void> _loadScouts() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final scouts = await _apiService.getAdminUsers(token);
      setState(() {
        _availableScouts = scouts
            .map((u) => ActiveShift(
                  id: u['id'],
                  userId: u['id'],
                  username: u['username'],
                  slotTimeRange: '',
                  position: u['position'] ?? '',
                  zone: '',
                  selfie: '',
                  isActive: false,
                ))
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка загрузки скаутов: $e')));
    }
  }

  Future<void> _generateShifts() async {
    if (_morningCount + _eveningCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите количество смен')),
      );
      return;
    }

    final selected = _selectedScoutIds.length;
    if (selected < _morningCount + _eveningCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите достаточно скаутов')),
      );
      return;
    }

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.generateShifts(
        token: token,
        date: _date,
        morningCount: _morningCount,
        eveningCount: _eveningCount,
        selectedScoutIds: _selectedScoutIds,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Смены успешно сгенерированы!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Генератор смен'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // === Дата ===
            ListTile(
              title: const Text('Дата смен'),
              subtitle: Text('${_date.day}.${_date.month}.${_date.year}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (picked != null) {
                  setState(() {
                    _date = picked;
                  });
                }
              },
            ),
            const Divider(),

            // === Утренние смены ===
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Утренние смены (07:00–15:00)'),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: _morningCount.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _morningCount = int.tryParse(value) ?? 0;
                      });
                    },
                    decoration: const InputDecoration(hintText: '0'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // === Вечерние смены ===
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Вечерние смены (15:00–23:00)'),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: _eveningCount.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _eveningCount = int.tryParse(value) ?? 0;
                      });
                    },
                    decoration: const InputDecoration(hintText: '0'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // === Выбор скаутов ===
            const Text('Выберите скаутов:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _availableScouts.map((scout) {
                return FilterChip(
                  label: Text(scout.username),
                  selected: _selectedScoutIds.contains(scout.userId),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedScoutIds.add(scout.userId);
                      } else {
                        _selectedScoutIds.remove(scout.userId);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 32),

            // === Кнопка генерации ===
            ElevatedButton(
              onPressed: _generateShifts,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Сгенерировать смены',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
