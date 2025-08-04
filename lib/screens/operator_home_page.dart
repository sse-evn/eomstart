import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'map_screens.dart'; // Или точный путь к вашему файлу с MapScreen
import 'profile_screens.dart'; // Или точный путь
import 'qr_scanner_screen.dart'; // Или точный путь

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _currentTime = '';
  Timer? _timer;
  bool _isDayModeSelected = true;
  int _currentIndex = 0; // Текущий выбранный индекс

  @override
  void initState() {
    super.initState();
    _updateTime();
    _startTimer();
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

  Widget _buildCalendarDayCard(DateTime date, bool isActive) {
    final DateFormat dayOfWeekFormat = DateFormat('EE', 'ru');
    final DateFormat dayOfMonthFormat = DateFormat('d', 'ru');

    return Column(
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActiveSlotCard(),
            const SizedBox(height: 20),
            _buildReportCard(now, calendarDays),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('О приложении'),
                      content: const Text(
                          'Это приложение для операторов микромобильности. Версия 1.0.0'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text('Закрыть'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'О приложении',
                        style: TextStyle(fontSize: 16),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey[600],
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Карта',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Профиль',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'QR-сканер',
          ),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              // Главная - это текущий экран (DashboardScreen), можно ничего не делать
              // Или перейти снова, если хотите сбросить состояние:
              // Navigator.push(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
              break;
            case 1:
              // Перейти на экран Карты (предположим, он называется MapScreen)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const MapScreen(), // Убедитесь, что MapScreen импортирован
                ),
              );
              break;
            case 2:
              // Перейти на Профиль (предположим, он называется ProfileScreen)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const ProfileScreen(), // Убедитесь, что ProfileScreen импортирован
                ),
              );
              break;
            case 3:
              // Перейти на Сканирование QR-кода (предположим, он называется QrScannerScreen)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const QrScannerScreen(), // Убедитесь, что QrScannerScreen импортирован
                ),
              );
              break;
          }
        },
      ),
    );
  }

  Widget _buildActiveSlotCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.green[800],
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Активный слот',
                style: TextStyle(
                  color: Colors.green[200],
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Icon(
            Icons.arrow_forward_ios,
            color: Colors.white,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(DateTime now, List<DateTime> calendarDays) {
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
          // Переключатель "День" / "Период"
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
          // Календарь (динамический)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: calendarDays.map((date) {
              bool isActive = date.day == now.day &&
                  date.month == now.month &&
                  date.year == now.year;
              return _buildCalendarDayCard(date, isActive);
            }).toList(),
          ),
          const SizedBox(height: 20),
          // Иконки и текст отчета
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person, size: 60, color: Colors.green),
              const SizedBox(width: 20),
              Icon(Icons.monetization_on, size: 60, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 10),
          // Убедитесь, что текст может переноситься
          Text(
            'Отчет будет сформирован по завершении слота',
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            textAlign: TextAlign.center,
            softWrap: true, // Разрешаем перенос текста
            overflow: TextOverflow.visible, // Убеждаемся, что не обрезается
          ),
        ],
      ),
    );
  }
}
