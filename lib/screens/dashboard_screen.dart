import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

enum SlotState {
  inactive,
  active,
}

enum SlotSetupStep {
  selfie,
  pickingDuration,
  pickingDetails,
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
  Timer? _timer;
  bool _isDayModeSelected = true;
  int _currentIndex = 0;

  SlotState _slotState = SlotState.inactive;
  String? _selectedSlotTimeRange;
  String? _selectedZone;
  String? _selectedPosition;

  late final Map<DateTime, ShiftData> _shiftHistory;
  late DateTime _selectedCalendarDate;

  String? _activeSlotStartTime;
  int _activeSlotDurationInSeconds = 0;
  Timer? _activeSlotTimer;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _startClockTimer();
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
    _activeSlotTimer?.cancel();
    super.dispose();
  }

  void _startClockTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateTime();
      }
    });
  }

  void _updateTime() {
    setState(() {
      if (_slotState == SlotState.active && _activeSlotStartTime != null) {
        _updateActiveSlotTime();
      }
    });
  }

  void _updateActiveSlotTime() {
    final now = DateTime.now();
    final startTime = DateFormat('HH:mm').parse(_activeSlotStartTime!);
    final duration = now.difference(DateTime(
        now.year, now.month, now.day, startTime.hour, startTime.minute));
    _activeSlotDurationInSeconds = duration.inSeconds;
  }

  void _deactivateSlot() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить слот?'),
        content: const Text(
            'Вы уверены, что хотите завершить текущий слот? Это действие нельзя будет отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() {
                  _slotState = SlotState.inactive;
                  _selectedSlotTimeRange = null;
                  _selectedZone = null;
                  _selectedPosition = null;
                });
              }
              _activeSlotTimer?.cancel();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
  }

  void _openSlotSetupModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SlotSetupModal(
        initialPosition: _selectedPosition,
        initialZone: _selectedZone,
        onSlotActivated: (String slotTimeRange, String position, String zone,
            File selfieImage) {
          if (mounted) {
            setState(() {
              _slotState = SlotState.active;
              _selectedSlotTimeRange = slotTimeRange;
              _selectedPosition = position;
              _selectedZone = zone;
              _activeSlotStartTime = DateFormat('HH:mm').format(DateTime.now());
              _activeSlotDurationInSeconds = 0;
            });
            _activeSlotTimer =
                Timer.periodic(const Duration(seconds: 1), (timer) {
              _updateActiveSlotTime();
            });
          }
        },
      ),
    );
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
              Navigator.pushNamed(context, '/map');
              break;
            case 2:
              Navigator.pushNamed(context, '/qr_scanner');
              break;
            case 3:
              Navigator.pushNamed(context, '/profile');
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
      final hours = _activeSlotDurationInSeconds ~/ 3600;
      final minutes = (_activeSlotDurationInSeconds % 3600) ~/ 60;
      final timeString = '${hours}ч ${minutes}мин';

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
                    Icons.power_settings_new,
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
                  'Слот активен',
                  '${DateFormat('HH:mm').format(DateTime.now().subtract(Duration(seconds: _activeSlotDurationInSeconds)))}-${DateFormat('HH:mm').format(DateTime.now())}',
                  Colors.white,
                ),
                _buildInfoBlock(
                  'Время работы',
                  timeString,
                  Colors.white,
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return GestureDetector(
        onTap: _openSlotSetupModal,
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

  Widget _buildInfoBlock(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCalendarDayCard(DateTime date, bool isActive) {
    final DateFormat dayOfWeekFormat = DateFormat('EE', 'ru');
    final DateFormat dayOfMonthFormat = DateFormat('d', 'ru');

    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() {
            _selectedCalendarDate = date;
          });
        }
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
                      if (mounted) {
                        setState(() {
                          _isDayModeSelected = true;
                        });
                      }
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
                      if (mounted) {
                        setState(() {
                          _isDayModeSelected = false;
                        });
                      }
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

class _SlotSetupModal extends StatefulWidget {
  final Function(String, String, String, File) onSlotActivated;
  final String? initialPosition;
  final String? initialZone;

  const _SlotSetupModal(
      {required this.onSlotActivated, this.initialPosition, this.initialZone});

  @override
  State<_SlotSetupModal> createState() => _SlotSetupModalState();
}

class _SlotSetupModalState extends State<_SlotSetupModal> {
  SlotSetupStep _state = SlotSetupStep.selfie;
  File? _selfieImage;
  String? _selectedSlotTimeRange;
  String? _selectedZone;
  String? _selectedPosition;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
    _selectedZone = widget.initialZone;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _takeSelfie();
    });
  }

  Future<void> _takeSelfie() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      if (mounted) {
        setState(() {
          _selfieImage = File(image.path);
          _state = SlotSetupStep.pickingDuration;
        });
      }
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _openDurationStep() {
    if (mounted) {
      setState(() {
        _state = SlotSetupStep.pickingDuration;
      });
    }
  }

  void _openDetailsStep() {
    if (mounted) {
      setState(() {
        _state = SlotSetupStep.pickingDetails;
      });
    }
  }

  void _finishSetup() {
    if (_selectedSlotTimeRange != null &&
        _selectedZone != null &&
        _selectedPosition != null &&
        _selfieImage != null) {
      widget.onSlotActivated(_selectedSlotTimeRange!, _selectedPosition!,
          _selectedZone!, _selfieImage!);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: _buildCurrentStateView(),
    );
  }

  Widget _buildCurrentStateView() {
    switch (_state) {
      case SlotSetupStep.selfie:
        return _buildSelfieView();
      case SlotSetupStep.pickingDuration:
        return _buildSlotDurationView();
      case SlotSetupStep.pickingDetails:
        return _buildSlotDetailsView();
    }
  }

  Widget _buildSelfieView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 48),
            const Text('Селфи для слота',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const Spacer(),
        if (_selfieImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(15.0),
            child: Image.file(
              _selfieImage!,
              height: 200,
              width: 200,
              fit: BoxFit.cover,
            ),
          )
        else
          const CircularProgressIndicator(),
        const Spacer(),
      ],
    );
  }

  Widget _buildSlotDurationView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _takeSelfie,
            ),
            const Text('Длительность слота',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
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
            onPressed: _selectedSlotTimeRange != null ? _openDetailsStep : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Далее'),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationButton(String timeRange) {
    bool isSelected = _selectedSlotTimeRange == timeRange;
    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() {
            _selectedSlotTimeRange = timeRange;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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

  Widget _buildSlotDetailsView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _openDurationStep,
            ),
            const Text('Начать слот',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Jet KZ1 | Алматинский • Алматы',
            style: TextStyle(color: Colors.grey[700])),
        const SizedBox(height: 20),
        _buildDetailItem(
          icon: Icons.person,
          title: _selectedPosition ?? 'Не выбрано',
          subtitle: 'Должность',
          onTap: () async {
            final newSelectedPosition =
                await Navigator.pushNamed(context, '/positions');
            if (newSelectedPosition != null && newSelectedPosition is String) {
              if (mounted) {
                setState(() {
                  _selectedPosition = newSelectedPosition;
                });
              }
            }
          },
        ),
        const SizedBox(height: 10),
        _buildDetailItem(
          icon: Icons.location_on,
          title: _selectedZone ?? 'Не выбрано',
          subtitle: 'Техзоны',
          trailingText: _selectedZone != null ? '1' : '0',
          onTap: () async {
            final newSelectedZone =
                await Navigator.pushNamed(context, '/zones');
            if (newSelectedZone != null && newSelectedZone is String) {
              if (mounted) {
                setState(() {
                  _selectedZone = newSelectedZone;
                });
              }
            }
          },
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selectedZone != null && _selectedPosition != null)
                ? _finishSetup
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Начать'),
          ),
        ),
      ],
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
}
