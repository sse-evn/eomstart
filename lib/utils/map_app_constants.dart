// lib/utils/map_app_constants.dart

import 'package:latlong2/latlong.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(43.2389, 76.8897);
  static const double defaultMapZoom = 13.0;

  static const String cartoDbPositronUrl =
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png";
  static const List<String> cartoDbSubdomains = ['a', 'b', 'c', 'd'];

  static const String userAgentPackageName = 'com.example.micromobility_app';
  static const String tileCacheStoreName = 'defaultCache';

  static const List<String> supportedCities = ['Алматы', 'Астана'];

  static const Map<String, LatLng> cityCenters = {
    'Алматы': LatLng(43.2389, 76.8897),
    'Астана': LatLng(51.1605, 71.4704),
  };

  static const String almatyGeoJson = 'assets/geojson/almaty_zone.geojson';
  static const String astanaGeoJson = 'assets/geojson/astana_zone.geojson';
}
