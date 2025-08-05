import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:latlong2/latlong.dart';

import 'package:micro_mobility_app/services/location_service.dart';

import 'package:micro_mobility_app/utils/app_constants.dart';

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
    try {
      final position = await _locationService.determinePosition();

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });

        _mapController.move(_currentLocation!, _mapController.camera.zoom);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка получения местоположения: $e')),
        );
      }
    }
  }

  Future<void> _loadAndParseGeoJson() async {
    try {
      final String geoJsonString =
          await rootBundle.loadString('assets/almaty_zone.geojson');

      _geoJsonParser.parseGeoJsonAsString(geoJsonString);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки или парсинга GeoJSON: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentLocation ?? const LatLng(43.238949, 76.889709),
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

            tileProvider:
                NetworkTileProvider(), // Использовать NetworkTileProvider

            retinaMode:
                RetinaMode.isHighDensity(context), // Автоматическое определение
          ),
          if (_currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation!,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          if (_geoJsonParser.polygons.isNotEmpty)
            PolygonLayer(
              polygons: _geoJsonParser.polygons.map((polygon) {
                return Polygon(
                  points: polygon.points,
                  borderColor: Colors.blue,
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderStrokeWidth: 2,
                );
              }).toList(),
            ),
          if (_geoJsonParser.polylines.isNotEmpty)
            PolylineLayer(
              polylines: _geoJsonParser.polylines.map((polyline) {
                return Polyline(
                  points: polyline.points,
                  color: Colors.green,
                  strokeWidth: 3,
                );
              }).toList(),
            ),
          if (_geoJsonParser.markers.isNotEmpty)
            MarkerLayer(
              markers: _geoJsonParser.markers.map((marker) {
                return Marker(
                  point: marker.point,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.purple,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
