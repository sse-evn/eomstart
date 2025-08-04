// screens/map_screen.dart
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
  String? _almatyGeoJson;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _loadAndParseGeoJson();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final position = await _locationService.determinePosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
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
      setState(() {
        // Обновляем состояние, чтобы карта перерисовала слои
      });
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
        backgroundColor: Colors.green[700], // Зеленый AppBar для карты
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _currentLocation ?? const LatLng(43.238949, 76.889709),
          initialZoom: AppConstants.defaultMapZoom,
        ),
        children: [
          TileLayer(
            urlTemplate: AppConstants.cartoDbPositronUrl,
            subdomains: AppConstants.cartoDbSubdomains,
            userAgentPackageName: AppConstants.userAgentPackageName,
          ),
          if (_currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation!,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40.0,
                  ),
                ),
              ],
            ),
          PolygonLayer(
            polygons: _geoJsonParser.polygons.map((polygon) {
              return Polygon(
                points: polygon.points,
                borderColor: Colors.blue,
                color: Colors.blueAccent.withOpacity(0.3),
                borderStrokeWidth: 3,
                isFilled: true,
              );
            }).toList(),
          ),
          PolylineLayer(
            polylines: _geoJsonParser.polylines.map((polyline) {
              return Polyline(
                points: polyline.points,
                color: Colors.green,
                strokeWidth: 4,
              );
            }).toList(),
          ),
          MarkerLayer(
            markers: _geoJsonParser.markers.map((marker) {
              return Marker(
                point: marker.point,
                child: const Icon(
                  Icons.circle,
                  color: Colors.purple,
                  size: 10,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
