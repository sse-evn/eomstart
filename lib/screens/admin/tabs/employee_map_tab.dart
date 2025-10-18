import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/utils/map_app_constants.dart'
    show AppConstants;
import 'package:micro_mobility_app/screens/admin/tabs/map_employee_map/employee_map_logic.dart';

class EmployeeMapTab extends StatefulWidget {
  const EmployeeMapTab({super.key});

  @override
  State<EmployeeMapTab> createState() => _EmployeeMapTabState();
}

class _EmployeeMapTabState extends State<EmployeeMapTab>
    with AutomaticKeepAliveClientMixin {
  late final EmployeeMapLogic _logic;
  bool _isInitialized = false;
  bool _disposed = false;
  int? _selectedEmployeeIndex;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _logic = EmployeeMapLogic();
    _logic.onStateChanged = () {
      if (!_disposed && mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    };
    _logic.init();
  }

  @override
  void dispose() {
    _disposed = true;
    _logic.dispose();
    super.dispose();
  }

  void _centerOnEmployee(EmployeeLocation emp) {
    if (_disposed || !mounted) return;
    _logic.mapController.move(emp.position, _logic.mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialized || _logic.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Карта
        Expanded(
          flex: 2,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _logic.mapController,
                options: MapOptions(
                  initialCenter:
                      _logic.currentLocation ?? const LatLng(43.2389, 76.8897),
                  initialZoom: 12.0,
                  minZoom: 5.0,
                  maxZoom: 18.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: AppConstants.cartoDbPositronUrl,
                    subdomains: AppConstants.cartoDbSubdomains,
                    retinaMode: RetinaMode.isHighDensity(context),
                  ),
                  // Текущая позиция пользователя
                  if (_logic.currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _logic.currentLocation!,
                          width: 48,
                          height: 48,
                          child: ClipOval(
                            child: _logic.currentUserAvatarUrl != null
                                ? Image.network(
                                    _logic.currentUserAvatarUrl!,
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                      color: Colors.blue[700],
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.blue[700],
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  // Маркеры сотрудников
                  if (_logic.employeeLocations.isNotEmpty)
                    MarkerLayer(
                      markers:
                          _logic.employeeLocations.asMap().entries.map((entry) {
                        final index = entry.key;
                        final emp = entry.value;
                        return Marker(
                          point: emp.position,
                          width: 36,
                          height: 36,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedEmployeeIndex = index;
                              });
                              _centerOnEmployee(emp);
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  Icons.person,
                                  color: _selectedEmployeeIndex == index
                                      ? Colors.orange
                                      : Colors.green[700],
                                  size: 32,
                                ),
                                if (emp.battery != null)
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${emp.battery!}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),

              // Индикатор подключения
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Live-трекинг',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Список сотрудников
        Expanded(
          flex: 1,
          child: _logic.employeeLocations.isEmpty
              ? const Center(child: Text('Нет данных о сотрудниках'))
              : ListView.builder(
                  itemCount: _logic.employeeLocations.length,
                  itemBuilder: (context, index) {
                    final emp = _logic.employeeLocations[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: ClipOval(
                          child: emp.avatarUrl != null
                              ? Image.network(
                                  emp.avatarUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                    width: 40,
                                    height: 40,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.person,
                                        color: Colors.grey),
                                  ),
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.person,
                                      color: Colors.grey),
                                ),
                        ),
                        title: Text('Сотрудник ${emp.userId}'),
                        subtitle: emp.battery != null
                            ? Text('Батарея: ${emp.battery!.toInt()}%')
                            : null,
                        trailing: Icon(
                          Icons.location_on,
                          color: Colors.green[700],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedEmployeeIndex = index;
                          });
                          _centerOnEmployee(emp);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
