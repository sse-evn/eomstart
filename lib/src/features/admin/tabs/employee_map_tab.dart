import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
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
                    errorBuilder: (_, __, ___) => _buildFallbackAvatar(battery: emp.battery, label: emp.name),
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
          (label?.isNotEmpty == true) ? label!.substring(0, 1).toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_logic.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.green));
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _logic.mapController,
            options: MapOptions(
              initialCenter: _logic.currentLocation ?? const LatLng(43.2389, 76.8897),
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
              if (_logic.selectedEmployeeHistory.isNotEmpty)
                MarkerLayer(
                  markers: [
                    // Старт (Зеленый)
                    Marker(
                      point: _logic.selectedEmployeeHistory.first,
                      width: 25,
                      height: 25,
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2))),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 15),
                      ),
                    ),
                    // Финиш (Красный)
                    Marker(
                      point: _logic.selectedEmployeeHistory.last,
                      width: 25,
                      height: 25,
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2))),
                        child: const Icon(Icons.stop, color: Colors.white, size: 15),
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
                      onTap: () => _showHistory(emp),
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
                              ? Image.network(_logic.currentUserAvatarUrl!, fit: BoxFit.cover)
                              : const Icon(Icons.my_location, color: Colors.blue),
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
          DraggableScrollableSheet(
            initialChildSize: 0.12,
            minChildSize: 0.08,
            maxChildSize: 0.6,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _logic.isHistoryMode
                                ? 'Архив смен (${_logic.historyShifts.length})'
                                : 'Сотрудники (${_logic.employeeLocations.length})',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          if (!_logic.isHistoryMode)
                            TextButton(
                              onPressed: _logic.fetchEmployeeLocations,
                              child: const Text('Обновить', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _logic.isHistoryMode
                          ? _buildHistoryList(scrollController, isDarkMode)
                          : _buildLiveList(scrollController, isDarkMode),
                    ),
                  ],
                ),
              );
            },
          ),

          // Shift Details UI (Overlay)
          if (_logic.selectedShift != null)
            _buildShiftDetailPanel(isDarkMode),
        ],
      ),
    );
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
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildMapControl({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
        ),
        child: Icon(icon, color: Colors.green[800], size: 24),
      ),
    );
  }

  Widget _buildHistoryPanel(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black87 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_logic.selectedEmployeeName ?? 'История', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_logic.selectedHistoryRange != null)
                   Text('${_logic.selectedHistoryRange!.start.day}.${_logic.selectedHistoryRange!.start.month} - ${_logic.selectedHistoryRange!.end.day}.${_logic.selectedHistoryRange!.end.month}', 
                        style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _logic.clearHistory),
        ],
      ),
    );
  }

  Widget _buildEmployeeListItem(EmployeeLocation emp, bool isDarkMode) {
    final isOnline = _logic.isEmployeeOnline(emp.timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _logic.zoomToEmployee(emp),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50],
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
                    Text(emp.name ?? 'ID ${emp.userId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(isOnline ? 'В сети' : 'Оффлайн (более 5 мин)', 
                         style: TextStyle(color: isOnline ? Colors.green : Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (emp.battery != null)
                    Row(
                      children: [
                        Icon(emp.battery! > 20 ? Icons.battery_full : Icons.battery_alert, size: 14, color: emp.battery! > 20 ? Colors.green : Colors.red),
                        const SizedBox(width: 4),
                        Text('${emp.battery!.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  IconButton(
                    icon: Icon(Icons.history, color: _logic.selectedEmployeeId == emp.userId ? Colors.orange : Colors.grey),
                    onPressed: () => _showHistory(emp),
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
          Icon(Icons.calendar_today, size: 16, color: isToday ? Colors.green : Colors.orange),
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
              isToday ? 'Сегодня' : DateFormat('dd.MM.yyyy').format(_logic.selectedDate),
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
        return _buildEmployeeListItem(_logic.employeeLocations[index], isDarkMode);
      },
    );
  }

  Widget _buildHistoryList(ScrollController scrollController, bool isDarkMode) {
    if (_logic.isHistoryLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
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
            onTap: () => _logic.selectShift(shift),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected 
                    ? Colors.orange.withOpacity(0.1) 
                    : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
                borderRadius: BorderRadius.circular(20),
                border: isSelected ? Border.all(color: Colors.orange.withOpacity(0.3)) : null,
              ),
              child: Row(
                children: [
                   _buildShiftSelfieMini(shift.selfie),
                   const SizedBox(width: 16),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(shift.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                         Text(
                           '${DateFormat('HH:mm').format(shift.startTime ?? DateTime.now())} - ${shift.endTime != null ? DateFormat('HH:mm').format(shift.endTime!) : "..."}',
                           style: TextStyle(color: Colors.grey[600], fontSize: 12),
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

  Widget _buildShiftDetailPanel(bool isDarkMode) {
    final shift = _logic.selectedShift!;
    return Positioned(
      bottom: 100, // Над BottomSheet
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 2)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _showFullImage(shift.selfie),
                  child: Hero(
                    tag: 'selfie_${shift.id}',
                    child: _buildShiftSelfieMini(shift.selfie, size: 80),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shift.username, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text('${shift.position} • ${shift.zone}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        'Смена: ${DateFormat('HH:mm').format(shift.startTime ?? DateTime.now())} - ${shift.endTime != null ? DateFormat('HH:mm').format(shift.endTime!) : "В процессе"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _logic.selectedShift = null;
                    _logic.selectedEmployeeHistory = [];
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftSelfieMini(String? selfie, {double size = 48}) {
    if (selfie == null || selfie.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.person, color: Colors.white),
      );
    }

    String url = selfie;
    if (!url.startsWith('http')) {
      // Если путь уже содержит uploads/, убираем его перед добавлением mediaBaseUrl или просто используем mediaBaseUrl
      // На бэкенде обычно хранится путь вида "uploads/selfies/..."
      if (url.startsWith('/')) url = url.substring(1);
      url = '${AppConfig.backendHost}/$url';
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
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
                child: Image.network(url, fit: BoxFit.contain),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Настройки слоев', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 24),
              _buildLayerToggle('Ограниченные зоны', _logic.showRestrictedZones, (v) {
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

class _PulseMarkerState extends State<_PulseMarker> with SingleTickerProviderStateMixin {
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
          width: 60 * _controller.value,
          height: 60 * _controller.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withOpacity(1 - _controller.value),
          ),
        );
      },
    );
  }
}
