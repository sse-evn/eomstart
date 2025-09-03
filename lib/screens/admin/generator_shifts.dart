import 'package:flutter/material.dart';
import 'package:micro_mobility_app/services/api_service.dart';
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

  List<dynamic> _availableScouts = [];
  List<int> _selectedScoutIds = [];

  bool _isLoading = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadScouts();
  }

  Future<void> _loadScouts() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ошибка: Токен не найден')),
          );
        }
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final scoutsData = await _apiService.getAdminUsers(token);

      final scouts = scoutsData
          .where(
              (user) => user is Map<String, dynamic> && user['role'] == 'scout')
          .toList();

      if (mounted) {
        setState(() {
          _availableScouts = scouts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки скаутов: $e')),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _date) {
      setState(() => _date = picked);
    }
  }

  void _updateMorningCount(String value) {
    setState(() => _morningCount = int.tryParse(value) ?? 0);
  }

  void _updateEveningCount(String value) {
    setState(() => _eveningCount = int.tryParse(value) ?? 0);
  }

  Future<void> _generateShifts() async {
    final totalShifts = _morningCount + _eveningCount;

    if (totalShifts == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Укажите количество утренних или вечерних смен'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (_selectedScoutIds.length < totalShifts) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Выберите как минимум $totalShifts скаутов. Сейчас выбрано: ${_selectedScoutIds.length}',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ошибка: Токен не найден')),
          );
        }
        return;
      }

      setState(() => _isGenerating = true);

      await _apiService.generateShifts(
        token: token,
        date: _date,
        morningCount: _morningCount,
        eveningCount: _eveningCount,
        selectedScoutIds: _selectedScoutIds,
      );

      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Смены успешно сгенерированы!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка генерации смен: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalShifts = _morningCount + _eveningCount;
    final remainingScouts = totalShifts - _selectedScoutIds.length;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === Дата ===
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () => _selectDate(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Дата смен',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // === Утренние смены ===
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Утренние смены',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '(07:00–15:00)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextFormField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: false),
                                initialValue: _morningCount.toString(),
                                onChanged: _updateMorningCount,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // === Вечерние смены ===
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Вечерние смены',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '(15:00–23:00)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextFormField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: false),
                                initialValue: _eveningCount.toString(),
                                onChanged: _updateEveningCount,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // === Информация о выбранных сменах ===
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Информация',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Всего смен:'),
                                Text(
                                  '$totalShifts',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Выбрано скаутов:'),
                                Text(
                                  '${_selectedScoutIds.length}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            if (remainingScouts > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Нужно выбрать еще:'),
                                  Text(
                                    '$remainingScouts',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (totalShifts > 0) ...[
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Готово к генерации:'),
                                  Icon(Icons.check_circle, color: Colors.green),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // === Выбор скаутов ===
                    const Text(
                      'Выберите скаутов:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_availableScouts.isEmpty)
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Нет доступных скаутов для выбора.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableScouts.map((scout) {
                            if (scout is! Map<String, dynamic>)
                              return const SizedBox.shrink();

                            final userId = scout['id'] as int?;
                            final username =
                                scout['username'] as String? ?? 'Без имени';
                            final firstName = scout['first_name'] as String?;
                            final displayName = firstName ?? username;

                            if (userId == null) return const SizedBox.shrink();

                            return ChoiceChip(
                              label: Text(displayName),
                              selected: _selectedScoutIds.contains(userId),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedScoutIds.add(userId);
                                  } else {
                                    _selectedScoutIds.remove(userId);
                                  }
                                });
                              },
                              selectedColor: Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.3),
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _selectedScoutIds.contains(userId)
                                    ? Theme.of(context).primaryColor
                                    : Colors.black87,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: _selectedScoutIds.contains(userId)
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade300,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 32),

                    // === Кнопка генерации ===
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isGenerating ? null : _generateShifts,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isGenerating
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Генерация...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'Сгенерировать смены',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
