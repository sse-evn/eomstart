// lib/screens/dashboard/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Добавлен импорт
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:micro_mobility_app/utils/app_icons.dart'; // Убедитесь, что путь правильный
import 'package:provider/provider.dart';
import '../../providers/shift_provider.dart';
import '../components/slot_card.dart';
import '../components/report_card.dart';
// import '../components/history_chart.dart'; // Удален неиспользуемый импорт
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';
import 'package:micro_mobility_app/screens/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/screens/profile_screens.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  late StreamSubscription<List<ConnectivityResult>>
      _connectivitySubscription; // Исправлен тип

  final List<Widget> _screens = [
    const _DashboardHome(),
    const MapScreen(),
    const QrScannerScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _listenToConnectionChanges();
  }

  void _listenToConnectionChanges() {
    // Исправлена подписка с правильной обработкой типа Stream<List<ConnectivityResult>>
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      // Обычно список содержит один результат, но берем первый "подключенный"
      final result = results.firstWhere(
        (r) => r != ConnectivityResult.none,
        orElse: () => ConnectivityResult.none,
      );
      if (mounted) {
        // setState не нужен для _hasInternet/_isCheckingConnection, так как
        // NoInternetScreen теперь обрабатывается внутри _DashboardHome
        // Просто перестраиваем текущий экран (_DashboardHome), чтобы он мог проверить состояние
        if (result != ConnectivityResult.none) {
          // Если соединение появилось, заставляем _DashboardHome перезагрузиться
          setState(
              () {}); // Это пересоздаст _DashboardHome, вызвав его initState
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Основное тело - текущий экран из списка
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green[700],
        selectedFontSize: 13,
        unselectedItemColor: Colors.grey[600],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: SvgPicture.asset(
                _currentIndex == 0
                    ? AppIcons.home2
                    : AppIcons.home, // Пример названий иконок
                key: ValueKey<int>(_currentIndex),
                colorFilter: ColorFilter.mode(
                  _currentIndex == 0 ? Colors.green[700]! : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
            ),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: SvgPicture.asset(
                _currentIndex == 1 ? AppIcons.map2 : AppIcons.map,
                key: ValueKey<int>(_currentIndex),
                colorFilter: ColorFilter.mode(
                  _currentIndex == 1 ? Colors.green[700]! : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
            ),
            label: 'Карта',
          ),
          BottomNavigationBarItem(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: SvgPicture.asset(
                _currentIndex == 2 ? AppIcons.qr2 : AppIcons.qr,
                key: ValueKey<int>(_currentIndex),
                colorFilter: ColorFilter.mode(
                  _currentIndex == 2 ? Colors.green[700]! : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
            ),
            label: 'QR',
          ),
          BottomNavigationBarItem(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: SvgPicture.asset(
                _currentIndex == 3 ? AppIcons.profile2 : AppIcons.profile,
                key: ValueKey<int>(_currentIndex),
                colorFilter: ColorFilter.mode(
                  _currentIndex == 3 ? Colors.green[700]! : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
            ),
            label: 'Профиль',
          ),
        ],
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// --- Экран главной страницы ---
class _DashboardHome extends StatefulWidget {
  const _DashboardHome();

  @override
  State<_DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<_DashboardHome> {
  late Future<void> _loadDataFuture;
  StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription; // Исправлен тип

  @override
  void initState() {
    super.initState();
    _loadDataFuture = _loadData(); // Инициализируем загрузку данных
    _listenToConnectionChanges();
  }

  void _listenToConnectionChanges() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final result = results.firstWhere(
        (r) => r != ConnectivityResult.none,
        orElse: () => ConnectivityResult.none,
      );
      // Просто перестраиваем Future, если соединение появилось
      if (mounted && result != ConnectivityResult.none) {
        setState(() {
          _loadDataFuture = _loadData(); // Перезапускаем загрузку
        });
      }
    });
  }

  Future<void> _loadData() async {
    final provider = Provider.of<ShiftProvider>(context, listen: false);
    await provider.loadShifts(); // loadShifts сам обрабатывает ошибки
  }

  Future<void> _refresh() async {
    setState(() {
      _loadDataFuture = _loadData(); // Пересоздаем Future для обновления
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Главная'),
        actions: [
          IconButton(
            icon: SvgPicture.asset(
              AppIcons.notification, // Убедитесь, что иконка существует
              color: Colors.black87,
            ),
            onPressed: () {
              // Логика для уведомлений
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<void>(
          future: _loadDataFuture,
          builder: (context, snapshot) {
            Widget child;
            if (snapshot.connectionState == ConnectionState.waiting) {
              child = const Center(
                  child: CircularProgressIndicator(color: Colors.green));
            } else if (snapshot.hasError) {
              // Проверяем тип ошибки
              if (snapshot.error.toString().contains('SocketException') ||
                  snapshot.error.toString().contains('Network')) {
                child = NoInternetWidget(
                    onRetry: _refresh); // Показываем виджет "Нет интернета"
              } else {
                // Другая ошибка (например, сервер 500)
                child = Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Ошибка загрузки данных',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _refresh, // Повторить попытку
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                );
              }
            } else {
              // Данные успешно загружены
              child = const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SlotCard(),
                    SizedBox(height: 20),
                    ReportCard(),
                    // HistoryChart(), // Если используется
                  ],
                ),
              );
            }

            return child;
          },
        ),
      ),
    );
  }
}

/// Виджет, отображаемый при отсутствии интернета
class NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;

  const NoInternetWidget({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off,
                size: 80,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Нет подключения к интернету',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Проверьте соединение с сетью и попробуйте снова',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Повторить',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // TextButton для перехода в настройки (опционально, требует доп. пакетов)
            // TextButton(
            //   onPressed: () {
            //     // Логика для открытия настроек сети
            //   },
            //   child: const Text(
            //     'Проверить настройки сети',
            //     style: TextStyle(color: Colors.green),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
