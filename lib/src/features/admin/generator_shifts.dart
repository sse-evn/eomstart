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
  int _fullCount = 0;

  List<Map<String, dynamic>> _availableScouts = [];
  Set<String> _busyShifts = {};
  List<Map<String, dynamic>> _previewResult = [];

  bool _isLoading = false;
  bool _isCalculating = false;
  bool _isSaving = false;

  final TextEditingController _morningController = TextEditingController(text: '1');
  final TextEditingController _eveningController = TextEditingController(text: '1');
  final TextEditingController _fullController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _loadScoutsAndBusyShifts();
  }

  @override
  void dispose() {
    _morningController.dispose();
    _eveningController.dispose();
    _fullController.dispose();
    super.dispose();
  }

  Future<void> _loadScoutsAndBusyShifts() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

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
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
    }
  }

  Future<Set<String>> _getBusyShifts(String token, DateTime start, int days) async {
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
           // Если есть любая смена, считаем день занятым для этого типа
           busy.add('$id-$dateStr-any');
        }
      } catch (e) {
        debugPrint('Ошибка загрузки смен за $dateStr: $e');
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

  void _toggleWeekly() {
    setState(() => _isWeekly = !_isWeekly);
    _loadScoutsAndBusyShifts();
  }

  List<int> _simulateAssignment(List<int> scoutIds, int needed, DateTime date,
      String shiftType, Set<String> currentBusy) {
    if (needed <= 0) return [];
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final candidates = <int>[];
    for (int id in scoutIds) {
      final key = '$id-$dateStr-$shiftType';
      final anyKey = '$id-$dateStr-any';
      if (!currentBusy.contains(key) && !currentBusy.contains(anyKey)) {
        candidates.add(id);
      }
    }
    return candidates.take(needed).toList();
  }

  Future<void> _calculatePreview() async {
    if (_morningCount + _eveningCount + _fullCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите количество смен')));
      return;
    }
    if (_availableScouts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Нет доступных скаутов')));
      return;
    }

    setState(() => _isCalculating = true);

    final days = _isWeekly ? 7 : 1;
    final scoutIds = _availableScouts.map((s) => s['id'] as int).toList();
    final result = <Map<String, dynamic>>[];
    final workingBusy = Set<String>.from(_busyShifts);

    for (int i = 0; i < days; i++) {
      final date = _startDate.add(Duration(days: i));
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      // Сначала распределяем полные смены
      final full = _simulateAssignment(scoutIds, _fullCount, date, 'full', workingBusy);
      for (var id in full) workingBusy.add('$id-$dateStr-any');

      // Затем утренние
      final morning = _simulateAssignment(scoutIds, _morningCount, date, 'morning', workingBusy);
       for (var id in morning) workingBusy.add('$id-$dateStr-any');

      // Затем вечерние
      final evening = _simulateAssignment(scoutIds, _eveningCount, date, 'evening', workingBusy);
      for (var id in evening) workingBusy.add('$id-$dateStr-any');

      result.add({
        'date': date,
        'full': full,
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

  Future<void> _saveShifts() async {
    if (_previewResult.isEmpty) return;

    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

    setState(() => _isSaving = true);

    try {
      int successCount = 0;
      for (final day in _previewResult) {
        final date = day['date'] as DateTime;
        final morning = List<int>.from(day['morning']);
        final evening = List<int>.from(day['evening']);
        final full = List<int>.from(day['full']);

        // Собираем всех выбранных скаутов для этого дня (хотя бэкэнд может ожидать другую структуру, 
        // но ApiService.generateShifts принимает morningCount, eveningCount и список IDs)
        // В текущей реализации бэкенда GenerateShiftsRequest имеет MorningCount, EveningCount, FullCount и ScoutIDs.
        // Он распределяет их последовательно.
        
        final List<int> allIds = [...full, ...morning, ...evening];
        if (allIds.isEmpty) continue;

        await _apiService.generateShifts(
          token: token,
          date: date,
          morningCount: morning.length,
          eveningCount: evening.length,
          fullCount: full.length,
          selectedScoutIds: allIds,
        );
        successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Успешно сохранено смен за $successCount дн.'), backgroundColor: Colors.green));
        setState(() => _isSaving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red));
      }
    }
  }

  String _getHandle(int id) {
    for (final scout in _availableScouts) {
      if (scout['id'] == id) {
        final firstName = scout['first_name'] as String?;
        final username = scout['username'] as String?;
        if (firstName != null && firstName.isNotEmpty) return firstName;
        if (username != null && username.isNotEmpty) return '@$username';
        return 'ID $id';
      }
    }
    return 'ID $id';
  }

  String _formatScheduleForTelegram() {
    if (_previewResult.isEmpty) return 'Нет данных.';
    final buffer = StringBuffer();
    buffer.writeln('📅 *Расписание с ${_startDate.day}.${_startDate.month}*:');
    buffer.writeln();
    for (final day in _previewResult) {
      final date = day['date'] as DateTime;
      final full = List<int>.from(day['full']);
      final morning = List<int>.from(day['morning']);
      final evening = List<int>.from(day['evening']);
      
      buffer.writeln('--------------------------');
      buffer.writeln('📅 *${date.day}.${date.month}.${date.year}*');
      if (full.isNotEmpty) {
        buffer.writeln('🌕 07:00-23:00: ${full.map((id) => _getHandle(id)).join(', ')}');
      }
      if (morning.isNotEmpty) {
        buffer.writeln('🌅 07:00-15:00: ${morning.map((id) => _getHandle(id)).join(', ')}');
      }
      if (evening.isNotEmpty) {
        buffer.writeln('🌆 15:00-23:00: ${evening.map((id) => _getHandle(id)).join(', ')}');
      }
    }
    buffer.writeln('--------------------------');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Параметры генерации'),
                const SizedBox(height: 12),
                _buildSettingsCard(primaryColor),
                const SizedBox(height: 24),
                _buildSectionTitle('Количество сотрудников в смену'),
                const SizedBox(height: 12),
                _buildShiftCountsCard(),
                const SizedBox(height: 32),
                _buildActionButtons(primaryColor),
                const SizedBox(height: 32),
                if (_previewResult.isNotEmpty) ...[
                  _buildSectionTitle('Предварительный просмотр'),
                  const SizedBox(height: 16),
                  ..._previewResult.map((day) => _buildDayPreviewCard(day)),
                  const SizedBox(height: 24),
                  _buildExportButtons(),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildSettingsCard(Color primaryColor) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined, color: Colors.blue),
            title: const Text('Период планирования', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text(_isWeekly ? 'Неделя' : 'Один день', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
            onTap: _toggleWeekly,
          ),
          const Divider(height: 1, indent: 55),
          ListTile(
            leading: const Icon(Icons.event_outlined, color: Colors.orange),
            title: const Text('Дата начала', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${_startDate.day}.${_startDate.month}.${_startDate.year}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _selectDate,
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCountsCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _buildCountRow(
            'Утро (07:00–15:00)', 
            _morningController, 
            (v) => setState(() => _morningCount = int.tryParse(v) ?? 0),
            _morningCount,
            (v) => setState(() {
              _morningCount = v;
              _morningController.text = v.toString();
            })
          ),
          const SizedBox(height: 16),
          _buildCountRow(
            'Вечер (15:00–23:00)', 
            _eveningController, 
            (v) => setState(() => _eveningCount = int.tryParse(v) ?? 0),
            _eveningCount,
            (v) => setState(() {
              _eveningCount = v;
              _eveningController.text = v.toString();
            })
          ),
          const SizedBox(height: 16),
          _buildCountRow(
            'Полная (07:00–23:00)', 
            _fullController, 
            (v) => setState(() => _fullCount = int.tryParse(v) ?? 0),
            _fullCount,
            (v) => setState(() {
              _fullCount = v;
              _fullController.text = v.toString();
            })
          ),
        ],
      ),
    );
  }

  Widget _buildCountRow(String label, TextEditingController controller, Function(String) onChanged, int currentVal, Function(int) onSet) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: currentVal > 0 ? () => onSet(currentVal - 1) : null,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              onPressed: () => onSet(currentVal + 1),
              icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(Color primaryColor) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isCalculating ? null : _calculatePreview,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isCalculating 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Распределить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ),
        if (_previewResult.isNotEmpty) ...[
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveShifts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSaving 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Сохранить всё', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDayPreviewCard(Map<String, dynamic> day) {
    final theme = Theme.of(context);
    final date = day['date'] as DateTime;
    final full = List<int>.from(day['full']);
    final morning = List<int>.from(day['morning']);
    final evening = List<int>.from(day['evening']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${date.day}.${date.month}.${date.year}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('${full.length + morning.length + evening.length} чел.', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (full.isNotEmpty) _buildShiftSummaryRow(Icons.wb_sunny, '07:00–23:00', full, Colors.orange),
          if (morning.isNotEmpty) _buildShiftSummaryRow(Icons.wb_sunny_outlined, '07:00–15:00', morning, Colors.blue),
          if (evening.isNotEmpty) _buildShiftSummaryRow(Icons.wb_twilight, '15:00–23:00', evening, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildShiftSummaryRow(IconData icon, String time, List<int> ids, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(ids.map((id) => _getHandle(id)).join(', '), style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
        ],
      ),
    );
  }

  Widget _buildExportButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _formatScheduleForTelegram()));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Текст скопирован')));
            },
            icon: const Icon(Icons.copy, size: 20),
            label: const Text('Копировать текст'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              final text = Uri.encodeComponent(_formatScheduleForTelegram());
              final uri = Uri.parse('https://t.me/share/url?url=&text=$text');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
            icon: const Icon(Icons.send, size: 20, color: Colors.white),
            label: const Text('В Telegram', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF24A1DE),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
