// lib/services/geo_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

void _log(String message, {Object? error, StackTrace? stackTrace}) {
  debugPrint('BG-GeoService: $message');
  if (error != null) debugPrint('  Error: $error');
  if (stackTrace != null) debugPrint('  Stack: $stackTrace');
}

const String _SHARED_PREFS_SHIFT_ID_KEY = 'active_shift_id_for_bg_service';
const String _SHARED_PREFS_BG_RUNNING_KEY = 'is_bg_geo_tracking_running';
const String _SHARED_PREFS_TOKEN_KEY = 'bg_geo_auth_token';

Timer? _backgroundTimer;
StreamSubscription<Position>? _positionStreamSubscription;
int? _activeShiftId;
String? _bgAuthToken;
Position? _latestPosition;
final FlutterSecureStorage _storage = const FlutterSecureStorage();

bool _serviceIsActuallyRunning = false;

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  _log("onStart вызван");

  if (_serviceIsActuallyRunning) {
    _log("Сервис уже поднят — игнорируем.");
    return;
  }

  _serviceIsActuallyRunning = true;
  final prefs = await SharedPreferences.getInstance();
  final shiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);

  if (shiftId == null) {
    _log("Нет active_shift_id — останавливаем.");
    service.stopSelf();
    _serviceIsActuallyRunning = false;
    return;
  }

  _activeShiftId = shiftId;
  _bgAuthToken = prefs.getString(_SHARED_PREFS_TOKEN_KEY);

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Микромобильность",
      content: "Отслеживание геопозиции активно",
    );
  }

  _log(
      "Получен shiftId: $_activeShiftId, Token: ${_bgAuthToken != null ? 'OK' : 'MISSING'}");

  service.on('stopTracking').listen((event) {
    _log("Получен сигнал stopTracking");
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _activeShiftId = null;
    _serviceIsActuallyRunning = false;
    service.stopSelf();
  });

  LocationSettings settings;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    settings = AppleSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
      activityType: ActivityType.otherNavigation,
    );
  } else {
    settings = const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  _log("Инициализация Location Stream...");
  _positionStreamSubscription = Geolocator.getPositionStream(
    locationSettings: settings,
  ).listen((position) {
    _latestPosition = position;
  });

  // Запускаем таймер сбора данных
  _backgroundTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
    await _collectAndAttemptToSendGeoData(timer);
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Микромобильность",
        content:
            "Геопозиция обновлена: ${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}",
      );
    }
  });

  await prefs.setBool(_SHARED_PREFS_BG_RUNNING_KEY, true);
  _log("Сервис запущен для смены $_activeShiftId");
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Обязательно синхронизируем данные с диска
    
    final shiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);
    final token = prefs.getString(_SHARED_PREFS_TOKEN_KEY);

    if (shiftId == null || token == null) {
      _log("iOS BG: Нет shiftId или токена, пропускаем отправку.");
      return true;
    }

    _bgAuthToken = token;
    _activeShiftId = shiftId;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
    
    int batteryLevel;
    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (_) {
      batteryLevel = 0;
    }

    final geoDataJson = jsonEncode({
      'lat': position.latitude,
      'lon': position.longitude,
      'speed': position.speed,
      'accuracy': position.accuracy,
      'battery': batteryLevel,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'event': 'ios_background',
      'shift_id': shiftId,
    });

    final key = 'geo_buffer_$shiftId';
    List<String> currentBuffer = prefs.getStringList(key) ?? [];
    currentBuffer.add(geoDataJson);

    try {
      await _sendGeoDataBatch(currentBuffer, shiftId);
      await prefs.remove(key);
      _log("iOS BG: Успешно отправлено ${currentBuffer.length} точек");
    } catch (networkError) {
      _log("iOS BG: Ошибка сети, сохраняем в буфер (${currentBuffer.length} точек)");
      if (currentBuffer.length > 1000) {
        currentBuffer.removeRange(0, currentBuffer.length - 1000);
      }
      await prefs.setStringList(key, currentBuffer);
    }
    return true;
  } catch (e) {
    _log("iOS BG fetch error: $e");
    return true;
  }
}

Future<void> _collectAndAttemptToSendGeoData(Timer timer) async {
  _log("Сбор геоданных...");

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Обязательно синхронизируем данные с диска (UI мог обновить токен)
    
    final currentActiveShiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);

    if (currentActiveShiftId == null) {
      _log("ShiftID отсутствует — пропускаем тик (таймер не останавливаем).");
      _activeShiftId = null;
      return;
    }

    // Всегда синхронизируем локальный ID с актуальным из SharedPreferences
    _activeShiftId = currentActiveShiftId;

    // Обновляем токен из хранилища на случай, если он поменялся (refresh)
    final freshToken = prefs.getString(_SHARED_PREFS_TOKEN_KEY);
    if (freshToken != null) _bgAuthToken = freshToken;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _log("Нет разрешения — прерываем.");
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      _log("GPS выключен.");
      return;
    }

    Position? position = _latestPosition;
    int batteryLevel;

    if (position == null) {
      _log("Stream еще не дал позицию. Пробуем получить последнюю известную...");
      position = await Geolocator.getLastKnownPosition();
      if (position == null) return;
    }

    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (e) {
      batteryLevel = 0;
    }

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
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'event': 'tracking',
      'shift_id': _activeShiftId,
    });

    final key = 'geo_buffer_$_activeShiftId';
    List<String> currentBuffer = prefs.getStringList(key) ?? [];
    currentBuffer.add(geoDataJson);

    try {
      await _sendGeoDataBatch(currentBuffer, _activeShiftId!);
      await prefs.remove(key);
      _log("✅ Успешно отправлено ${currentBuffer.length} точек (включая офлайн буфер)");
    } catch (e) {
      _log("❌ Ошибка отправки: $e, сохраняем в буфер (${currentBuffer.length} точек)...");
      if (currentBuffer.length > 1000) {
        currentBuffer.removeRange(0, currentBuffer.length - 1000);
      }
      await prefs.setStringList(key, currentBuffer);
    }
  } catch (e) {
    _log("Критическая ошибка в сборе данных: $e");
  }
}

Future<void> _sendGeoDataBatch(List<String> geoDataJsonList, int shiftId) async {
  final token = _bgAuthToken;
  if (token == null) {
    _log("Ошибка: Токен отсутствует в фоновом режиме.");
    throw Exception('JWT missing in background');
  }

  final dataList = geoDataJsonList.map((s) => jsonDecode(s)).toList();

  final res = await http.post(
    Uri.parse(AppConfig.geoTrackUrl),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'data': dataList
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

Future<bool> startBackgroundTracking({required int shiftId}) async {
  _log("startBackgroundTracking($shiftId)");

  // 1. Проверяем и запрашиваем геопозицию через Geolocator (он работает надежнее на iOS)
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _log("Location services are disabled.");
      // Мы не прерываем, чтобы кнопка включилась, а сервис попытается потом.
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        _log("Location denied, requesting...");
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _log("Location denied after request.");
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        _log("Location permanently denied.");
      }
    }

    // Попытка запросить Always доступ, если это возможно, но не критично для запуска
    var alwaysStatus = await Permission.locationAlways.status;
    if (alwaysStatus.isDenied) {
      await Permission.locationAlways.request();
    }
  } catch (e) {
    _log("Ошибка при запросе разрешений геолокации: $e");
    // Не прерываем запуск, позволим Geolocator внутри фонового процесса разобраться самому
  }

  // 2. Для Android запрашиваем отключение ограничений батареи
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      var batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        _log("IgnoreBatteryOptimizations not granted, requesting...");
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      _log("Ошибка при запросе ignoreBatteryOptimizations: $e");
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final isRunning = prefs.getBool(_SHARED_PREFS_BG_RUNNING_KEY) ?? false;
  final currentShift = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);

  _log("isRunning=$isRunning, currentShift=$currentShift");

  if (isRunning && currentShift == shiftId) return true;
  if (isRunning && currentShift != shiftId) await stopBackgroundTracking();

  final service = FlutterBackgroundService();
  final token = await _storage.read(key: 'jwt_token');

  // Сохраняем shiftId, токен и помечаем, что трекинг включён
  await prefs.setInt(_SHARED_PREFS_SHIFT_ID_KEY, shiftId);
  await prefs.setBool(_SHARED_PREFS_BG_RUNNING_KEY, true);
  if (token != null) {
    await prefs.setString(_SHARED_PREFS_TOKEN_KEY, token);
    _bgAuthToken = token;
  }

  try {
    bool isServiceActive = await service.isRunning();
    if (!isServiceActive) {
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
        ),
        iosConfiguration: IosConfiguration(
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );
    }
  } catch (e) {
    _log("Ошибка при конфигурации сервиса: $e");
  }

  await service.startService();
  _log("Фоновый сервис запущен.");
  return true;
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
  await prefs.remove(_SHARED_PREFS_TOKEN_KEY);
  _bgAuthToken = null;

  _log("Фоновый сервис остановлен.");
}

Future<bool> isBackgroundTrackingRunning() async {
  final prefs = await SharedPreferences.getInstance();
  final hasRunningFlag = prefs.getBool(_SHARED_PREFS_BG_RUNNING_KEY) ?? false;
  if (!hasRunningFlag) return false;

  // На iOS возвращаем статус на основе сохраненного флага предпочтений, так как 
  // фоновые процессы iOS сильно ограничены и вызов .isRunning() часто возвращает false.
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return true;
  }

  try {
    final isServiceRunning = await FlutterBackgroundService().isRunning();
    return isServiceRunning;
  } catch (e) {
    _log("Ошибка при проверке реального статуса сервиса: $e");
    return false;
  }
}
