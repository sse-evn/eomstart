// lib/utils/map_app_constants.dart
import 'package:latlong2/latlong.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(43.2389, 76.8897);
  static const double defaultMapZoom = 15.0;

  // ✅ Обновлено: стиль карты как в 2GIS (более детализированный)
  static const String mapUrl =
      'https://tile{s}.maps.2gis.com/tiles?z={z}&x={x}&y={y}&v=1';
  static const List<String> mapSubdomains = ['1', '2', '3', '4'];

  static const String userAgentPackageName = 'kz.evn';

  static const double minZoom = 12.0;
  static const double maxZoom = 25.0; // Увеличено для лучшей детализации
  static const double zoneLabelZoomThreshold = 14.0;
}
