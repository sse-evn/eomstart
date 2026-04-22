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
  List<String> _availableZones = [];
  Set<String> _busyShifts = {};
  List<Map<String, dynamic>> _previewResult = [];

  bool _isLoading = false;
  bool _isCalculating = false;
  bool _isSaving = false;

  final TextEditingController _morningController = TextEditingController(text: '1');
  final TextEditingController _eveningController = TextEditingController(text: '1');
  final TextEditingController _fullController = TextEditingController(text: '0');
  final TextEditingController _aiController = TextEditingController();
  bool _isAiProcessing = false;
  Map<String, dynamic>? _aiRecommendation;
  bool _isFetchingRecommendation = false;

  @override
  void initState() {
    super.initState();
    _loadScoutsAndBusyShifts();
    _fetchAiRecommendation();
  }

  @override
  void dispose() {
    _morningController.dispose();
    _eveningController.dispose();
    _fullController.dispose();
    _aiController.dispose();
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

      final zones = await _apiService.getAvailableZones(token);

      final days = _isWeekly ? 7 : 1;
      final busy = await _getBusyShifts(token, _startDate, days);

      if (mounted) {
        setState(() {
          _availableScouts = scouts;
          _availableZones = zones;
          _busyShifts = busy;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAiRecommendation() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return;

    setState(() => _isFetchingRecommendation = true);
    try {
      final rec = await _apiService.getShiftRecommendations(token, _startDate);
      if (mounted) {
        setState(() {
          _aiRecommendation = rec;
          _isFetchingRecommendation = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки рекомендаций: $e');
      if (mounted) setState(() => _isFetchingRecommendation = false);
    }
  }

  void _applyAiRecommendation() {
    if (_aiRecommendation == null) return;
    
    setState(() {
      _morningCount = _aiRecommendation!['recommended_morning'] ?? 0;
      _eveningCount = _aiRecommendation!['recommended_evening'] ?? 0;
      _fullCount = _aiRecommendation!['recommended_full'] ?? 0;
      
      _morningController.text = _morningCount.toString();
      _eveningController.text = _eveningCount.toString();
      _fullController.text = _fullCount.toString();
    });
    
    _calculatePreview();
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
      _fetchAiRecommendation();
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

  Future<void> _processAiCommand() async {
    final text = _aiController.text.trim().toLowerCase();
    if (text.isEmpty) return;

    setState(() => _isAiProcessing = true);

    // Имитация "размышления" ИИ
    await Future.delayed(const Duration(milliseconds: 1500));

    bool morningSet = false;
    bool eveningSet = false;
    bool fullSet = false;

    // Регулярки для поиска чисел
    final numReg = RegExp(r'(\d+)');
    
    // Сценарии
    if (text.contains('недел')) {
      _isWeekly = true;
    } else if (text.contains('завтр')) {
      _startDate = DateTime.now().add(const Duration(days: 1));
      _isWeekly = false;
    } else if (text.contains('сегод') || text.contains('сейч')) {
      _startDate = DateTime.now();
      _isWeekly = false;
    }

    bool noZones = text.contains('без зон');

    // Парсинг количеств
    final parts = text.split(RegExp(r'[,.;]|\sи\s'));
    for (var part in parts) {
      final match = numReg.firstMatch(part);
      if (match != null) {
        final count = int.parse(match.group(1)!);
        if (part.contains('утр')) {
          _morningCount = count;
          _morningController.text = count.toString();
          morningSet = true;
        } else if (part.contains('веч')) {
          _eveningCount = count;
          _eveningController.text = count.toString();
          eveningSet = true;
        } else if (part.contains('полн') || part.contains('день')) {
          _fullCount = count;
          _fullController.text = count.toString();
          fullSet = true;
        }
      }
    }

    // Если прямого указания не было, но есть одно число — применяем его ко всему или по логике
    if (!morningSet && !eveningSet && !fullSet) {
       final match = numReg.firstMatch(text);
       if (match != null) {
         final count = int.parse(match.group(1)!);
         _morningCount = count;
         _morningController.text = count.toString();
         _eveningCount = count;
         _eveningController.text = count.toString();
       }
    }

    setState(() => _isAiProcessing = false);
    await _calculatePreview(autoAssignZones: !noZones);
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('✨ ИИ: Расписание сформировано и зоны распределены'),
           backgroundColor: Colors.indigo,
           behavior: SnackBarBehavior.floating,
         )
       );
    }
  }

  Future<void> _calculatePreview({bool autoAssignZones = true}) async {
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

    int zoneIndex = 0;

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

      // Авто-распределение зон
      final dayAssignments = <String, List<int>>{};
      if (autoAssignZones && _availableZones.isNotEmpty) {
        for (var id in [...full, ...morning, ...evening]) {
          final zone = _availableZones[zoneIndex % _availableZones.length];
          if (!dayAssignments.containsKey(zone)) dayAssignments[zone] = [];
          dayAssignments[zone]!.add(id);
          zoneIndex++;
        }
      }

      result.add({
        'date': date,
        'full': full,
        'morning': morning,
        'evening': evening,
        'assignments': dayAssignments, // Зона -> Список ID
      });
    }

    if (mounted) {
      setState(() {
        _previewResult = result;
        _isCalculating = false;
      });
    }
  }

  // _saveShifts удален по запросу, так как сохранение в БД больше не требуется

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
      final assignments = Map<String, List<int>>.from(day['assignments'] ?? {});
      
      buffer.writeln('--------------------------');
      buffer.writeln('📅 *${date.day}.${date.month}.${date.year}*');

      if (assignments.isNotEmpty) {
        assignments.forEach((zone, ids) {
          buffer.writeln('📍 *Зона $zone*: ${ids.map((id) => _getHandle(id)).join(', ')}');
        });
        buffer.writeln();
      }

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
                _buildAiRecommendationCard(primaryColor),
                const SizedBox(height: 16),
                _buildAiAssistantCard(primaryColor),
                const SizedBox(height: 16),
                Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: const Text('Ручные параметры (опционально)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.grey)),
                    tilePadding: EdgeInsets.zero,
                    children: [
                      _buildSettingsCard(primaryColor),
                      const SizedBox(height: 12),
                      _buildShiftCountsCard(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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

  Widget _buildAiAssistantCard(Color primaryColor) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor.withOpacity(0.15), Colors.indigo.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: primaryColor.withOpacity(0.05), blurRadius: 30, spreadRadius: 5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.25),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: primaryColor.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
                  ],
                ),
                child: Icon(Icons.auto_awesome, color: primaryColor, size: 24),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ИИ ПОМОЩНИК',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.2),
                  ),
                  Text(
                    'Умное распределение смен и зон',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const Spacer(),
              if (_isAiProcessing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.indigo),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _aiController,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Пример: "Смена на завтра, 2 человека утром и 1 вечером. Без зон."',
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
              filled: true,
              fillColor: theme.cardColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: primaryColor, width: 1.5),
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(Icons.send_rounded, color: primaryColor, size: 28),
                  onPressed: _isAiProcessing ? null : _processAiCommand,
                ),
              ),
            ),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            onSubmitted: (_) => _isAiProcessing ? null : _processAiCommand(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildFastChip('Завтра 2+1', () => _aiController.text = 'Смена на завтра, 2 утром и 1 вечером'),
              _buildFastChip('Неделя по 1', () => _aiController.text = 'На неделю по 1 человеку в смену'),
              _buildFastChip('Без зон', () {
                if (!_aiController.text.contains('Без зон')) {
                  _aiController.text += ' Без зон.';
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFastChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      onPressed: onTap,
      backgroundColor: Colors.white.withOpacity(0.5),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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


  Widget _buildDayPreviewCard(Map<String, dynamic> day) {
    final theme = Theme.of(context);
    final date = day['date'] as DateTime;
    final full = List<int>.from(day['full']);
    final morning = List<int>.from(day['morning']);
    final evening = List<int>.from(day['evening']);
    final assignments = Map<String, List<int>>.from(day['assignments'] ?? {});

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
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
          if (assignments.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('📍 РАСПРЕДЕЛЕНИЕ ПО ЗОНАМ:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...assignments.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  Text('Зона ${e.key}: ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Expanded(child: Text(e.value.map((id) => _getHandle(id)).join(', '), style: const TextStyle(fontSize: 13))),
                ],
              ),
            )),
          ],
          const SizedBox(height: 12),
          const Text('⏰ ГРАФИК РАБОТЫ:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
          const SizedBox(height: 8),
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

  Widget _buildAiRecommendationCard(Color primaryColor) {
    if (_isFetchingRecommendation) {
      return Container(
        height: 100,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_aiRecommendation == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.indigo.withOpacity(0.2) : Colors.indigo.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.indigo.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.indigo, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'РЕКОМЕНДАЦИЯ ИИ',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                ),
              ),
              if (_aiRecommendation!['weather_icon'] != null)
                Image.network(
                  'https://openweathermap.org/img/wn/${_aiRecommendation!['weather_icon']}@2x.png',
                  width: 40,
                  height: 40,
                  errorBuilder: (_, __, ___) => const Icon(Icons.wb_sunny, color: Colors.orange),
                ),
              Text(
                '${_aiRecommendation!['temperature'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _aiRecommendation!['reason'] ?? '',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSmallBadge('Утро: ${_aiRecommendation!['recommended_morning']}'),
              const SizedBox(width: 8),
              _buildSmallBadge('Вечер: ${_aiRecommendation!['recommended_evening']}'),
              const SizedBox(width: 8),
              _buildSmallBadge('День: ${_aiRecommendation!['recommended_full']}'),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _applyAiRecommendation,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Применить план ИИ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
    );
  }
}
