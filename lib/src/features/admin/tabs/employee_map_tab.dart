import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/src/features/app/models/location.dart';
import 'package:micro_mobility_app/src/core/utils/map_app_constants.dart'
    show AppConstants;
import 'package:micro_mobility_app/src/features/admin/tabs/map_employee_map/employee_map_logic.dart';

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

    // Открыть диалог выбора диапазона
    final range = await _showDateRangePicker(context);
    if (range == null) return;

    await _logic.loadEmployeeHistory(emp.userId, range: range);
    if (_logic.selectedEmployeeHistory.isNotEmpty) {
      _logic.mapController.move(_logic.selectedEmployeeHistory.first, 13.0);
    }
    if (mounted && _logic.selectedEmployeeHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История не найдена')),
      );
    }
  }

  Future<DateTimeRange?> _showDateRangePicker(BuildContext context) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1);

    // Безопасно задаём end: не больше сегодняшнего дня
    final initialStart = DateTime(now.year, now.month, now.day);
    final initialEnd = initialStart.add(const Duration(days: 1));
    final safeInitialEnd = initialEnd.isAfter(now) ? now : initialEnd;

    final initialDateRange = DateTimeRange(
      start: initialStart,
      end: safeInitialEnd,
    );

    return await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: now,
      initialDateRange: initialDateRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: Colors.green,
            onPrimary: Colors.white,
            surface: Theme.of(context).cardColor,
            onSurface: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          appBarTheme: Theme.of(context).appBarTheme.copyWith(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
  }

  Widget _buildFallbackAvatar({double? battery, Color? color, String? label}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color ?? Colors.green[700],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (label != null)
             Text(label.substring(0, 1).toUpperCase(), 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          else
            const Icon(Icons.person, color: Colors.white, size: 24),
          if (battery != null)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: battery > 20 ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text(
                  '${battery.toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
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
                    urlTemplate: AppConstants.mapUrl,
                    subdomains: AppConstants.mapSubdomains,
                    userAgentPackageName: AppConstants.userAgentPackageName,
                    retinaMode: RetinaMode.isHighDensity(context),
                    tileProvider: _logic.tileProvider,
                  ),
                  if (_logic.geoJsonParser.polygons.isNotEmpty && _logic.showRestrictedZones)
                    PolygonLayer(
                      polygons: _logic.geoJsonParser.polygons.map((polygon) {
                        return Polygon(
                          points: polygon.points,
                          borderColor: Colors.red,
                          color: Colors.red.withOpacity(0.12),
                          borderStrokeWidth: 2.0,
                        );
                      }).toList(),
                    ),
                  if (_logic.geoJsonParser.polylines.isNotEmpty && _logic.showBoundaries)
                    PolylineLayer(
                      polylines: _logic.geoJsonParser.polylines.map((polyline) {
                        return Polyline(
                          points: polyline.points,
                          color: Colors.blue.withOpacity(0.6),
                          strokeWidth: 3,
                        );
                      }).toList(),
                    ),
                  if (_logic.selectedEmployeeHistory.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _logic.selectedEmployeeHistory,
                          color: Colors.red,
                          strokeWidth: 4.0,
                        ),
                      ],
                    ),
                  if (_logic.geoJsonParser.markers.isNotEmpty)
                    MarkerLayer(markers: _logic.geoJsonParser.markers),
                  if (_logic.currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _logic.currentLocation!,
                          width: 50,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _logic.currentUserAvatarUrl != null
                                  ? Image.network(
                                      _logic.currentUserAvatarUrl!,
                                      fit: BoxFit.cover,
                                      width: 48,
                                      height: 48,
                                      errorBuilder: (context, error, stackTrace) =>
                                          _buildFallbackAvatar(
                                              color: Colors.blue[700]),
                                    )
                                  : _buildFallbackAvatar(color: Colors.blue[700]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_logic.employeeLocations.isNotEmpty)
                    MarkerLayer(
                      markers: _logic.employeeLocations.map((emp) {
                        return Marker(
                          point: emp.position,
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => _showHistory(emp),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
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
                                                    battery: emp.battery,
                                                    label: emp.name),
                                      )
                                    : _buildFallbackAvatar(
                                        battery: emp.battery, label: emp.name),
                              ),
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
                      subtitle: _logic.selectedHistoryRange != null
                          ? Text(
                              'С ${_logic.selectedHistoryRange!.start.day}.${_logic.selectedHistoryRange!.start.month} по ${_logic.selectedHistoryRange!.end.day}.${_logic.selectedHistoryRange!.end.month}')
                          : null,
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
