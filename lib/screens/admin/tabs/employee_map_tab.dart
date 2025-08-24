// lib/screens/employee_map_tab.dart

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

class _EmployeeMapTabState extends State<EmployeeMapTab> {
  late EmployeeMapLogic logic;

  @override
  void initState() {
    super.initState();
    logic = EmployeeMapLogic(context);
    logic.onStateChanged = () {
      if (mounted) setState(() {});
    };
    logic.init();
  }

  @override
  void dispose() {
    logic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (logic.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (logic.error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка: ${logic.error}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  logic.isLoading = true;
                  logic.error = '';
                });
                // Перезапускаем инициализацию через публичный метод
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  logic.initMap(); // ✅ Но лучше — вынести в публичный метод
                });
              },
              child: const Text('Попробовать снова'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Карта
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              FlutterMap(
                mapController: logic.mapController,
                options: MapOptions(
                  initialCenter:
                      logic.currentLocation ?? const LatLng(43.2389, 76.8897),
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
                  if (logic.currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: logic.currentLocation!,
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
                  if (logic.users.isNotEmpty)
                    MarkerLayer(
                      markers: logic.users.map((user) {
                        return Marker(
                          point: LatLng(user.lat, user.lng),
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                user.username.isNotEmpty
                                    ? user.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  if (logic.activeShifts.isNotEmpty)
                    MarkerLayer(
                      markers: logic.activeShifts
                          .where((shift) => shift.hasLocation)
                          .map((shift) {
                        return Marker(
                          point: LatLng(shift.lat!, shift.lng!),
                          width: 60,
                          height: 30,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 3,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              shift.username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),

              // Статус подключения
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: logic.isWebSocketConnected
                        ? Colors.green
                        : (logic.connectionError ? Colors.red : Colors.orange),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        logic.isWebSocketConnected
                            ? Icons.wifi
                            : (logic.connectionError
                                ? Icons.wifi_off
                                : Icons.wifi_find),
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        logic.isWebSocketConnected
                            ? 'Подключено'
                            : (logic.connectionError
                                ? 'Ошибка'
                                : 'Подключение...'),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              // Кнопка обновления
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: logic.refreshMap,
                  tooltip: 'Обновить карту',
                  child: logic.isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        // Список смен
        Expanded(
          flex: 2,
          child: Card(
            margin: const EdgeInsets.all(8),
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Активные смены: ${logic.activeShifts.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      if (logic.isRefreshing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              size: 18, color: Colors.white),
                          onPressed: logic.refreshMap,
                          tooltip: 'Обновить',
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: logic.activeShifts.isEmpty
                      ? const Center(
                          child: Text('Нет активных смен',
                              style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: logic.activeShifts.length,
                          itemBuilder: (context, index) {
                            final shift = logic.activeShifts[index];
                            final locationStatus = shift.hasLocation
                                ? '📍 ${shift.lat!.toStringAsFixed(5)}, ${shift.lng!.toStringAsFixed(5)}'
                                : 'Местоположение недоступно';
                            final timeAgo = shift.timestamp != null
                                ? logic.formatTimeAgo(shift.timestamp!)
                                : 'Данные не обновлялись';
                            final statusColor = logic.getStatusColor(shift);

                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: shift.hasLocation
                                      ? Colors.green
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    shift.username[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                shift.username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Позиция: ${shift.position}'),
                                  Text('Зона: ${shift.zone}'),
                                  Text(locationStatus),
                                  Text('🕒 $timeAgo',
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              trailing: Icon(Icons.circle,
                                  color: statusColor, size: 12),
                              onTap: () {
                                if (shift.hasLocation) {
                                  logic.mapController.move(
                                    LatLng(shift.lat!, shift.lng!),
                                    15.0,
                                  );
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
