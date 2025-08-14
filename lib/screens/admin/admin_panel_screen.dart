// lib/screens/admin/admin_panel_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/screens/admin/tasks_screen.dart';
import 'package:micro_mobility_app/screens/admin/map_upload_screen.dart';
import 'package:micro_mobility_app/screens/admin/shift_monitoring_screen.dart';
import 'package:micro_mobility_app/widgets/admin_users_list.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _currentIndex = 0;

  final List<String> _titles = [
    'Пользователи',
    'Задания',
    'Карта',
    'Смены',
  ];

  // Ключи для принудительного обновления вкладок (опционально)
  final List<GlobalKey<RefreshIndicatorState>> _refreshKeys = [
    GlobalKey<RefreshIndicatorState>(), // для вкладки "Пользователи"
    GlobalKey(), // Задания
    GlobalKey(), // Карта
    GlobalKey(), // Смены
  ];

  @override
  Widget build(BuildContext context) {
    Widget currentBody;

    switch (_currentIndex) {
      case 0:
        currentBody = const AdminUsersList();
        break;
      case 1:
        currentBody = const TasksScreen();
        break;
      case 2:
        currentBody = MapUploadScreen(
          onGeoJsonLoaded: (File file) {
            // После загрузки GeoJSON — переходим на экран карты
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
        title: Text(_titles[_currentIndex]),
        centerTitle: true,
        backgroundColor: const Color(0xFF388E3C),
        elevation: 4,
        leading: null, // УДАЛЯЕМ КНОПКУ "НАЗАД"
        actions: [
          // Кнопка обновления — вызывает pull-to-refresh на текущей вкладке
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Пример: вызываем обновление только для вкладки "Пользователи"
              if (_currentIndex == 0) {
                final key = _refreshKeys[0];
                if (key.currentState != null) {
                  key.currentState!.show();
                }
              }
              // Можно добавить обновление для других вкладок
            },
            tooltip: 'Обновить',
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
          selectedItemColor: Colors.green[700],
          unselectedItemColor: Colors.grey[600],
          backgroundColor: Colors.white,
          elevation: 0,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Пользователи',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment),
              label: 'Задания',
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
