import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'map_screens.dart';
import 'profile_screens.dart';
import 'qr_scanner_screen.dart';
import 'about_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'zones_screen.dart';

enum SlotState {
  inactive,
  pickingDuration,
  pickingDetails,
  active,
}

class ShiftData {
  final DateTime date;
  final String selectedSlot;
  final String workedTime;
  final String workPeriod;
  final String transportStatus;
  final int newTasks;

  ShiftData({
    required this.date,
    required this.selectedSlot,
    required this.workedTime,
    required this.workPeriod,
    required this.transportStatus,
    required this.newTasks,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _currentTime = '';
  Timer? _timer;
  bool _isDayModeSelected = true;
  int _currentIndex = 0;

  SlotState _slotState = SlotState.inactive;
  String? _selectedSlotTimeRange;
  List<String> _selectedZones = ['Алматы дивизион 3'];
  String _employeePosition = 'Водитель';
  File? _selfieImage;

  late final Map<DateTime, ShiftData> _shiftHistory;
  late DateTime _selectedCalendarDate;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _startTimer();
    _generateMockShiftData();
    _selectedCalendarDate = DateTime.now();
  }

  void _generateMockShiftData() {
    _shiftHistory = {
      DateTime.now().subtract(const Duration(days: 1)): ShiftData(
        date: DateTime.now().subtract(const Duration(days: 1)),
        selectedSlot: '8 часов',
        workedTime: '7 ч 58 мин',
        workPeriod: '07:00–14:58',
        transportStatus: 'Транспорт не указан',
        newTasks: 2,
      ),
      DateTime.now().subtract(const Duration(days: 2)): ShiftData(
        date: DateTime.now().subtract(const Duration(days: 2)),
        selectedSlot: '12 часов',
        workedTime: '11 ч 59 мин',
        workPeriod: '07:00–18:59',
        transportStatus: 'Транспорт не указан',
        newTasks: 0,
      ),
      DateTime.now().subtract(const Duration(days: 3)): ShiftData(
        date: DateTime.now().subtract(const Duration(days: 3)),
        selectedSlot: '4 часа',
        workedTime: '3 ч 50 мин',
        workPeriod: '15:00–18:50',
        transportStatus: 'Транспорт не указан',
        newTasks: 1,
      ),
      DateTime.now(): ShiftData(
        date: DateTime.now(),
        selectedSlot: '12 часов',
        workedTime: '0 ч 22 мин',
        workPeriod: '19:00–19:22',
        transportStatus: 'Транспорт не указан',
        newTasks: 0,
      ),
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateTime();
      }
    });
  }

  void _updateTime() {
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    });
  }

  Future<void> _takeSelfie() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selfieImage = File(image.path);
      });
      _openDurationSheet();
    }
  }

  void _openDurationSheet() {
    setState(() {
      _slotState = SlotState.pickingDuration;
    });
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _buildSlotDurationSheet();
      },
    );
  }

  void _openDetailsSheet() {
    setState(() {
      _slotState = SlotState.pickingDetails;
    });
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _buildSlotDetailsSheet();
      },
    );
  }

  void _activateSlot() {
    setState(() {
      _slotState = SlotState.active;
    });
    Navigator.pop(context);
  }

  void _deactivateSlot() {
    setState(() {
      _slotState = SlotState.inactive;
      _selectedSlotTimeRange = null;
      _selectedZones = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    List<DateTime> calendarDays =
        List.generate(9, (index) => now.subtract(Duration(days: 4 - index)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          ),
          TextButton(
            onPressed: () {},
            child: const Text('TM', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSlotCard(),
            const SizedBox(height: 20),
            _buildReportCard(now, calendarDays),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey[600],
        backgroundColor: Colors.white,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          switch (index) {
            case 0:
              break;
            case 1:
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const MapScreen()));
              break;
            case 2:
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const QrScannerScreen()));
              break;
            case 3:
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ProfileScreen()));
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Главная'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Карта'),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: 'QR-сканер'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
        ],
      ),
    );
  }

  Widget _buildSlotCard() {
    if (_slotState == SlotState.active) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.green[700],
          borderRadius: BorderRadius.circular(15.0),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Активный слот',
                      style: TextStyle(color: Colors.green[100], fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedSlotTimeRange ?? 'Слот',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _deactivateSlot,
                  child: const Icon(
                    Icons.pause_circle_outline,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white54),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoBlock(
                  'Завершить',
                  Icons.power_settings_new,
                  Colors.white,
                  () {
                    _deactivateSlot();
                  },
                ),
                _buildInfoBlock(
                  'Пауза',
                  Icons.pause,
                  Colors.white,
                  () {},
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: () {
          if (_selfieImage == null) {
            _takeSelfie();
          } else {
            _openDurationSheet();
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15.0),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, color: Colors.green[700]),
                  const SizedBox(width: 10),
                  Text(
                    'Начать слот',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700]),
                  ),
                ],
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildInfoBlock(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotDurationSheet() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _slotState = SlotState.inactive;
                  });
                },
              ),
              const Text('Длительность слота',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.transparent),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDurationButton('7:00 - 15:00'),
          const SizedBox(height: 16),
          _buildDurationButton('15:00 - 23:00'),
          const SizedBox(height: 16),
          _buildDurationButton('7:00 - 23:00'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedSlotTimeRange != null
                  ? () {
                      Navigator.pop(context);
                      _openDetailsSheet();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Далее'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationButton(String timeRange) {
    bool isSelected = _selectedSlotTimeRange == timeRange;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSlotTimeRange = timeRange;
        });
        (context as Element).markNeedsBuild();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.green[700]! : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            timeRange,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotDetailsSheet() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                  _openDurationSheet();
                },
              ),
              const Text('Начать слот',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Алматы EOM', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 20),
          _buildDetailItem(
            icon: Icons.person,
            title: _employeePosition,
            subtitle: 'Должность',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _buildDetailItem(
            icon: Icons.location_on,
            title: _selectedZones.isEmpty
                ? 'Не выбраны'
                : _selectedZones.join(', '),
            subtitle: 'Техзоны',
            trailingText: _selectedZones.length.toString(),
            onTap: () async {
              final newSelectedZones = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ZonesScreen(selectedZones: _selectedZones),
                ),
              );

              if (newSelectedZones != null) {
                setState(() {
                  _selectedZones = newSelectedZones;
                });
              }
              (context as Element).markNeedsBuild();
            },
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _activateSlot();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Далее'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailingText,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.green[700], size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ],
              ),
            ),
            if (trailingText != null) ...[
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 12,
                backgroundColor: Colors.green[700],
                child: Text(
                  trailingText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarDayCard(DateTime date, bool isActive) {
    final DateFormat dayOfWeekFormat = DateFormat('EE', 'ru');
    final DateFormat dayOfMonthFormat = DateFormat('d', 'ru');

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCalendarDate = date;
        });
      },
      child: Column(
        children: [
          Text(
            dayOfWeekFormat.format(date),
            style: TextStyle(
              color: isActive ? Colors.green[700] : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: isActive ? Colors.green[700] : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                dayOfMonthFormat.format(date),
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(DateTime now, List<DateTime> calendarDays) {
    ShiftData? shiftData = _shiftHistory.containsKey(_selectedCalendarDate)
        ? _shiftHistory[_selectedCalendarDate]
        : null;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDayModeSelected = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _isDayModeSelected
                            ? Colors.green[600]
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Center(
                        child: Text(
                          'День',
                          style: TextStyle(
                            color: _isDayModeSelected
                                ? Colors.white
                                : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDayModeSelected = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_isDayModeSelected
                            ? Colors.green[600]
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Center(
                        child: Text(
                          'Период',
                          style: TextStyle(
                            color: !_isDayModeSelected
                                ? Colors.white
                                : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: calendarDays.map((date) {
              bool isActive = date.day == _selectedCalendarDate.day &&
                  date.month == _selectedCalendarDate.month &&
                  date.year == _selectedCalendarDate.year;
              return _buildCalendarDayCard(date, isActive);
            }).toList(),
          ),
          const SizedBox(height: 20),
          _buildShiftDetailsCard(shiftData),
        ],
      ),
    );
  }

  Widget _buildShiftDetailsCard(ShiftData? shiftData) {
    if (shiftData == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Center(
          child: Text(
            'Отчет по смене отсутствует',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Водитель',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(shiftData.transportStatus,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
          const Divider(),
          _buildShiftDetailRow(
              'По задачнику ТС (новый)', shiftData.newTasks.toString()),
          _buildShiftDetailRow('Выбранный слот', shiftData.selectedSlot),
          _buildShiftDetailRow('Время работы', shiftData.workedTime),
          _buildShiftDetailRow('Период работы', shiftData.workPeriod),
        ],
      ),
    );
  }

  Widget _buildShiftDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
