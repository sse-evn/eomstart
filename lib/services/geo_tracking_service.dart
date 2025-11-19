// lib/services/geo_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'package:http/http.dart' as http;

void _log(String message, {Object? error, StackTrace? stackTrace}) {
  debugPrint('BG-GeoService: $message');
  if (error != null) debugPrint('  Error: $error');
  if (stackTrace != null) debugPrint('  Stack: $stackTrace');
}

const String _SHARED_PREFS_SHIFT_ID_KEY = 'active_shift_id_for_bg_service';
const String _SHARED_PREFS_BG_RUNNING_KEY = 'is_bg_geo_tracking_running';

Timer? _backgroundTimer;
int? _activeShiftId;
final FlutterSecureStorage _storage = const FlutterSecureStorage();

bool _serviceIsActuallyRunning = false;

@pragma('vm:entry-point')
FutureOr<bool> onStart(ServiceInstance service) async {
  _log("onStart вызван");

  if (_serviceIsActuallyRunning) {
    _log("Сервис уже поднят — игнорируем.");
    return true;
  }

  _serviceIsActuallyRunning = true;
  final prefs = await SharedPreferences.getInstance();
  final shiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);

  if (shiftId == null) {
    _log("Нет active_shift_id — останавливаем.");
    service.stopSelf();
    _serviceIsActuallyRunning = false;
    return false;
  }

  _activeShiftId = shiftId;
  _log("Получен shiftId: $_activeShiftId");

  service.on('stopTracking').listen((event) {
    _log("Получен сигнал stopTracking");
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _activeShiftId = null;
    _serviceIsActuallyRunning = false;
  });

  _backgroundTimer = Timer.periodic(
      const Duration(seconds: 60), _collectAndAttemptToSendGeoData);

  await prefs.setBool(_SHARED_PREFS_BG_RUNNING_KEY, true);
  _log("Сервис запущен для смены $_activeShiftId");

  return true;
}

Future<void> _collectAndAttemptToSendGeoData(Timer timer) async {
  _log("Сбор геоданных...");

  try {
    final prefs = await SharedPreferences.getInstance();
    final currentActiveShiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);

    if (currentActiveShiftId != _activeShiftId) {
      _log("ShiftID изменился — останавливаем таймер.");
      timer.cancel();
      _activeShiftId = null;
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    _log("Проверка разрешения: $permission");

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _log("Нет разрешения — прерываем.");
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      _log("GPS выключен.");
      return;
    }

    Position position;
    int batteryLevel;

    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
    } catch (e) {
      _log("Ошибка получения позиции: $e");
      return;
    }

    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (e) {
      batteryLevel = 0;
    }

    // 🔥 Фильтр нулевых координат
    if (position.latitude == 0.0 || position.longitude == 0.0) {
      _log("Получена 0,0 позиция — пропуск");
      return;
    }

    final geoDataJson = jsonEncode({
      'lat': position.latitude,
      'lon': position.longitude,
      'speed': position.speed,
      'accuracy': position.accuracy,
      'battery': batteryLevel,
      'timestamp': DateTime.now().toIso8601String(),
      'event': 'tracking',
      'shift_id': _activeShiftId,
    });

    _log("Отправляем: $geoDataJson");

    try {
      await _sendSingleGeoDataToServer(geoDataJson);
    } catch (e) {
      _log("Ошибка отправки, сохраняем в буфер...");
      await _bufferFailedData(geoDataJson, _activeShiftId);
    }
  } catch (e) {
    _log("Ошибка в сборе данных: $e");
  }
}

Future<void> _sendSingleGeoDataToServer(String geoDataJson) async {
  final token = await _storage.read(key: 'jwt_token');
  if (token == null) throw Exception('JWT missing');

  final res = await http.post(
    Uri.parse(AppConfig.geoTrackUrl),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'data': [jsonDecode(geoDataJson)]
    }),
  );

  if (res.statusCode != 200) {
    if (res.statusCode == 401) {
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
    }
    throw Exception("HTTP ${res.statusCode}");
  }
}

Future<void> _bufferFailedData(String geoDataJson, int? shiftId) async {
  if (shiftId == null) return;
  final prefs = await SharedPreferences.getInstance();
  final key = 'geo_buffer_$shiftId';
  final current = prefs.getStringList(key) ?? [];
  current.add(geoDataJson);
  if (current.length > 1000) {
    current.removeRange(0, current.length - 1000);
  }
  await prefs.setStringList(key, current);
}

Future<void> startBackgroundTracking({required int shiftId}) async {
  _log("startBackgroundTracking($shiftId)");

  final prefs = await SharedPreferences.getInstance();
  final isRunning = prefs.getBool(_SHARED_PREFS_BG_RUNNING_KEY) ?? false;
  final currentShift = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);

  _log("isRunning=$isRunning, currentShift=$currentShift");

  if (isRunning && currentShift == shiftId) return;
  if (isRunning && currentShift != shiftId) await stopBackgroundTracking();

  final service = FlutterBackgroundService();
  await prefs.setInt(_SHARED_PREFS_SHIFT_ID_KEY, shiftId);

  if (!_serviceIsActuallyRunning) {
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onStart,
      ),
    );
  }

  await service.startService();
  _log("Фоновый сервис запущен.");
}

Future<void> stopBackgroundTracking() async {
  final prefs = await SharedPreferences.getInstance();
  final service = FlutterBackgroundService();

  service.invoke('stopTracking');

  _backgroundTimer?.cancel();
  _backgroundTimer = null;
  _activeShiftId = null;
  _serviceIsActuallyRunning = false;

  await prefs.remove(_SHARED_PREFS_SHIFT_ID_KEY);
  await prefs.remove(_SHARED_PREFS_BG_RUNNING_KEY);

  _log("Фоновый сервис остановлен.");
}

Future<bool> isBackgroundTrackingRunning() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_SHARED_PREFS_BG_RUNNING_KEY) ?? false;
}
