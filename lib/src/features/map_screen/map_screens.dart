// screens/map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:micro_mobility_app/src/core/utils/map_app_constants.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/providers/shift_provider.dart';
import 'map_logic.dart';

class MapScreen extends StatefulWidget {
  final String? initialMapId;
  const MapScreen({super.key, this.initialMapId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late MapLogic logic;

  // 🔥 Создаём tile provider ОДИН РАЗ вне build()
  late final FMTCTileProvider _tileProvider = FMTCTileProvider(
    stores: const {'mapStore': BrowseStoreStrategy.readUpdateCreate},
    loadingStrategy: BrowseLoadingStrategy.onlineFirst,
  );

  @override
  void initState() {
    super.initState();

    logic = MapLogic(context);
    
    // Получаем автарку из провайдера
    final shiftProvider = context.read<ShiftProvider>();
    final avatar = shiftProvider.profile?['avatar'] as String?;
    if (avatar != null) {
      logic.updateAvatarUrl(avatar);
    }

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
      body: Consumer<ShiftProvider>(
        builder: (context, shiftProvider, child) {
          // Обновляем аватарку в логике, если она изменилась или загрузилась
          final avatar = shiftProvider.profile?['avatarUrl'] as String?;
          if (avatar != null && avatar != logic.currentUserAvatarUrl) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              logic.updateAvatarUrl(avatar);
            });
          }

          return Stack(
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
                    urlTemplate: AppConstants.mapUrl,
                    subdomains: AppConstants.mapSubdomains,
                    userAgentPackageName: AppConstants.userAgentPackageName,
                    retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
                    tileProvider: logic.tileProvider,
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
                    MarkerLayer(markers: logic.geoJsonParser.markers),
                  if (logic.currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: logic.currentLocation!,
                          width: 54,
                          height: 54,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: logic.currentUserAvatarUrl != null
                                  ? Image.network(
                                      logic.currentUserAvatarUrl!,
                                      fit: BoxFit.cover,
                                      width: 48,
                                      height: 48,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                        if (loadingProgress == null)
                                          return child;
                                        return Container(
                                          color: Colors.blue[300],
                                          child:
                                              const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        );
                                      },
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                        color: Colors.blue[700],
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.blue[700],
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  // + Слой с другими пользователями
                  if (logic.otherScoutsLocations.isNotEmpty)
                    MarkerLayer(
                      markers: logic.otherScoutsLocations.map((loc) {
                        final lat = double.tryParse(
                                loc['latitude']?.toString() ?? '0') ??
                            0;
                        final lon = double.tryParse(
                                loc['longitude']?.toString() ?? '0') ??
                            0;
                        return Marker(
                          point: LatLng(lat, lon),
                          width: 32,
                          height: 32,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.orange[800],
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4)
                              ],
                            ),
                            child: const Icon(Icons.person_outline,
                                size: 18, color: Colors.white),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
              Positioned(
                bottom: 30,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'zoomIn',
                      backgroundColor: Colors.green[700],
                      onPressed: () {
                        logic.mapController.move(
                          logic.mapController.camera.center,
                          logic.mapController.camera.zoom + 1,
                        );
                      },
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'zoomOut',
                      backgroundColor: Colors.green[700],
                      onPressed: () {
                        logic.mapController.move(
                          logic.mapController.camera.center,
                          logic.mapController.camera.zoom - 1,
                        );
                      },
                      child: const Icon(Icons.remove, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'location',
                      backgroundColor: Colors.green[700],
                      onPressed: logic.fetchCurrentLocation,
                      child: logic.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.my_location, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
