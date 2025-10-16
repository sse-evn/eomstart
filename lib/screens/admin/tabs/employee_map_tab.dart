import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_logic.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Карта
        Expanded(
          flex: 3,
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
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue[700],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  // Live-позиции сотрудников (геотрекинг)
                  if (_logic.employeeLocations.isNotEmpty)
                    MarkerLayer(
                      markers: _logic.employeeLocations.map((emp) {
                        return Marker(
                          point: emp.position,
                          width: 36,
                          height: 36,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.person,
                                color: Colors.green[700],
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
                        );
                      }).toList(),
                    ),
                ],
              ),

              // Индикатор подключения (опционально, можно убрать)
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

        // Пустой placeholder для списка (если не нужен — удалите)
        Expanded(
          flex: 2,
          child: Card(
            margin: const EdgeInsets.all(8),
            child: Center(
              child: Text(
                'Всего сотрудников: ${_logic.employeeLocations.length}',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
