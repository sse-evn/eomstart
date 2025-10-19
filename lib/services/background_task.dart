// lib/services/background_task.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:http/http.dart' as http;
import 'package:micro_mobility_app/config/config.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Устанавливаем обработчик ДО configure
  // FlutterBackgroundService.setServiceHandler(onStart);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'tracking_channel',
      initialNotificationTitle: 'Микромобильность',
      initialNotificationContent: 'Трекинг активен',
      foregroundServiceNotificationId: 888,
      onStart: (ServiceInstance service) {},
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
    ),
    // НЕ передаём onStart здесь — он зарегистрирован глобально
  );

  service.startService();
}

@pragma('vm:entry-point')
FutureOr<bool> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = const FlutterSecureStorage();
  final battery = Battery();

  bool isServiceRunning = true;

  service.on('stopTracking').listen((event) async {
    isServiceRunning = false;
    if (service is AndroidServiceInstance) {
      await service.stopSelf();
    } else {
      service.invoke('stopService');
    }
  });

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (!isServiceRunning) {
      timer.cancel();
      return;
    }

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) {
        debugPrint('JWT токен не найден, пропускаем отправку');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      final batteryLevel = await battery.batteryLevel;

      final response = await http.post(
        Uri.parse(AppConfig.geoTrackUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'lat': position.latitude,
          'lon': position.longitude,
          'speed': position.speed,
          'accuracy': position.accuracy,
          'battery': batteryLevel,
          'event': 'tracking',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Позиция отправлена: ${DateTime.now().toLocal()}');
      } else {
        debugPrint('Ошибка сервера: ${response.statusCode}');
      }

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "Микромобильность",
          content: "Последнее обновление: ${DateTime.now().toLocal()}",
        );
      }
    } catch (e) {
      debugPrint('Ошибка трекинга: $e');
    }
  });

  return true; // <-- важно вернуть bool
}
