import 'dart:io';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/config.dart';
import 'package:micro_mobility_app/screens/admin/shift_history_screen.dart';
import 'package:micro_mobility_app/screens/admin/shift_monitoring_screen.dart';
import 'package:micro_mobility_app/screens/admin/tasks_screen.dart';
import 'package:micro_mobility_app/screens/admin/map_upload_screen.dart';
import 'package:micro_mobility_app/screens/generator_shifts.dart';
import 'package:micro_mobility_app/widgets/admin_users_list.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  final List<String> _titles = [
    'Пользователи',
    'Генератор смен',
    'Карта',
    'Смены',
  ];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    Widget currentBody;

    switch (_currentIndex) {
      case 0:
        currentBody = const AdminUsersList();
        break;
      case 1:
        currentBody = const GeneratorShiftScreen();
        break;
      case 2:
        currentBody = MapAndZoneScreen();
        // onGeoJsonLoaded: (File file) {
        //   Navigator.pushReplacement(
        //       context,
        //       MaterialPageRoute(
        //         builder: (context) => MapScreen(customGeoJsonFile: file),
        //       ),
        //     );
        //   },
        // );
        break;
      case 3:
        currentBody = Column(
          children: [
            Material(
              color: primaryColor,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Активные', icon: Icon(Icons.play_arrow, size: 18)),
                  Tab(text: 'История', icon: Icon(Icons.history, size: 18)),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: Colors.white, width: 2.0),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  ShiftMonitoringScreen(),
                  ShiftHistoryScreen(),
                ],
              ),
            ),
          ],
        );
        break;
      default:
        currentBody = const AdminUsersList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: primaryColor,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final state1 =
                  context.findAncestorStateOfType<ShiftMonitoringScreenState>();
              final state2 =
                  context.findAncestorStateOfType<ShiftHistoryScreenState>();
              state1?.refresh();
              state2?.refresh();
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
            colors: [Colors.grey[50]!, Colors.white],
          ),
        ),
        child: currentBody,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey[600],
        backgroundColor: Colors.white,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Пользователи'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today),
              label: 'Генератор смен'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Карта'),
          BottomNavigationBarItem(
              icon: Icon(Icons.access_time_outlined),
              activeIcon: Icon(Icons.access_time),
              label: 'Смены'),
        ],
      ),
    );
  }
}
