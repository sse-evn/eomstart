// lib/services/geo_tracking_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
DateTime? _lastSendTime; // Время последней отправки (для iOS throttle)
final FlutterSecureStorage _storage = const FlutterSecureStorage();

bool _serviceIsActuallyRunning = false;
int _consecutiveStreamErrors = 0;
bool _isSending = false; // Предотвращаем одновременную отправку из stream и timer

/// Собирает и отправляет геоданные — общая логика для timer и stream
Future<void> _collectAndSend(Position position) async {
  if (_isSending) return; // Другая отправка уже в процессе
  _isSending = true;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final currentActiveShiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);
    if (currentActiveShiftId == null) {
      _log("ShiftID отсутствует — пропускаем.");
      return;
    }

    _activeShiftId = currentActiveShiftId;

    final freshToken = prefs.getString(_SHARED_PREFS_TOKEN_KEY);
    if (freshToken != null) _bgAuthToken = freshToken;

    if (position.latitude == 0.0 || position.longitude == 0.0) {
      _log("Получена 0,0 позиция — пропуск");
      return;
    }

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
      'event': 'tracking',
      'shift_id': _activeShiftId,
    });

    final key = 'geo_buffer_$_activeShiftId';
    List<String> currentBuffer = prefs.getStringList(key) ?? [];
    currentBuffer.add(geoDataJson);

    try {
      await _sendGeoDataBatch(currentBuffer, _activeShiftId!);
      await prefs.remove(key);
      _lastSendTime = DateTime.now();
      _log("✅ Отправлено ${currentBuffer.length} точек (включая буфер)");
    } catch (e) {
      _log("❌ Ошибка отправки: $e, буферизуем (${currentBuffer.length} точек)");
      if (currentBuffer.length > 1000) {
        currentBuffer.removeRange(0, currentBuffer.length - 1000);
      }
      await prefs.setStringList(key, currentBuffer);
    }
  } catch (e) {
    _log("Критическая ошибка: $e");
  } finally {
    _isSending = false;
  }
}

/// Запускает или перезапускает position stream с автовосстановлением.
/// На iOS: stream — это ЕДИНСТВЕННЫЙ надёжный механизм, он сам отправляет данные.
/// На Android: stream кэширует позицию, а таймер отправляет.
void _startPositionStream() {
  _positionStreamSubscription?.cancel();
  _positionStreamSubscription = null;

  LocationSettings settings;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    settings = AppleSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0, // 0 = всегда обновлять, даже стоя на месте
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
      activityType: ActivityType.otherNavigation,
    );
  } else {
    settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 10),
    );
  }

  _log("Запуск Position Stream...");
  _positionStreamSubscription = Geolocator.getPositionStream(
    locationSettings: settings,
  ).listen(
    (position) {
      _latestPosition = position;
      _consecutiveStreamErrors = 0;

      // === На iOS: отправляем данные ПРЯМО ИЗ STREAM ===
      // iOS убивает Dart-таймер в фоне, но position stream работает,
      // потому что он привязан к нативному Core Location.
      // Throttle: отправляем не чаще раза в 15 секунд.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final now = DateTime.now();
        if (_lastSendTime == null ||
            now.difference(_lastSendTime!).inSeconds >= 15) {
          _collectAndSend(position);
        }
      }
    },
    onError: (error) {
      _log("❌ Position Stream ошибка: $error");
      _consecutiveStreamErrors++;
      final delay = Duration(seconds: (_consecutiveStreamErrors * 5).clamp(5, 60));
      _log("Перезапуск stream через ${delay.inSeconds} сек...");
      Future.delayed(delay, () {
        if (_serviceIsActuallyRunning) {
          _startPositionStream();
        }
      });
    },
    onDone: () {
      _log("⚠️ Position Stream завершился. Перезапуск через 5 сек...");
      Future.delayed(const Duration(seconds: 5), () {
        if (_serviceIsActuallyRunning) {
          _startPositionStream();
        }
      });
    },
    cancelOnError: false,
  );
}

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
  _consecutiveStreamErrors = 0;
  _lastSendTime = null;
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
    _latestPosition = null;
    _lastSendTime = null;
    _serviceIsActuallyRunning = false;
    service.stopSelf();
  });

  // Слушаем появление интернета, чтобы сразу отправить накопленный буфер
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
    if (!results.contains(ConnectivityResult.none)) {
      _log("🌐 Сеть восстановлена, пробуем отправить буфер...");
      if (_latestPosition != null) {
        await _collectAndSend(_latestPosition!);
      }
    }
  });

  // Запускаем Position Stream с автовосстановлением
  _startPositionStream();

  // Таймер — основной механизм на Android.
  // На iOS таймер работает как запасной вариант (пока приложение в foreground).
  // Когда iOS убьёт таймер в фоне, stream продолжит отправлять сам.
  _backgroundTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
    final pos = _latestPosition;
    if (pos == null) {
      _log("Таймер: нет позиции, пропуск.");
      return;
    }

    // Проверяем, не отправил ли уже stream за последние 10 сек (на iOS)
    if (_lastSendTime != null &&
        DateTime.now().difference(_lastSendTime!).inSeconds < 10) {
      _log("Таймер: stream уже отправил недавно, пропуск.");
      return;
    }

    await _collectAndSend(pos);

    if (service is AndroidServiceInstance) {
      final now = DateTime.now();
      service.setForegroundNotificationInfo(
        title: "Микромобильность",
        content:
            "Обновлено: ${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
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
    await prefs.reload();
    
    final shiftId = prefs.getInt(_SHARED_PREFS_SHIFT_ID_KEY);
    final token = prefs.getString(_SHARED_PREFS_TOKEN_KEY);

    if (shiftId == null || token == null) {
      _log("iOS BG: Нет shiftId или токена, пропускаем.");
      return true;
    }

    _bgAuthToken = token;
    _activeShiftId = shiftId;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) {
      _log("iOS BG: Позиция недоступна.");
      return true;
    }
    
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
      _log("iOS BG: Отправлено ${currentBuffer.length} точек");
    } catch (networkError) {
      _log("iOS BG: Ошибка сети, буферизуем (${currentBuffer.length} точек)");
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

Future<void> _sendGeoDataBatch(List<String> geoDataJsonList, int shiftId) async {
  final token = _bgAuthToken;
  if (token == null) {
    _log("Ошибка: Токен отсутствует.");
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
  ).timeout(const Duration(seconds: 15));

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

  // 1. Проверяем и запрашиваем геопозицию
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _log("Location services are disabled.");
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

    // Попытка запросить Always доступ — критично для iOS фонового трекинга
    var alwaysStatus = await Permission.locationAlways.status;
    if (alwaysStatus.isDenied) {
      await Permission.locationAlways.request();
    }
  } catch (e) {
    _log("Ошибка при запросе разрешений: $e");
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
      _log("Ошибка ignoreBatteryOptimizations: $e");
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
    _log("Ошибка конфигурации сервиса: $e");
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
  _positionStreamSubscription?.cancel();
  _positionStreamSubscription = null;
  _activeShiftId = null;
  _latestPosition = null;
  _lastSendTime = null;
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

  // На iOS возвращаем флаг из SharedPrefs, т.к. .isRunning() ненадежен
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return true;
  }

  try {
    final isServiceRunning = await FlutterBackgroundService().isRunning();
    return isServiceRunning;
  } catch (e) {
    _log("Ошибка проверки статуса сервиса: $e");
    return false;
  }
}
