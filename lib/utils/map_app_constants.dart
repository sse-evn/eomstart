// lib/utils/map_app_constants.dart
import 'package:latlong2/latlong.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(43.2389, 76.8897);
  static const double defaultMapZoom = 15.0;

  static const String cartoDbPositronUrl =
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png";
  static const List<String> cartoDbSubdomains = ['a', 'b', 'c', 'd'];

  static const String userAgentPackageName = 'kz.evn';

  static const double minZoom = 14.0;
  static const double maxZoom = 25.0;
  static const double zoneLabelZoomThreshold = 14.0;

  // === Только константы — НИКАКИХ ОБЪЕКТОВ ===
  static const String tileCacheStoreName = 'map_tiles_cache';
  static const Duration cacheValidDuration = Duration(days: 30);
  static const int maxTileCount = 5000;
  static const bool cacheEnabled = true;
}
