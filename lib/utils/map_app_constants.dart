// lib/utils/map_app_constants.dart
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(43.2389, 76.8897);
  static const double defaultMapZoom = 15.0;

  static const String cartoDbPositronUrl =
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png";
  static const List<String> cartoDbSubdomains = ['a', 'b', 'c', 'd'];

  static const String userAgentPackageName = 'kz.evn';

  // Настройки карты
  static const double minZoom = 12.0;
  static const double maxZoom = 25.0;
  static const double zoneLabelZoomThreshold = 14.0;

  // Кэш для тайлов (добавлено для офлайн-загрузки фоновой карты)
  static const String tileCacheStoreName = 'map_tiles_cache';
  
}
