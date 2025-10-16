// screens/map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/utils/map_app_constants.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'map_logic.dart'; // убедись, что путь правильный

class MapScreen extends StatefulWidget {
  final String? initialMapId;
  const MapScreen({super.key, this.initialMapId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late MapLogic logic;

  @override
  void initState() {
    super.initState();
    logic = MapLogic(context);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта зон'),
        automaticallyImplyLeading: false,
        actions: [
          // Индикатор офлайна
          FutureBuilder<bool>(
            future: logic.isOffline(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.data == true) {
                return const Tooltip(
                  message: 'Режим офлайн',
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.cloud_off, color: Colors.orange),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (logic.availableMaps.isNotEmpty)
            PopupMenuButton<int>(
              icon: const Icon(Icons.map),
              onSelected: logic.onMapChanged,
              itemBuilder: (BuildContext context) {
                return logic.availableMaps.map((map) {
                  if (map is Map<String, dynamic>) {
                    final id = map['id'] as int;
                    final city = map['city'] as String? ?? 'Неизвестный город';
                    final description = map['description'] as String? ?? '';
                    final displayName =
                        description.isNotEmpty ? '$city - $description' : city;
                    return PopupMenuItem<int>(
                      value: id,
                      child: Text(displayName),
                    );
                  }
                  return const PopupMenuItem<int>(
                    value: 0,
                    child: Text('Некорректная карта'),
                  );
                }).toList();
              },
            ),
          if (logic.selectedMapId != -1)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => logic.downloadMapLocally(logic.selectedMapId),
              tooltip: 'Сохранить карту локально',
            ),
          if (logic.isMapLoadedOffline)
            const Tooltip(
              message: 'Карта загружена из офлайн-кеша',
              child: Icon(Icons.cloud_off, color: Colors.grey),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: logic.mapController,
            options: MapOptions(
              initialCenter:
                  logic.currentLocation ?? AppConstants.defaultMapCenter,
              initialZoom: AppConstants.defaultMapZoom,
              minZoom: AppConstants.minZoom,
              maxZoom: AppConstants.maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.cartoDbPositronUrl,
                subdomains: AppConstants.cartoDbSubdomains,
                userAgentPackageName: AppConstants.userAgentPackageName,
                retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
              ),
              if (logic.employeeLocations.isNotEmpty)
                MarkerLayer(
                  markers: logic.employeeLocations.map((emp) {
                    return Marker(
                      point: emp.position,
                      width: 36,
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Основная иконка
                          Icon(
                            Icons.person,
                            color: Colors.green[700],
                            size: 32,
                          ),
                          // Уровень батареи (если есть)
                          if (emp.battery != null)
                            Positioned(
                              top: -8,
                              right: -8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${emp.battery!.toInt()}%',
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
              if (logic.geoJsonParser.polygons.isNotEmpty &&
                  logic.showRestrictedZones)
                PolygonLayer(
                  polygons: logic.geoJsonParser.polygons.map((polygon) {
                    return Polygon(
                      points: polygon.points,
                      borderColor: Colors.red,
                      color: Colors.red.withOpacity(0.2),
                      borderStrokeWidth: 2.0,
                    );
                  }).toList(),
                ),
              if (logic.geoJsonParser.polylines.isNotEmpty &&
                  logic.showBoundaries)
                PolylineLayer(
                  polylines: logic.geoJsonParser.polylines.map((polyline) {
                    return Polyline(
                      points: polyline.points,
                      color: Colors.blue,
                      strokeWidth: 5,
                    );
                  }).toList(),
                ),
              if (logic.geoJsonParser.markers.isNotEmpty)
                MarkerLayer(
                  markers:
                      logic.geoJsonParser.markers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final marker = entry.value;
                    return Marker(
                      point: marker.point,
                      width: 30,
                      height: 30,
                      child: Container(
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 3.0,
                                color: Colors.black,
                                offset: Offset(1.0, 1.0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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
            ],
          ),
          Positioned(
            bottom: 80,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'layersFab',
              backgroundColor: Colors.green[700],
              onPressed: logic.showLayerSettingsDialog,
              child: const Icon(Icons.layers, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'locationFab',
              backgroundColor: Colors.green[700],
              onPressed: logic.fetchCurrentLocation,
              child: logic.isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
          if (logic.isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
