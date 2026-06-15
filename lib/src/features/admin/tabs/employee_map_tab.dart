import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as flutter_secure_storage;
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:micro_mobility_app/src/core/utils/map_app_constants.dart'
    show AppConstants;
import 'package:micro_mobility_app/src/features/admin/tabs/map_employee_map/employee_map_logic.dart';
import 'package:micro_mobility_app/src/features/app/models/location.dart';

class EmployeeMapTab extends StatefulWidget {
  const EmployeeMapTab({super.key});

  @override
  State<EmployeeMapTab> createState() => _EmployeeMapTabState();
}

class _EmployeeMapTabState extends State<EmployeeMapTab>
    with AutomaticKeepAliveClientMixin {
  late final EmployeeMapLogic _logic;
  bool _disposed = false;
  late final DraggableScrollableController _sheetController;
  EmployeeLocation? _selectedHistoryPoint;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _logic = EmployeeMapLogic();
    _logic.onStateChanged = () {
      if (!_disposed && mounted) setState(() {});
    };
    _logic.init();
  }

  @override
  void dispose() {
    _disposed = true;
    _sheetController.dispose();
    _logic.dispose();
    super.dispose();
  }

  void _toggleSheet() {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size > 0.3) {
      _sheetController.animateTo(0.15,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    } else {
      _sheetController.animateTo(0.40,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
  }

  void _showHistory(EmployeeLocation emp) async {
    if (_disposed || !mounted) return;

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

  Color _getColorForUser(String userId) {
    final int hash = userId.hashCode;
    final List<Color> colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.black,
      Colors.brown,
      Colors.deepOrange,
      Colors.lime,
      Colors.blueGrey,
      Colors.deepPurple,
      const Color(0xFFE91E63), // Magenta
      const Color(0xFF004D40), // Dark Teal
      const Color(0xFF3E2723), // Dark Brown
      const Color(0xFFF50057), // Neon Pink
    ];
    return colors[hash.abs() % colors.length];
  }

  Widget _buildModernMarker(EmployeeLocation emp, bool isOnline) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (isOnline) const _PulseMarker(),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: isOnline ? Colors.white : Colors.grey, width: 2.5),
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
                    errorBuilder: (context, error, stackTrace) =>
                        _buildFallbackAvatar(battery: emp.battery, label: emp.name),
                  )
                : _buildFallbackAvatar(battery: emp.battery, label: emp.name),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: _buildStatusDot(isOnline),
        ),
      ],
    );
  }

  Widget _buildStatusDot(bool isOnline) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isOnline ? Colors.green : Colors.grey,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _buildFallbackAvatar({double? battery, Color? color, String? label}) {
    return Container(
      color: color ?? Colors.green[700],
      child: Center(
        child: Text(
          (label?.isNotEmpty == true)
              ? label!.substring(0, 1).toUpperCase()
              : '?',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_logic.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.green));
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
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
              onTap: (tapPosition, point) {
                if (_logic.isHistoryMode && _logic.selectedHistoryPoints.isNotEmpty) {
                  EmployeeLocation? closestPoint;
                  double minDistance = double.infinity;
                  const distanceParams = Distance();

                  for (var p in _logic.selectedHistoryPoints) {
                    final dist = distanceParams.as(LengthUnit.Meter, point, p.position);
                    if (dist < minDistance) {
                      minDistance = dist;
                      closestPoint = p;
                    }
                  }

                  if (closestPoint != null && minDistance < 1500) { // В пределах 1.5 км от места нажатия
                    setState(() {
                      _selectedHistoryPoint = closestPoint;
                    });
                  }
                } else if (!_logic.isHistoryMode && _logic.selectedLiveEmployee != null) {
                  setState(() {
                    _logic.selectedLiveEmployee = null;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.mapUrl,
                subdomains: AppConstants.mapSubdomains,
                userAgentPackageName: AppConstants.userAgentPackageName,
                retinaMode: RetinaMode.isHighDensity(context),
                tileProvider: _logic.tileProvider,
              ),
              if (_logic.geoJsonParser.polygons.isNotEmpty &&
                  _logic.showRestrictedZones)
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
              if (_logic.geoJsonParser.polylines.isNotEmpty &&
                  _logic.showBoundaries)
                PolylineLayer(
                  polylines: _logic.geoJsonParser.polylines.map((polyline) {
                    return Polyline(
                      points: polyline.points,
                      color: Colors.blue.withOpacity(0.6),
                      strokeWidth: 3,
                    );
                  }).toList(),
                ),

              // Треки перемещений активных сотрудников
              if (!_logic.isHistoryMode)
                PolylineLayer(
                  polylines: _logic.activeEmployeesPaths.entries.where((entry) {
                    if (_logic.showRoutes) return true;
                    if (_logic.selectedLiveEmployee?.userId == entry.key) return true;
                    return false;
                  }).map((entry) {
                    final userId = entry.key;
                    final points = entry.value;
                    final isSelected = _logic.selectedLiveEmployee?.userId == userId;
                    final color = _getColorForUser(userId);
                    return Polyline(
                      points: points,
                      color: isSelected ? color.withOpacity(0.8) : color.withOpacity(0.4),
                      strokeWidth: isSelected ? 5.0 : 3.0,
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
              if (_logic.selectedEmployeeHistory.isNotEmpty)
                MarkerLayer(
                  markers: [
                    if (_selectedHistoryPoint != null)
                      Marker(
                        point: _selectedHistoryPoint!.position,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                        ),
                      ),
                    // Старт (Зеленый)
                    Marker(
                      point: _logic.selectedEmployeeHistory.first,
                      width: 100,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Container(
                        decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                            border: Border.all(color: Colors.white, width: 2)),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('СТАРТ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    // Финиш (Красный)
                    Marker(
                      point: _logic.selectedEmployeeHistory.last,
                      width: 100,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Container(
                        decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                            border: Border.all(color: Colors.white, width: 2)),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sports_score, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('ФИНИШ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              if (_logic.showMarkers && _logic.geoJsonParser.markers.isNotEmpty)
                MarkerLayer(markers: _logic.geoJsonParser.markers),
              MarkerLayer(
                markers: _logic.employeeLocations.map((emp) {
                  final isOnline = _logic.isEmployeeOnline(emp.timestamp);
                  return Marker(
                    point: emp.position,
                    width: 70,
                    height: 70,
                    child: GestureDetector(
                      onTap: () => _logic.zoomToEmployee(emp),
                      onLongPress: () => _showHistory(emp),
                      child: _buildModernMarker(emp, isOnline),
                    ),
                  );
                }).toList(),
              ),
              if (_logic.currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _logic.currentLocation!,
                      width: 50,
                      height: 50,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue.withOpacity(0.3),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: ClipOval(
                          child: _logic.currentUserAvatarUrl != null
                              ? Image.network(
                                  _logic.currentUserAvatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.my_location, color: Colors.blue),
                                )
                              : const Icon(Icons.my_location,
                                  color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildLiveBadge(),
                const SizedBox(height: 12),
                _buildMapControl(
                  icon: Icons.layers_outlined,
                  onTap: () => _showLayerSettings(context),
                ),
                const SizedBox(height: 8),
                _buildMapControl(
                  icon: Icons.my_location,
                  onTap: () {
                    if (_logic.currentLocation != null) {
                      _logic.mapController.move(_logic.currentLocation!, 15.0);
                    }
                  },
                ),
              ],
            ),
          ),

          Positioned(
            top: 20,
            left: 20,
            child: _buildDateSelector(),
          ),
          if (_logic.selectedLiveEmployee == null && _logic.selectedShift == null)
            Positioned(
              bottom: 40,
              left: 30,
              right: 30,
              child: GestureDetector(
                onTap: () => _showEmployeeListModal(context, isDarkMode),
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 24,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                      )
                    ],
                    border: Border.all(color: Colors.green.withOpacity(0.4), width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.people_alt, color: Colors.green, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _logic.isHistoryMode
                            ? 'Смены (${_logic.historyShifts.length})'
                            : 'Сотрудники (${_logic.employeeLocations.length})',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey, size: 24),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Shift Details UI (Overlay)
          if (_logic.selectedShift != null) _buildShiftDetailPanel(isDarkMode),
          if (_logic.selectedLiveEmployee != null && !_logic.isHistoryMode) _buildLiveEmployeePanel(isDarkMode),
        ],
      ),
    );
  }

  Future<void> _exportGeoJson() async {
    if (_logic.selectedHistoryPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет данных для экспорта')),
      );
      return;
    }

    final features = _logic.selectedHistoryPoints.map((point) {
      return {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [point.position.longitude, point.position.latitude]
        },
        "properties": {
          "speed": point.speed ?? 0.0,
          "battery": point.battery ?? 0,
          "time": point.timestamp.toIso8601String(),
        }
      };
    }).toList();

    features.add({
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": _logic.selectedHistoryPoints.map((p) => [p.position.longitude, p.position.latitude]).toList()
      },
      "properties": {
        "name": "Route",
        "stroke": "#FF0000",
        "stroke-width": 3
      }
    });

    final geoJson = {
      "type": "FeatureCollection",
      "features": features,
    };

    final directory = await getTemporaryDirectory();
    final filename = 'route_${_logic.selectedShift?.username ?? "export"}.geojson';
    final file = File('${directory.path}/$filename');
    await file.writeAsString(jsonEncode(geoJson));

    await share_plus.Share.shareXFiles([share_plus.XFile(file.path)], text: 'Экспорт маршрута в GeoJSON');
  }



  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('LIVE',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildMapControl(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)
          ],
        ),
        child: Icon(icon, color: Colors.green[800], size: 24),
      ),
    );
  }

  Widget _buildEmployeeListItem(EmployeeLocation emp, bool isDarkMode) {
    final isOnline = _logic.isEmployeeOnline(emp.timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          _logic.zoomToEmployee(emp);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _buildModernMarker(emp, isOnline),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emp.name ?? 'ID ${emp.userId}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(isOnline ? Icons.wifi : Icons.wifi_off, 
                          size: 14, color: isOnline ? Colors.green : Colors.grey),
                        const SizedBox(width: 4),
                        Text(isOnline ? 'В сети' : 'Был(а): ${DateFormat('HH:mm').format(emp.timestamp.toLocal())}',
                            style: TextStyle(color: isOnline ? Colors.green : Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (emp.battery != null)
                    Row(
                      children: [
                        Icon(
                            emp.battery! > 20
                                ? Icons.battery_full
                                : Icons.battery_alert,
                            size: 14,
                            color:
                                emp.battery! > 20 ? Colors.green : Colors.red),
                        const SizedBox(width: 4),
                        Text('${emp.battery!.toInt()}%',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  IconButton(
                    icon: Icon(Icons.history,
                        color: _logic.selectedEmployeeId == emp.userId
                            ? Colors.orange
                            : Colors.grey),
                    onPressed: () {
                      Navigator.pop(context);
                      _showHistory(emp);
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final isToday = _logic.selectedDate.year == now.year &&
        _logic.selectedDate.month == now.month &&
        _logic.selectedDate.day == now.day;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today,
              size: 16, color: isToday ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _logic.selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (date != null) _logic.setDate(date);
            },
            child: Text(
              isToday
                  ? 'Сегодня'
                  : DateFormat('dd.MM.yyyy').format(_logic.selectedDate),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isToday ? Colors.green : Colors.orange[800],
              ),
            ),
          ),
          if (!isToday) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _logic.setDate(DateTime.now()),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveList(ScrollController scrollController, bool isDarkMode) {
    if (_logic.employeeLocations.isEmpty) {
      return const Center(child: Text('Нет активных сотрудников'));
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      itemCount: _logic.employeeLocations.length,
      itemBuilder: (context, index) {
        return _buildEmployeeListItem(
            _logic.employeeLocations[index], isDarkMode);
      },
    );
  }

  Widget _buildHistoryList(ScrollController scrollController, bool isDarkMode) {
    if (_logic.isHistoryLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.orange));
    }
    if (_logic.historyShifts.isEmpty) {
      return const Center(child: Text('За этот день смен не найдено'));
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      itemCount: _logic.historyShifts.length,
      itemBuilder: (context, index) {
        final shift = _logic.historyShifts[index];
        final isSelected = _logic.selectedShift?.id == shift.id;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              _logic.selectShift(shift);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.orange.withOpacity(0.1)
                    : (isDarkMode
                        ? Colors.white.withOpacity(0.05)
                        : Colors.grey[50]),
                borderRadius: BorderRadius.circular(20),
                border: isSelected
                    ? Border.all(color: Colors.orange.withOpacity(0.3))
                    : null,
              ),
              child: Row(
                children: [
                  _buildShiftSelfieMini(shift.selfie),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shift.username,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          '${DateFormat('HH:mm').format((shift.startTime ?? DateTime.now()).toLocal())} - ${shift.endTime != null ? DateFormat('HH:mm').format(shift.endTime!.toLocal()) : "..."}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEmployeeListModal(BuildContext context, bool isDarkMode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _logic.isHistoryMode
                              ? 'Архив смен (${_logic.historyShifts.length})'
                              : 'Сотрудники (${_logic.employeeLocations.length})',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        if (!_logic.isHistoryMode)
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.green),
                            onPressed: () {
                              _logic.fetchEmployeeLocations();
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _logic.isHistoryMode
                        ? _buildHistoryList(controller, isDarkMode)
                        : _buildLiveList(controller, isDarkMode),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShiftDetailPanel(bool isDarkMode) {
    final shift = _logic.selectedShift!;
    
    double totalDistanceMeters = 0;
    if (_logic.selectedHistoryPoints.length > 1) {
      const distanceCalc = Distance();
      for (int i = 0; i < _logic.selectedHistoryPoints.length - 1; i++) {
        totalDistanceMeters += distanceCalc.as(
          LengthUnit.Meter,
          _logic.selectedHistoryPoints[i].position,
          _logic.selectedHistoryPoints[i+1].position
        );
      }
    }
    
    final distanceText = totalDistanceMeters > 1000 
        ? '${(totalDistanceMeters / 1000).toStringAsFixed(2)} км'
        : '${totalDistanceMeters.toStringAsFixed(0)} м';

    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 2)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // User info row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _showFullImage(shift.selfie),
                    child: Hero(
                      tag: 'selfie_${shift.id}',
                      child: _buildShiftSelfieMini(shift.selfie, size: 50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shift.username,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${shift.position} • ${shift.zone}',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('HH:mm').format((shift.startTime ?? DateTime.now()).toLocal())} - ${shift.endTime != null ? DateFormat('HH:mm').format(shift.endTime!.toLocal()) : "В процессе"}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        if (_logic.selectedHistoryPoints.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.route, size: 12, color: Colors.blueAccent),
                              const SizedBox(width: 4),
                              Text('Пройдено: $distanceText', 
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (_logic.selectedHistoryPoints.isNotEmpty)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.file_download_outlined, color: Colors.blueAccent, size: 24),
                          onPressed: _exportGeoJson,
                        ),
                      const SizedBox(width: 12),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close, size: 24),
                        onPressed: () {
                          _logic.selectedShift = null;
                          _logic.selectedEmployeeHistory = [];
                          _selectedHistoryPoint = null;
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
              
              // Timeline and point info
              if (_logic.selectedHistoryPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (_selectedHistoryPoint != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.blueAccent),
                          const SizedBox(width: 4),
                          Text(DateFormat('HH:mm:ss').format(_selectedHistoryPoint!.timestamp.toLocal()),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.speed, size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text('${((_selectedHistoryPoint!.speed ?? 0.0) * 3.6).toStringAsFixed(1)} км/ч',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      if (_selectedHistoryPoint!.battery != null)
                        Row(
                          children: [
                            Icon(_selectedHistoryPoint!.battery! > 20 ? Icons.battery_full : Icons.battery_alert,
                                size: 14, color: _selectedHistoryPoint!.battery! > 20 ? Colors.green : Colors.red),
                            const SizedBox(width: 4),
                            Text('${_selectedHistoryPoint!.battery!.toInt()}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                    ],
                  ),
                ],
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Colors.blueAccent,
                    inactiveTrackColor: Colors.grey.withOpacity(0.3),
                    thumbColor: Colors.blueAccent,
                  ),
                  child: Slider(
                    value: _selectedHistoryPoint == null 
                      ? 0.0 
                      : _logic.selectedHistoryPoints.indexOf(_selectedHistoryPoint!).toDouble().clamp(0.0, _logic.selectedHistoryPoints.length.toDouble() - 1),
                    min: 0,
                    max: (_logic.selectedHistoryPoints.length - 1).toDouble(),
                    onChanged: (val) {
                      final idx = val.toInt();
                      if (idx >= 0 && idx < _logic.selectedHistoryPoints.length) {
                        setState(() {
                          _selectedHistoryPoint = _logic.selectedHistoryPoints[idx];
                        });
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveEmployeePanel(bool isDarkMode) {
    final emp = _logic.selectedLiveEmployee!;
    final isOnline = _logic.isEmployeeOnline(emp.timestamp);
    
    return Positioned(
      bottom: 20, // Опускаем вниз, так как BottomSheet скрыт
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 2)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _buildModernMarker(emp, isOnline),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp.name ?? 'ID ${emp.userId}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(isOnline ? Icons.wifi : Icons.wifi_off, 
                            size: 14, color: isOnline ? Colors.green : Colors.grey),
                          const SizedBox(width: 4),
                          Text(isOnline ? 'В сети' : 'Был(а): ${DateFormat('HH:mm').format(emp.timestamp.toLocal())}',
                              style: TextStyle(color: isOnline ? Colors.green : Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (emp.battery != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(emp.battery! > 20 ? Icons.battery_full : Icons.battery_alert,
                                size: 14, color: emp.battery! > 20 ? Colors.green : Colors.red),
                            const SizedBox(width: 4),
                            Text('${emp.battery!.toInt()}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _logic.selectedLiveEmployee = null;
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showPersonalNotificationDialog(emp.userId, emp.name),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Отправить пуш', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  foregroundColor: Colors.blueAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonalNotificationDialog(String userIdStr, String? userName) {
    final TextEditingController msgController = TextEditingController();
    bool isSending = false;
    final userId = int.tryParse(userIdStr) ?? 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.send_rounded, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Сообщение для ${userName ?? 'ID $userId'}', style: const TextStyle(fontSize: 16))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: msgController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Почему стоим на месте?',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isSending ? null : () async {
                    final msg = msgController.text.trim();
                    if (msg.isEmpty) return;

                    setDialogState(() => isSending = true);
                    try {
                      final token = await const flutter_secure_storage.FlutterSecureStorage().read(key: 'jwt_token');
                      if (token != null) {
                        await ApiService().sendAdminNotification(token, msg, userId: userId);
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('Сообщение отправлено!'), backgroundColor: Colors.green),
                          );
                        }
                      }
                    } catch (e) {
                      setDialogState(() => isSending = false);
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                  child: isSending 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Отправить'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildShiftSelfieMini(String? selfie, {double size = 48}) {
    if (selfie == null || selfie.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: Colors.grey[300], borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.person, color: Colors.white),
      );
    }

    String url = selfie;
    if (!url.startsWith('http')) {
      if (url.startsWith('/')) url = url.substring(1);
      url = '${AppConfig.backendHost}/$url';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[300],
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Colors.white),
        ),
      ),
    );
  }

  void _showFullImage(String? selfie) {
    if (selfie == null || selfie.isEmpty) return;

    String url = selfie;
    if (!url.startsWith('http')) {
      if (url.startsWith('/')) url = url.substring(1);
      url = '${AppConfig.backendHost}/$url';
    }

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.error, color: Colors.white, size: 50),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLayerSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Настройки слоев',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 24),
              _buildLayerToggle('Ограниченные зоны', _logic.showRestrictedZones,
                  (v) {
                _logic.toggleLayer('restricted');
                setModalState(() {});
                setState(() {});
              }),
              _buildLayerToggle('Границы города', _logic.showBoundaries, (v) {
                _logic.toggleLayer('boundaries');
                setModalState(() {});
                setState(() {});
              }),
              _buildLayerToggle('Маркеры GeoJSON', _logic.showMarkers, (v) {
                _logic.toggleLayer('markers');
                setModalState(() {});
                setState(() {});
              }),
              _buildLayerToggle('Маршруты сотрудников', _logic.showRoutes, (v) {
                _logic.toggleLayer('routes');
                setModalState(() {});
                setState(() {});
              }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayerToggle(String title, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      value: value,
      onChanged: onChanged,
      activeColor: Colors.green,
    );
  }
}

class _PulseMarker extends StatefulWidget {
  const _PulseMarker();

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 44 + (24 * _controller.value),
          height: 44 + (24 * _controller.value),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withOpacity(1.0 - _controller.value),
          ),
        );
      },
    );
  }
}
