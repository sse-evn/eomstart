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
        title: const Text(
          'Карта объектов',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          _buildMapActions(),
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
                  onTap: (tapPosition, point) => _handleMapTap(point),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: Theme.of(context).brightness == Brightness.dark
                        ? AppConstants.darkMapUrl
                        : AppConstants.mapUrl,
                    subdomains: AppConstants.mapSubdomains,
                    userAgentPackageName: AppConstants.userAgentPackageName,
                    retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
                    tileProvider: logic.tileProvider,
                  ),
                  if (logic.geoJsonParser.polygons.isNotEmpty &&
                      logic.showRestrictedZones)
                    PolygonLayer(
                      polygons: logic.geoJsonParser.polygons.map((polygon) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return Polygon(
                          points: polygon.points,
                          borderColor: isDark ? Colors.redAccent : Colors.red,
                          color: isDark 
                              ? Colors.redAccent.withOpacity(0.3) 
                              : Colors.red.withOpacity(0.2),
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
                          child: Transform.rotate(
                            angle: (logic.isNavigatorMode ? logic.currentHeading : 0) * (3.1415926535897932 / 180),
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
                              child: Stack(
                                children: [
                                  ClipOval(
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
                                  if (logic.isNavigatorMode)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Icon(Icons.navigation_rounded, color: Colors.blueAccent, size: 20),
                                      ),
                                    ),
                                ],
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
                        final name = loc['employee_name']?.toString() ?? 'Скаут';
                        
                        return Marker(
                          point: LatLng(lat, lon),
                          width: 45,
                          height: 45,
                          child: GestureDetector(
                            onTap: () => _showScoutInfo(name, loc),
                            child: _buildScoutMarker(name),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
              // Тень сверху для AppBar-эффекта
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                         Colors.black.withOpacity(0.1),
                         Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Боковая панель управления (Слои, Карта)
              Positioned(
                top: 20,
                right: 16,
                child: _buildSideControls(),
              ),
              // Нижняя панель управления (Зум, Локация)
              Positioned(
                bottom: 30,
                right: 16,
                child: _buildMapNavigationControls(),
              ),
              // Индикатор загрузки
              if (logic.isLoading)
                const Center(
                  child: Card(
                    elevation: 8,
                    shape: CircleBorder(),
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(color: Colors.green),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _handleMapTap(LatLng point) {
    final zoneData = logic.findPolygonAtPoint(point);
    if (zoneData != null) {
      // Центрируем и увеличиваем
      logic.mapController.move(point, 17.5);
      _showZoneInfoSheet(zoneData);
    }
  }

  void _showZoneInfoSheet(Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? data['description']?.toString() ?? 'Активная зона';
    final isRestricted = data['type'] == 'restricted' || (data['description']?.toString().contains('Запрет') ?? false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A), // Темный фон для четкости
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  isRestricted ? Icons.block_flipped : Icons.verified_user_rounded,
                  color: isRestricted ? Colors.redAccent : Colors.greenAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      Text(
                        isRestricted ? 'Ограничение проезда/парковки' : 'Разрешенная зона работы',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMapActions() {
    return Row(
      children: [
        FutureBuilder<bool>(
          future: logic.isOffline(),
          builder: (context, snapshot) {
            if (snapshot.data == true) {
              return const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 20),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        if (logic.isMapLoadedOffline)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.sd_storage_rounded, color: Colors.green, size: 20),
          ),
      ],
    );
  }

  Widget _buildSideControls() {
    return Column(
      children: [
        _mapControlButon(
          icon: Icons.layers_rounded,
          onPressed: () => logic.showLayerSettingsDialog(),
          tooltip: 'Слои',
        ),
        const SizedBox(height: 12),
        if (logic.availableMaps.isNotEmpty)
          _mapControlButon(
            icon: Icons.map_rounded,
            onPressed: () => _showMapSelectionMenu(),
            tooltip: 'Выбор города',
          ),
        const SizedBox(height: 12),
        if (logic.selectedMapId != -1)
          _mapControlButon(
            icon: Icons.download_for_offline_rounded,
            onPressed: () => logic.downloadMapLocally(logic.selectedMapId),
            tooltip: 'Скачать карту',
          ),
      ],
    );
  }

  Widget _buildMapNavigationControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mapControlButon(
          icon: logic.isNavigatorMode ? Icons.navigation_rounded : Icons.explore_outlined,
          onPressed: () {
            logic.toggleNavigatorMode();
          },
          tooltip: 'Режим навигатора',
        ),
        const SizedBox(height: 16),
        _mapControlButon(
          icon: Icons.add_rounded,
          onPressed: () {
            logic.mapController.move(
              logic.mapController.camera.center,
              logic.mapController.camera.zoom + 1,
            );
          },
        ),
        const SizedBox(height: 8),
        _mapControlButon(
          icon: Icons.remove_rounded,
          onPressed: () {
            logic.mapController.move(
              logic.mapController.camera.center,
              logic.mapController.camera.zoom - 1,
            );
          },
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => logic.fetchCurrentLocation(isManual: true),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[700],
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: logic.isLocating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location_rounded, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _mapControlButon({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.grey[800]),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildScoutMarker(String name) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.orange[800],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.person_pin_circle_rounded, size: 22, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showMapSelectionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A), // Темный фон
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Выберите город',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: logic.availableMaps.map((map) {
                  final id = map['id'] as int;
                  final city = map['city'] as String? ?? 'Неизвестный город';
                  final desc = map['description'] as String? ?? '';
                  final isSelected = logic.selectedMapId == id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.green : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.green : Colors.white10,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.location_city_rounded,
                          color: isSelected ? Colors.white : Colors.white70,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        city,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: desc.isNotEmpty 
                        ? Text(desc, style: TextStyle(color: Colors.white38, fontSize: 12)) 
                        : null,
                      trailing: isSelected 
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 24) 
                        : null,
                      onTap: () {
                        logic.onMapChanged(id);
                        Navigator.pop(context);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showScoutInfo(String name, dynamic data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2),
              ),
              child: const Icon(Icons.person_rounded, color: Colors.orangeAccent, size: 45),
            ),
            const SizedBox(height: 20),
            Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Скаут команды',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _scoutAction(Icons.message_rounded, 'Написать', () {}),
                _scoutAction(Icons.call_rounded, 'Позвонить', () {}),
                _scoutAction(Icons.gps_fixed_rounded, 'Маршрут', () {
                   Navigator.pop(context);
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _scoutAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
