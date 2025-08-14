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

  static const Map<String, LatLng> cityCenters = {
    'Алматы': LatLng(43.2389, 76.8897),
    'Астана': LatLng(51.1605, 71.4704),
  };

  static const String almatyGeoJson = 'assets/geojson/almaty_zone.geojson';
  static const String astanaGeoJson = 'assets/geojson/astana_zone.geojson';

  // Слои запретных зон
  static const String restrictedZonesGeoJson =
      'assets/geojson/restricted_zones.geojson';

  // Типы геометрий в GeoJSON для разных слоев
  static const String featureTypeZone = 'zone'; // Основные зоны обслуживания
  static const String featureTypeRestricted = 'restricted'; // Запретные зоны
  static const String featureTypeDanger = 'danger'; // Опасные зоны
  static const String featureTypeParking = 'parking'; // Зоны парковки

  // Свойства GeoJSON для определения типа зоны
  static const String propertyType = 'type';
  static const String propertyName = 'name';
  static const String propertyDescription = 'description';
  static const String propertyColor = 'color';
  static const String propertyOpacity = 'opacity';

  // Настройки отображения маркеров
  static const double markerWidth = 30;
  static const double markerHeight = 30;
  static const double markerFontSize = 14;

  // Настройки карты
  static const double minZoom = 10.0;
  static const double maxZoom = 18.0;
  static const double zoneLabelZoomThreshold =
      14.0; // Минимальный зум для отображения подписей

  // Цвета для разных типов зон
  static Map<String, ZoneStyle> get zoneStyles => {
        'zone': ZoneStyle(
          borderColor: Colors.blue,
          fillColor: Colors.blueAccent.withOpacity(0.1),
          borderWidth: 1.5,
        ),
        'restricted': ZoneStyle(
          borderColor: Colors.red,
          fillColor: Colors.red.withOpacity(0.2),
          borderWidth: 2.0,
        ),
        'danger': ZoneStyle(
          borderColor: Colors.orange,
          fillColor: Colors.orange.withOpacity(0.3),
          borderWidth: 2.5,
        ),
        'parking': ZoneStyle(
          borderColor: Colors.green,
          fillColor: Colors.green.withOpacity(0.15),
          borderWidth: 1.5,
        ),
      };
}

// Класс для стилей зон
class ZoneStyle {
  final Color borderColor;
  final Color fillColor;
  final double borderWidth;

  ZoneStyle({
    required this.borderColor,
    required this.fillColor,
    required this.borderWidth,
  });
}
