// lib/screens/admin/shift_list_screen.dart
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/screens/admin/shift_monitoring_screen.dart';
import 'package:micro_mobility_app/screens/admin/shift_history_screen.dart';

class ShiftListScreen extends StatelessWidget {
  const ShiftListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        TabBar(
          tabs: [
            Tab(text: 'Активные', icon: Icon(Icons.play_arrow)),
            Tab(text: 'История', icon: Icon(Icons.history)),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              ShiftMonitoringScreen(), // Активные
              ShiftHistoryScreen(), // Завершённые
            ],
          ),
        ),
      ],
    );
  }
}
