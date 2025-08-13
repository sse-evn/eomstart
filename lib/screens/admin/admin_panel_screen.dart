// lib/screens/admin/admin_panel_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/screens/admin/tasks_screen.dart';
import 'package:micro_mobility_app/screens/admin/map_upload_screen.dart';
import 'package:micro_mobility_app/screens/admin/shift_monitoring_screen.dart';
import 'package:micro_mobility_app/widgets/admin_users_list.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart'; // Убедись, что путь верный

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

  @override
  Widget build(BuildContext context) {
    // Динамически определяем тело в зависимости от индекса
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
            // После загрузки переходим на экран карты с этим файлом
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
        backgroundColor: Colors.blue[700],
        actions: const [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: null, // Позже можешь добавить логику обновления
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: currentBody,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Пользователи',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Задания',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Карта',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'Смены',
          ),
        ],
      ),
    );
  }
}
