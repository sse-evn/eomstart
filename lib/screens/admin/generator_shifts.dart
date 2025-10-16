import 'dart:convert';
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

  DateTime _startDate = DateTime.now();
  bool _isWeekly = false; // false = день, true = неделя

  int _morningCount = 1;
  int _eveningCount = 1;

  List<dynamic> _availableScouts = [];
  List<Map<String, dynamic>> _scoutStats = []; // {id, name, shiftCount}

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
          .map((user) {
        final firstName = user['first_name'] as String?;
        final username = user['username'] as String?;
        return {
          'id': user['id'],
          'name': firstName ?? username ?? 'Без имени',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _availableScouts = scouts;
          _scoutStats = scouts
              .map((s) => {
                    'id': s['id'],
                    'name': s['name'],
                    'shiftCount': 0,
                  })
              .toList();
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
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _startDate) {
      setState(() => _startDate = picked);
    }
  }

  void _updateMorningCount(String value) {
    setState(() => _morningCount = int.tryParse(value) ?? 0);
  }

  void _updateEveningCount(String value) {
    setState(() => _eveningCount = int.tryParse(value) ?? 0);
  }

  // Получить занятые смены за период
  Future<Set<String>> _getBusyShifts(
      String token, DateTime start, int days) async {
    final Set<String> busy = {};
    for (int i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      final formattedDate =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      try {
        final shifts = await _apiService.getShiftsByDate(token, formattedDate);
        for (var shift in shifts) {
          final scoutId = shift['user_id']?.toString();
          final shiftType = shift['shift_type'];
          if (scoutId != null && shiftType != null) {
            busy.add('$scoutId-$formattedDate-$shiftType');
          }
        }
      } catch (e) {
        debugPrint('Не удалось загрузить смены за $formattedDate: $e');
      }
    }
    return busy;
  }

  // Распределить смены с учётом занятости и равномерности
  List<int> _assignShifts(List<int> scoutIds, int needed, Set<String> busy,
      DateTime date, String shiftType) {
    final List<int> assigned = [];
    final List<Map<String, dynamic>> candidates = [];

    final dateString =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    for (int id in scoutIds) {
      final key = '$id-$dateString-$shiftType';
      if (!busy.contains(key)) {
        final scout = _scoutStats.firstWhere((s) => s['id'] == id,
            orElse: () => {'shiftCount': 0});
        candidates.add({'id': id, 'shiftCount': scout['shiftCount'] ?? 0});
      }
    }

    candidates.sort(
        (a, b) => (a['shiftCount'] as int).compareTo(b['shiftCount'] as int));

    for (var candidate in candidates.take(needed)) {
      assigned.add(candidate['id'] as int);
      final stat = _scoutStats.firstWhere((s) => s['id'] == candidate['id']);
      stat['shiftCount'] = (stat['shiftCount'] as int) + 1;
    }

    return assigned;
  }

  Future<void> _generateShifts() async {
    final totalDailyShifts = _morningCount + _eveningCount;
    if (totalDailyShifts == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Укажите количество смен'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (_availableScouts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет скаутов для назначения'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      setState(() => _isGenerating = true);

      final int days = _isWeekly ? 7 : 1;
      final Set<String> busyShifts =
          await _getBusyShifts(token, _startDate, days);

      for (int i = 0; i < days; i++) {
        final currentDate = _startDate.add(Duration(days: i));
        final dateString =
            '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';

        final List<int> scoutIds =
            _availableScouts.map((s) => s['id'] as int).toList();

        final List<int> morningAssigned = _assignShifts(
          scoutIds,
          _morningCount,
          busyShifts,
          currentDate,
          'morning',
        );

        final List<int> eveningAssigned = _assignShifts(
          scoutIds,
          _eveningCount,
          busyShifts,
          currentDate,
          'evening',
        );

        final List<int> allAssigned = [...morningAssigned, ...eveningAssigned];
        if (allAssigned.isEmpty) continue;

        await _apiService.generateShifts(
          token: token,
          date: currentDate,
          morningCount: _morningCount,
          eveningCount: _eveningCount,
          selectedScoutIds: allAssigned,
        );

        for (var id in morningAssigned) {
          busyShifts.add('$id-$dateString-morning');
        }
        for (var id in eveningAssigned) {
          busyShifts.add('$id-$dateString-evening');
        }
      }

      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Смены сгенерированы на ${_isWeekly ? "неделю" : "день"}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Stack(
      children: [
        // Основной контент
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // === Режим: день / неделя ===
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Режим:',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                              ToggleButtons(
                                borderRadius: BorderRadius.circular(8),
                                isSelected: [
                                  !_isWeekly,
                                  _isWeekly,
                                ],
                                onPressed: (int index) {
                                  setState(() {
                                    _isWeekly = (index == 1);
                                  });
                                },
                                children: const [
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
                                    child: Text('День'),
                                  ),
                                  Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
                                    child: Text('Неделя'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // === Дата ===
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          onTap: () => _selectDate(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Дата начала',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  _isWeekly
                                      ? '${_startDate.day.toString().padLeft(2, '0')}.${_startDate.month.toString().padLeft(2, '0')} - '
                                          '${_startDate.add(const Duration(days: 6)).day.toString().padLeft(2, '0')}.${_startDate.month.toString().padLeft(2, '0')}'
                                      : '${_startDate.day.toString().padLeft(2, '0')}.${_startDate.month.toString().padLeft(2, '0')}.${_startDate.year}',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // === Утренние смены ===
                      _buildShiftField('Утренние смены', '(07:00–15:00)',
                          _morningCount, _updateMorningCount),
                      const SizedBox(height: 16),

                      // === Вечерние смены ===
                      _buildShiftField('Вечерние смены', '(15:00–23:00)',
                          _eveningCount, _updateEveningCount),
                      const SizedBox(height: 24),

                      // === Информация ===
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Статистика',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Смены в день:'),
                                    Text('${_morningCount + _eveningCount}'),
                                  ]),
                              const SizedBox(height: 8),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Период:'),
                                    Text(_isWeekly ? '7 дней' : '1 день'),
                                  ]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
        ),

        // === FAB: кнопка генерации справа снизу ===
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: _isGenerating ? null : _generateShifts,
            tooltip: 'Сгенерировать смены',
            child: _isGenerating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white)),
                  )
                : const Icon(Icons.play_circle_filled),
          ),
        ),
      ],
    );
  }
  
  Widget _buildShiftField(String title, String subtitle, int count,
      void Function(String) onChanged) {
    return Card(
      color: Theme.of(context).colorScheme.secondary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            ),
            Container(
              width: 80,
              decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade700 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8)),
              child: TextFormField(
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: false),
                initialValue: count.toString(),
                onChanged: onChanged,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
