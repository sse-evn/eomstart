import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class GeneratorShiftScreen extends StatefulWidget {
  const GeneratorShiftScreen({super.key});

  @override
  State<GeneratorShiftScreen> createState() => _GeneratorShiftScreenState();
}

class _GeneratorShiftScreenState extends State<GeneratorShiftScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  DateTime _startDate = DateTime.now();
  bool _isWeekly = false;

  int _morningCount = 1;
  int _eveningCount = 1;

  List<Map<String, dynamic>> _availableScouts = [];
  Set<String> _busyShifts = {};
  List<Map<String, dynamic>> _previewResult = [];

  bool _isLoading = false;
  bool _isCalculating = false;

  @override
  void initState() {
    super.initState();
    _loadScoutsAndBusyShifts();
  }

  Future<void> _loadScoutsAndBusyShifts() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Токен не найден')));
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final scoutsData = await _apiService.getAdminUsers(token);
      final scouts = scoutsData
          .where((u) => u is Map && u['role'] == 'scout')
          .map((u) => {
                'id': u['id'] as int,
                'first_name': u['first_name'] as String?,
                'username': u['username'] as String?,
              })
          .toList();

      final days = _isWeekly ? 7 : 1;
      final busy = await _getBusyShifts(token, _startDate, days);

      if (mounted) {
        setState(() {
          _availableScouts = scouts;
          _busyShifts = busy;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<Set<String>> _getBusyShifts(
      String token, DateTime start, int days) async {
    final Set<String> busy = {};
    for (int i = 0; i < days; i++) {
      final date = start.add(Duration(days: i));
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      try {
        final shifts = await _apiService.getShiftsByDate(token, dateStr);
        for (var s in shifts) {
          final id = s['user_id']?.toString();
          final type = s['shift_type']?.toString();
          if (id != null && type != null) {
            busy.add('$id-$dateStr-$type');
          }
        }
      } catch (e) {
        debugPrint('Не удалось загрузить смены за $dateStr: $e');
      }
    }
    return busy;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _startDate) {
      setState(() => _startDate = picked);
      _loadScoutsAndBusyShifts();
    }
  }

  void _updateMorningCount(String v) =>
      setState(() => _morningCount = int.tryParse(v) ?? 0);
  void _updateEveningCount(String v) =>
      setState(() => _eveningCount = int.tryParse(v) ?? 0);
  void _toggleWeekly() {
    setState(() => _isWeekly = !_isWeekly);
    _loadScoutsAndBusyShifts();
  }

  List<int> _simulateAssignment(List<int> scoutIds, int needed, DateTime date,
      String shiftType, Set<String> currentBusy) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final candidates = <int>[];
    for (int id in scoutIds) {
      final key = '$id-$dateStr-$shiftType';
      if (!currentBusy.contains(key)) {
        candidates.add(id);
      }
    }
    return candidates.take(needed).toList();
  }

  Future<void> _calculatePreview() async {
    if (_morningCount + _eveningCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите количество смен')));
      return;
    }
    if (_availableScouts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет скаутов')));
      return;
    }

    setState(() => _isCalculating = true);

    final days = _isWeekly ? 7 : 1;
    final scoutIds = _availableScouts.map((s) => s['id'] as int).toList();
    final result = <Map<String, dynamic>>[];
    final workingBusy = Set<String>.from(_busyShifts);

    for (int i = 0; i < days; i++) {
      final date = _startDate.add(Duration(days: i));
      final morning = _simulateAssignment(
          scoutIds, _morningCount, date, 'morning', workingBusy);
      final evening = _simulateAssignment(
          scoutIds, _eveningCount, date, 'evening', workingBusy);
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      for (var id in morning) workingBusy.add('$id-$dateStr-morning');
      for (var id in evening) workingBusy.add('$id-$dateStr-evening');
      result.add({
        'date': date,
        'morning': morning,
        'evening': evening,
      });
    }

    if (mounted) {
      setState(() {
        _previewResult = result;
        _isCalculating = false;
      });
    }
  }

  String _getTelegramHandle(int id) {
    for (final scout in _availableScouts) {
      if (scout['id'] == id) {
        final username = scout['username'] as String?;
        if (username != null && username.isNotEmpty) {
          return '@$username';
        }
        return 'user$id';
      }
    }
    return 'user$id';
  }

  String _formatScheduleForTelegram() {
    if (_previewResult.isEmpty) return 'Нет данных для экспорта.';
    final buffer = StringBuffer();
    final date = _startDate;
    buffer.writeln('📅 Расписание на ${date.day}.${date.month}.${date.year}г:');
    buffer.writeln();
    for (final day in _previewResult) {
      final morning = List<int>.from(day['morning']);
      final evening = List<int>.from(day['evening']);
      if (morning.isNotEmpty) {
        buffer.writeln('    07:00-15:00');
        for (int i = 0; i < morning.length; i++) {
          buffer.writeln(
              '${i + 1}. ${_getTelegramHandle(morning[i])} - ${morning[i]}');
        }
        buffer.writeln();
      }
      if (evening.isNotEmpty) {
        buffer.writeln('    15:00-23:00');
        for (int i = 0; i < evening.length; i++) {
          buffer.writeln(
              '${i + 1}. ${_getTelegramHandle(evening[i])} - ${evening[i]}');
        }
        buffer.writeln();
      }
    }
    final totalMorning = _previewResult.fold(
        0, (sum, day) => sum + (day['morning'] as List).length);
    final totalEvening = _previewResult.fold(
        0, (sum, day) => sum + (day['evening'] as List).length);
    buffer.writeln(
        '7-15: $totalMorning | 15-23: $totalEvening | Всего: ${totalMorning + totalEvening}');
    return buffer.toString();
  }

  Future<void> _copyToClipboard() async {
    final text = _formatScheduleForTelegram();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Скопировано в буфер обмена')));
    }
  }

  Future<void> _sendToTelegram() async {
    final text = Uri.encodeComponent(_formatScheduleForTelegram());
    final uri = Uri.parse('https://t.me/share/url?url=&text=$text');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть Telegram')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildToggleRow('День/Неделя', _isWeekly, _toggleWeekly),
              _buildDateRow(),
              _buildShiftInput(
                  'Утро (07:00–15:00)', _morningCount, _updateMorningCount),
              _buildShiftInput(
                  'Вечер (15:00–23:00)', _eveningCount, _updateEveningCount),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isCalculating ? null : _calculatePreview,
                  icon: _isCalculating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Icon(Icons.calculate),
                  label: const Text('Рассчитать расписание'),
                ),
              ),
              const SizedBox(height: 24),
              if (_previewResult.isNotEmpty) ...[
                const Text('Расписание',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ..._previewResult.map((day) {
                  final date = day['date'] as DateTime;
                  final morning = List<int>.from(day['morning']);
                  final evening = List<int>.from(day['evening']);
                  final morningNames =
                      morning.map((id) => _getTelegramHandle(id)).join(', ');
                  final eveningNames =
                      evening.map((id) => _getTelegramHandle(id)).join(', ');
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${date.day}.${date.month}.${date.year}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                              '🕗 Утро: ${morningNames.isEmpty ? '—' : morningNames}'),
                          Text(
                              '🕖 Вечер: ${eveningNames.isEmpty ? '—' : eveningNames}'),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: const Text('Копировать'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sendToTelegram,
                      icon: const Icon(Icons.send),
                      label: const Text('В Telegram'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleRow(String label, bool value, void Function() onChanged) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Switch(value: value, onChanged: (_) => onChanged()),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: const Text('Дата начала'),
        subtitle: Text(
          _isWeekly
              ? '${_startDate.day}.${_startDate.month} – ${_startDate.add(const Duration(days: 6)).day}.${_startDate.month}'
              : '${_startDate.day}.${_startDate.month}.${_startDate.year}',
        ),
        trailing: const Icon(Icons.calendar_today),
        onTap: _selectDate,
      ),
    );
  }

  Widget _buildShiftInput(
      String label, int count, void Function(String) onChanged) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            SizedBox(
              width: 70,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                controller: TextEditingController(text: count.toString()),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
