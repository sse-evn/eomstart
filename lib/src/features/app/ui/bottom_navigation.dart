// lib/screens/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:micro_mobility_app/src/features/home/home_screen.dart';
import 'package:micro_mobility_app/src/features/map_screen/map_screens.dart';
import 'package:micro_mobility_app/src/features/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/src/features/profile/profile_screen.dart';
import 'package:micro_mobility_app/src/core/utils/app_icons.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;


  final List<Widget> _screens = [
    const DashboardHome(),
    const MapScreen(),
    const QrScannerScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],


      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,  
          splashColor: Colors.transparent,  
        ),
        child: BottomNavigationBar(
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
      ),
    );
  }
}
