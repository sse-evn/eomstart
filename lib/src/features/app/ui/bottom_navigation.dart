import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:micro_mobility_app/src/features/home/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_state.dart';
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
    return BlocBuilder<ShiftBloc, ShiftState>(
      builder: (context, shiftState) {
        final hasActiveShift = shiftState is ShiftActive;

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
                // Разрешаем переход на вкладку "Главная" (0) и "Профиль" (3) всегда
                // Для вкладок "Карта" (1) и "QR" (2) проверяем наличие активной смены
                if (index != 0 && index != 3 && !hasActiveShift) {
                  final provider =
                      Provider.of<ShiftProvider>(context, listen: false);
                  final role =
                      provider.profile?['role']?.toString().toLowerCase();
                  final isAllowedRole = role == 'superadmin' ||
                      role == 'supervisor' ||
                      role == 'coordinator';

                  if (!isAllowedRole) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Сначала откройте рабочую смену'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                }

                setState(() {
                  _currentIndex = index;
                });
              },
              items: [
                BottomNavigationBarItem(
                  icon: _buildIcon(AppIcons.home, AppIcons.home2, 0),
                  label: 'Главная',
                ),
                BottomNavigationBarItem(
                  icon: Opacity(
                    opacity: hasActiveShift ? 1.0 : 0.5,
                    child: _buildIcon(AppIcons.map, AppIcons.map2, 1),
                  ),
                  label: 'Карта',
                ),
                BottomNavigationBarItem(
                  icon: Opacity(
                    opacity: hasActiveShift ? 1.0 : 0.5,
                    child: _buildIcon(AppIcons.qr, AppIcons.qr2, 2),
                  ),
                  label: 'QR',
                ),
                BottomNavigationBarItem(
                  icon: _buildIcon(AppIcons.profile, AppIcons.profile2, 3),
                  label: 'Профиль',
                ),
              ],
              type: BottomNavigationBarType.fixed,
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon(String normalIcon, String selectedIcon, int index) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: SvgPicture.asset(
        _currentIndex == index ? selectedIcon : normalIcon,
        key: ValueKey<int>(_currentIndex == index ? 1 : 0),
        colorFilter: ColorFilter.mode(
          _currentIndex == index ? Colors.green[700]! : Colors.grey,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
