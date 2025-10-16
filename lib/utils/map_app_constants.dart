// lib/utils/map_app_constants.dart
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(43.2389, 76.8897);
  static const double defaultMapZoom = 13.0;

  static const String cartoDbPositronUrl =
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png";
  static const List<String> cartoDbSubdomains = ['a', 'b', 'c', 'd'];

  static const String userAgentPackageName = 'com.example.micromobility_app';
  static const String tileCacheStoreName = 'defaultCache';

  static const List<String> supportedCities = ['Алматы', 'Астана'];

  // Используем const LatLng и final Map
  static const LatLng _almaty = LatLng(43.2389, 76.8897);
  static const LatLng _astana = LatLng(51.1605, 71.4704);

  static final Map<String, LatLng> cityCenters = {
    'Алматы': _almaty,
    'Астана': _astana,
  };

  static const String almatyGeoJson = 'assets/geojson/almaty_zone.geojson';
  static const String astanaGeoJson = 'assets/geojson/astana_zone.geojson';
  static const String restrictedZonesGeoJson =
      'assets/geojson/restricted_zones.geojson';

  // Свойства GeoJSON
  static const String propertyType = 'type';
  static const String propertyName = 'name';
  static const String propertyDescription = 'description';
  static const String propertyColor = 'color';
  static const String propertyOpacity = 'opacity';

  // Настройки маркеров
  static const double markerWidth = 30;
  static const double markerHeight = 30;
  static const double markerFontSize = 14;

  // Настройки карты
  static const double minZoom = 10.0;
  static const double maxZoom = 18.0;
  static const double zoneLabelZoomThreshold = 14.0;

  // Стили зон — теперь const
  static const Map<String, ZoneStyle> zoneStyles = {
    'zone': ZoneStyle(
      borderColor: Colors.blue,
      fillColor: Colors.blueAccent,
      borderWidth: 1.5,
    ),
    'restricted': ZoneStyle(
      borderColor: Colors.red,
      fillColor: Colors.red,
      borderWidth: 2.0,
    ),
    'danger': ZoneStyle(
      borderColor: Colors.orange,
      fillColor: Colors.orange,
      borderWidth: 2.5,
    ),
    'parking': ZoneStyle(
      borderColor: Colors.green,
      fillColor: Colors.green,
      borderWidth: 1.5,
    ),
  };
}

// Конструктор ZoneStyle — теперь const
class ZoneStyle {
  final Color borderColor;
  final Color fillColor;
  final double borderWidth;

  const ZoneStyle({
    required this.borderColor,
    required this.fillColor,
    required this.borderWidth,
  });
}
