import 'package:flutter/material.dart';
import 'tabs/map_upload_tab.dart';
import 'tabs/zone_management_tab.dart';
import 'tabs/employee_map_tab.dart';

class MapAndZoneScreen extends StatefulWidget {
  const MapAndZoneScreen({super.key});

  @override
  State<MapAndZoneScreen> createState() => _MapAndZoneScreenState();
}

class _MapAndZoneScreenState extends State<MapAndZoneScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(icon: Icon(Icons.map), text: 'Карты'),
              Tab(icon: Icon(Icons.grid_3x3), text: 'Зоны'),
              Tab(icon: Icon(Icons.location_on), text: 'Онлайн'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                MapUploadTab(),
                ZoneManagementTab(),
                EmployeeMapTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
