import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
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
                // Разрешаем переход на вкладку tr(context, "Главная", tr(context, "Басты бет", "Басты бет")) (0) и tr(context, "Профиль", "Профиль") (3) всегда
                // Для вкладок tr(context, "Карта", "Карта") (1) и tr(context, "QR", "QR") (2) проверяем наличие активной смены
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
                      SnackBar(
                        content: Text(tr(context, 'Сначала откройте рабочую смену', tr(context, 'Алдымен жұмыс ауысымын ашыңыз', 'Алдымен жұмыс ауысымын ашыңыз'))),
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
                  label: tr(context, 'Главная', tr(context, 'Басты бет', 'Басты бет')),
                ),
                BottomNavigationBarItem(
                  icon: Opacity(
                    opacity: hasActiveShift ? 1.0 : 0.5,
                    child: _buildIcon(AppIcons.map, AppIcons.map2, 1),
                  ),
                  label: tr(context, 'Карта', 'Карта'),
                ),
                BottomNavigationBarItem(
                  icon: Opacity(
                    opacity: hasActiveShift ? 1.0 : 0.5,
                    child: _buildIcon(AppIcons.qr, AppIcons.qr2, 2),
                  ),
                  label: tr(context, 'QR', 'QR'),
                ),
                BottomNavigationBarItem(
                  icon: _buildIcon(AppIcons.profile, AppIcons.profile2, 3),
                  label: tr(context, 'Профиль', 'Профиль'),
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
