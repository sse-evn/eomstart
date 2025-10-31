// lib/utils/map_app_constants.dart
import 'package:latlong2/latlong.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(43.2389, 76.8897);
  static const double defaultMapZoom = 15.0;

  // ✅ Правильный URL — только чистая строка без мусора
  static const String cartoDbPositronUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // ❌ УДАЛИТЕ subdomains — они не нужны для tile.openstreetmap.org
  // static const List<String> cartoDbSubdomains = ['a', 'b', 'c', 'd'];

  static const String userAgentPackageName = 'kz.evn';

  static const double minZoom = 14.0;
  static const double maxZoom = 25.0;
  static const double zoneLabelZoomThreshold = 14.0;
}
