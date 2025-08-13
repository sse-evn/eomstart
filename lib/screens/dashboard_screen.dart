import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:micro_mobility_app/utils/app_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/shift_provider.dart';
import '../components/slot_card.dart';
import '../components/report_card.dart';
import '../components/history_chart.dart';
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

  final List<Widget> _screens = [
    _DashboardHome(),
    const MapScreen(),
    const QrScannerScreen(),
    const ProfileScreen(),
  ];

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
                _currentIndex == 0 ? AppIcons.home : AppIcons.home2,
                key: ValueKey<int>(_currentIndex), // важно для анимации
                color: _currentIndex == 0 ? Colors.green[700] : Colors.grey,
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
                color: _currentIndex == 1 ? Colors.green[700] : Colors.grey,
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
                color: _currentIndex == 2 ? Colors.green[700] : Colors.grey,
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
                _currentIndex == 3 ? AppIcons.profile : AppIcons.profile2,
                key: ValueKey<int>(_currentIndex),
                color: _currentIndex == 3 ? Colors.green[700] : Colors.grey,
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

class _DashboardHome extends StatelessWidget {
  const _DashboardHome();

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ShiftProvider>(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
    
        title: const Text('Главная'),
        actions: [
          IconButton(icon: SvgPicture.asset(AppIcons.notification, color: Colors.black87,), onPressed: () {}),
        ],
    ),
      body: RefreshIndicator(
        onRefresh: () => provider.loadShifts(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SlotCard(),
              // const SizedBox(height: 20),
              const SizedBox(height: 20),
              const ReportCard(),
            ],
          ),
        ),
      ),
    );
  }
}
