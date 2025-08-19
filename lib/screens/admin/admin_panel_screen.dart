// lib/screens/admin/admin_panel_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/config.dart';
import 'package:micro_mobility_app/screens/admin/tasks_screen.dart';
import 'package:micro_mobility_app/screens/admin/map_upload_screen.dart';
import 'package:micro_mobility_app/screens/admin/shift_monitoring_screen.dart';
import 'package:micro_mobility_app/widgets/admin_users_list.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';
import 'package:micro_mobility_app/screens/generatorshift.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _currentIndex = 0;

  final List<String> _titles = [
    'Пользователи',
    'Генератор смен',
    'Карта',
    'Смены',
  ];

  final List<GlobalKey<RefreshIndicatorState>> _refreshKeys = [
    GlobalKey<RefreshIndicatorState>(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ✅ ИСПРАВЛЕНО: используем colorScheme.primary
    final primaryColor = theme.colorScheme.primary;

    Widget currentBody;

    switch (_currentIndex) {
      case 0:
        currentBody = const AdminUsersList();
        break;
      case 1:
        currentBody = const Generatorshift();
        break;
      case 2:
        currentBody = MapUploadScreen(
          onGeoJsonLoaded: (File file) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MapScreen(customGeoJsonFile: file),
              ),
            );
          },
        );
        break;
      case 3:
        currentBody = const ShiftMonitoringScreen();
        break;
      default:
        currentBody = const AdminUsersList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: primaryColor, // ✅ Теперь точно зелёный
        elevation: 4,
        leading: null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_currentIndex == 0 && _refreshKeys[0].currentState != null) {
                _refreshKeys[0].currentState!.show();
              }
            },
            tooltip: 'Обновить',
          ),
          PopupMenuButton(
            icon:
                const Icon(Icons.info_outline, size: 18, color: Colors.white70),
            tooltip: 'Информация о среде',
            onSelected: (value) {
              if (value == 'env') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppConfig.environmentInfo)),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'env', child: Text('Показать среду')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[50]!,
              Colors.white,
            ],
          ),
        ),
        child: currentBody,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: primaryColor, // ✅ Цвет теперь из схемы
          unselectedItemColor: Colors.grey[600],
          backgroundColor: Colors.white,
          elevation: 0,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Пользователи',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today),
              label: 'Генератор смен',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Карта',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.access_time_outlined),
              activeIcon: Icon(Icons.access_time),
              label: 'Смены',
            ),
          ],
        ),
      ),
    );
  }
}
