// lib/screens/dashboard/dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../../providers/shift_provider.dart';
import '../components/slot_card.dart';
import '../components/report_card.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';
import 'package:micro_mobility_app/screens/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/screens/profile_screens.dart';
import 'package:micro_mobility_app/utils/app_icons.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

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
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final result = results.firstWhere(
        (r) => r != ConnectivityResult.none,
        orElse: () => ConnectivityResult.none,
      );
      if (mounted && result != ConnectivityResult.none) {
        setState(() {}); // Перестроит _DashboardHome
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
                _currentIndex == 0 ? AppIcons.home2 : AppIcons.home,
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _loadDataFuture = _loadData();
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
      if (mounted && result != ConnectivityResult.none) {
        setState(() {
          _loadDataFuture = _loadData();
        });
      }
    });
  }

  Future<void> _loadData() async {
    // ✅ Исправлено: используем context.read()
    final provider = context.read<ShiftProvider>();
    await provider.loadShifts();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadDataFuture = _loadData();
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
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<void>(
          future: _loadDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Colors.green));
            } else if (snapshot.hasError) {
              if (snapshot.error.toString().contains('SocketException') ||
                  snapshot.error.toString().contains('Network')) {
                return NoInternetWidget(onRetry: _refresh);
              } else {
                return Center(
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
                          onPressed: _refresh,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                );
              }
            } else {
              return const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SlotCard(),
                    SizedBox(height: 10),
                    ReportCard(),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

/// Виджет при отсутствии интернета
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
              child: const Icon(Icons.wifi_off, size: 80, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            const Text(
              'Нет подключения к интернету',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Проверьте соединение с сетью и попробуйте снова',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Повторить',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
