import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/app_config.dart' show AppConfig;

final FlutterSecureStorage _storage = const FlutterSecureStorage();
Timer? _backgroundTimer;

@pragma('vm:entry-point')
void backgroundServiceEntryPoint() {
  // Это точка входа для натива — ничего не делаем, просто вызываем onStart
}

@pragma('vm:entry-point')
FutureOr<bool> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  service.on('stopTracking').listen((event) {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  });

  _backgroundTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final battery = await Battery().batteryLevel;

      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        timer.cancel();
        return;
      }

      final body = {
        'lat': position.latitude,
        'lon': position.longitude,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'battery': battery,
        'event': 'tracking',
      };

      await http.post(
        Uri.parse(AppConfig.geoTrackUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      // ignore
    }
  });

  return true;
}

void startBackgroundTracking() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onStart,
    ),
  );
  await service.startService();
}

void stopBackgroundTracking() {
  FlutterBackgroundService().invoke('stopTracking');
}
