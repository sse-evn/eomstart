import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/services/location_service.dart';
import 'package:micro_mobility_app/utils/map_app_constants.dart';
import 'package:flutter_map_geojson/flutter_map_geojson.dart';
import 'package:flutter/services.dart' show rootBundle;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentLocation;
  final LocationService _locationService = LocationService();
  final GeoJsonParser _geoJsonParser = GeoJsonParser();
  late final MapController _mapController;
  bool _isLoading = false;
  final Map<int, LatLng> _zoneCenters = {};

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _fetchCurrentLocation();
    _loadAndParseGeoJson();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      final position = await _locationService.determinePosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoading = false;
          _mapController.move(_currentLocation!, _mapController.camera.zoom);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка получения местоположения')),
        );
      }
    }
  }

  Future<void> _loadAndParseGeoJson() async {
    try {
      final String geoJsonString =
          await rootBundle.loadString('assets/almaty_zone.geojson');
      _geoJsonParser.parseGeoJsonAsString(geoJsonString);

      // Вычисляем точный центр масс для каждой зоны
      for (int i = 0; i < _geoJsonParser.polygons.length; i++) {
        final points = _geoJsonParser.polygons[i].points;
        final zoneId = i + 1;
        _zoneCenters[zoneId] = _calculateCentroid(points);
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки GeoJSON')),
        );
      }
    }
  }

  // Точный расчет центра масс полигона
  LatLng _calculateCentroid(List<LatLng> points) {
    double area = 0;
    double lat = 0;
    double lng = 0;
    final int n = points.length;

    for (int i = 0; i < n; i++) {
      final LatLng p1 = points[i];
      final LatLng p2 = points[(i + 1) % n];

      final double f = p1.latitude * p2.longitude - p2.latitude * p1.longitude;
      lat += (p1.latitude + p2.latitude) * f;
      lng += (p1.longitude + p2.longitude) * f;
      area += f;
    }

    area /= 2;
    final double centroidLat = lat / (6 * area);
    final double centroidLng = lng / (6 * area);

    return LatLng(centroidLat.abs(), centroidLng.abs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта зон'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentLocation ?? const LatLng(43.238949, 76.889709),
              initialZoom: AppConstants.defaultMapZoom,
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
              if (_geoJsonParser.polygons.isNotEmpty)
                PolygonLayer(
                  polygons: _geoJsonParser.polygons.map((polygon) {
                    return Polygon(
                      points: polygon.points,
                      borderColor: Colors.blue,
                      color: Colors.blueAccent.withOpacity(0.1),
                      borderStrokeWidth: 1.5,
                    );
                  }).toList(),
                ),
              MarkerLayer(
                markers: _zoneCenters.entries.map((entry) {
                  return Marker(
                    point: entry.value,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key}',
                          style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
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
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'locationFab',
              backgroundColor: Colors.green[700],
              onPressed: _fetchCurrentLocation,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
