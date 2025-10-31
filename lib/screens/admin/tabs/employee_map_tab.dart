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
  bool _disposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _logic = EmployeeMapLogic();
    _logic.onStateChanged = () {
      if (!_disposed && mounted) setState(() {});
    };
    _logic.init();
  }

  @override
  void dispose() {
    _disposed = true;
    _logic.dispose();
    super.dispose();
  }

  void _showHistory(EmployeeLocation emp) async {
    if (_disposed || !mounted) return;
    if (_logic.selectedEmployeeId == emp.userId) {
      _logic.clearHistory();
    } else {
      await _logic.loadEmployeeHistory(emp.userId);
      if (_logic.selectedEmployeeHistory.isNotEmpty) {
        _logic.mapController.move(_logic.selectedEmployeeHistory.first, 13.0);
      }
    }
    if (mounted && _logic.selectedEmployeeHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История не найдена')),
      );
    }
  }

  Widget _buildFallbackAvatar({double? battery, Color? color}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color ?? Colors.green[700],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.person, color: Colors.white, size: 20),
          if (battery != null)
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
                  '${battery.toInt()}%',
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_logic.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
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
                    // subdomains: AppConstants.cartoDbSubdomains,
                    retinaMode: RetinaMode.isHighDensity(context),
                  ),
                  if (_logic.selectedEmployeeHistory.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _logic.selectedEmployeeHistory,
                          color: Colors.blueAccent,
                          strokeWidth: 4.0,
                        ),
                      ],
                    ),
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
                                            _buildFallbackAvatar(
                                                color: Colors.blue[700]),
                                  )
                                : _buildFallbackAvatar(color: Colors.blue[700]),
                          ),
                        ),
                      ],
                    ),
                  if (_logic.employeeLocations.isNotEmpty)
                    MarkerLayer(
                      markers: _logic.employeeLocations.map((emp) {
                        return Marker(
                          point: emp.position,
                          width: 40,
                          height: 40,
                          child: GestureDetector(
                            onTap: () => _showHistory(emp),
                            child: ClipOval(
                              child: emp.avatarUrl != null
                                  ? Image.network(
                                      emp.avatarUrl!,
                                      fit: BoxFit.cover,
                                      width: 40,
                                      height: 40,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildFallbackAvatar(
                                                  battery: emp.battery),
                                    )
                                  : _buildFallbackAvatar(battery: emp.battery),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
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
              if (_logic.selectedEmployeeId != null)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                          'История: ${_logic.selectedEmployeeName ?? _logic.selectedEmployeeId}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _logic.clearHistory,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
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
                        title: Text(emp.name ?? 'Сотрудник ${emp.userId}'),
                        subtitle: emp.battery != null
                            ? Text('Батарея: ${emp.battery!.toInt()}%')
                            : null,
                        trailing: Icon(
                          Icons.history,
                          color: _logic.selectedEmployeeId == emp.userId
                              ? Colors.orange
                              : Colors.grey,
                        ),
                        onTap: () => _showHistory(emp),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
