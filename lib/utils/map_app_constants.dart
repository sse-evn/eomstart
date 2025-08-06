// utils/app_constants.dart
import 'package:latlong2/latlong.dart';

class AppConstants {
  static const LatLng defaultMapCenter = LatLng(55.7558, 37.6173);
  static const double defaultMapZoom = 13.0;
  static const String cartoDbPositronUrl =
      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png";
  static const List<String> cartoDbSubdomains = ['a', 'b', 'c', 'd'];
  static const String userAgentPackageName = 'com.example.micromobility_app';
}
