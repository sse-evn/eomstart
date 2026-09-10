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
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'api_service.dart';
import 'geo/geo_delivery.dart';
import 'geo/geo_queue.dart';
import 'geo/geo_service_probe.dart';

const geoShiftKey = 'active_shift_id_for_bg_service';
const geoStateKey = 'geo_tracking_state';
const geoCheckedKey = 'geo_tracking_checked_at';
const geoLastUploadKey = 'geo_last_upload_at';
const geoDeliveryStateKey = 'geo_delivery_state';
const geoClosedShiftKey = 'geo_closed_shift_id';
const geoOwnerKey = 'geo_tracking_user_id';
const _storage = FlutterSecureStorage();
GeoRuntime? _runtime;
Future<bool>? _starting;
Future<void>? _stopping;
bool _configured = false;
int _generation = 0;

bool get supportsGeoTracking =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

GeoDelivery _makeDelivery(GeoQueue queue) => GeoDelivery(
    queue: queue,
    client: http.Client(),
    clientFactory: http.Client.new,
    url: Uri.parse(AppConfig.geoTrackUrl),
    readToken: () => _storage.read(key: 'jwt_token'),
    refreshToken: _refreshGeoToken);

Future<String?> _refreshGeoToken() async {
  final api = ApiService(clearRejectedSession: false);
  try {
    return await api.refreshToken();
  } finally {
    api.close();
  }
}

Future<int?> _readActiveShiftId() async {
  final token = await _storage.read(key: 'jwt_token');
  if (token == null) throw StateError('No authenticated session');
  final api = ApiService(clearRejectedSession: false);
  try {
    return (await api.getActiveShift(token))?.id;
  } finally {
    api.close();
  }
}

GeoRuntime _newRuntime(int shiftId,
        {ServiceInstance? service, String? ownerUserId}) =>
    GeoRuntime(shiftId,
        service: service,
        ownerUserId: ownerUserId,
        readActiveShift: _readActiveShiftId);

/// A live runtime is the source of truth, never a persisted "running" flag.
class GeoRuntime {
  final int shiftId;
  final ServiceInstance? service;
  final GeoQueue queue;
  late final GeoDelivery delivery;
  final DateTime Function() clock;
  final Future<int?> Function()? readActiveShift;
  Timer? _timer;
  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _gpsStatus;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Position? _latest;
  bool _stopped = false;
  bool _checking = false;
  bool _started = false;
  Future<void>? _uploading;
  Future<void>? _verifyingShift;
  DateTime? _lastCheckCompleted, _startedAt, _lastShiftCheck, _retryAt;
  DateTime? _streamStartedAt, _lastStreamEvent;
  int _failures = 0;
  DateTime? _lastCapture, _lastProbe, _lastReport;
  DateTime? _lastMeasurement;
  String? _lastPointID;
  String? _owner;
  String _state = 'no_fix';

  GeoRuntime(this.shiftId,
      {this.service,
      GeoQueue? queue,
      GeoDelivery? delivery,
      String? ownerUserId,
      this.readActiveShift,
      DateTime Function()? clock})
      : queue = queue ?? SqliteGeoQueue(),
        _owner = ownerUserId,
        clock = clock ?? DateTime.now {
    this.delivery = delivery ?? _makeDelivery(this.queue);
  }

  bool get isHealthy {
    if (_stopped) return false;
    final checked = _lastCheckCompleted ?? _startedAt;
    return checked != null &&
        clock().difference(checked) < const Duration(seconds: 90);
  }

  Future<void> start() async {
    if (_started || _stopped) return;
    _started = true;
    _startedAt = clock();
    _gpsStatus = Geolocator.getServiceStatusStream().listen((status) {
      _lastProbe = null;
      if (status == ServiceStatus.disabled) _latest = null;
      unawaited(check());
    }, onError: (Object error) => debugPrint('Geo service status: $error'));
    _connectivity = Connectivity().onConnectivityChanged.listen((_) {
      _retryAt = null;
      _failures = 0;
      unawaited(check());
    }, onError: (Object error) => debugPrint('Geo connectivity: $error'));
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => unawaited(check()));
    try {
      await _migrateLegacyBuffer().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Geo legacy buffer retained: $e');
    }
    await check();
  }

  Future<void> _migrateLegacyBuffer() async {
    final user =
        GeoDelivery.userFromToken(await _storage.read(key: 'jwt_token'));
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    // Legacy buffers have no owner. Only migrate the currently authenticated shift.
    final key = 'geo_buffer_$shiftId';
    final items = prefs.getStringList(key) ?? [];
    for (final item in items) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is! Map<String, dynamic>) continue;
        final point = decoded;
        final timestamp =
            DateTime.tryParse(point['timestamp']?.toString() ?? '');
        if (timestamp == null) continue;
        point['point_id'] =
            '$user:$shiftId:${timestamp.microsecondsSinceEpoch}';
        await queue.add(user, point);
      } on FormatException {
        continue;
      }
    }
    if (items.isNotEmpty) await prefs.remove(key);
  }

  Future<void> _cancelPositionStream() async {
    final stream = _positions;
    _positions = null;
    await stream?.cancel().timeout(const Duration(seconds: 3));
  }

  void _ensurePositionStream() {
    if (_positions != null || _stopped) return;
    _streamStartedAt = clock();
    final LocationSettings settings =
        defaultTargetPlatform == TargetPlatform.iOS
            ? AppleSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 0,
                allowBackgroundLocationUpdates: true,
                showBackgroundLocationIndicator: true,
                pauseLocationUpdatesAutomatically: false,
                activityType: ActivityType.otherNavigation)
            : AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 0,
                intervalDuration: const Duration(seconds: 15));
    _positions =
        Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      if (_stopped) return;
      _latest = p;
      _lastStreamEvent = clock();
      // Native Core Location events drive uploads on iOS when Dart timers are suspended.
      unawaited(check());
    }, onError: (Object error) {
      _latest = null;
      unawaited(_cancelPositionStream().catchError((Object _) {}));
      // The watchdog retries once per tick, avoiding recursive restart storms.
    }, onDone: () {
      _positions = null;
    }, cancelOnError: true);
  }

  Future<void> check() async {
    if (_stopped || _checking) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload().timeout(const Duration(seconds: 5));
      if (prefs.getInt(geoShiftKey) != shiftId) {
        await stop();
        return;
      }
      final enabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5));
      final permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5));
      if (!enabled ||
          permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _state = !enabled ? 'gps_disabled' : 'permission_denied';
        _latest = null;
        _lastProbe = null;
        await _cancelPositionStream();
      } else {
        final streamAt = _lastStreamEvent ?? _streamStartedAt;
        if (_positions != null &&
            streamAt != null &&
            clock().difference(streamAt) > const Duration(seconds: 60)) {
          await _cancelPositionStream();
          _lastStreamEvent = null;
        }
        _ensurePositionStream();
        final now = clock();
        if ((_latest == null || !isFreshGeoPoint(_latest!.timestamp, now)) &&
            (_lastProbe == null ||
                now.difference(_lastProbe!) >= const Duration(seconds: 45))) {
          _lastProbe = now;
          try {
            final probed = await Geolocator.getCurrentPosition(
                    locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.high,
                        timeLimit: Duration(seconds: 8)))
                .timeout(const Duration(seconds: 8));
            if (_latest == null ||
                probed.timestamp.isAfter(_latest!.timestamp)) {
              _latest = probed;
            }
          } catch (_) {
            await _cancelPositionStream();
            _ensurePositionStream();
          }
        }
        if (_stopped) return;
        final position = _latest;
        if (position == null || !isFreshGeoPoint(position.timestamp, clock())) {
          _state = 'no_fix';
        } else if (!position.accuracy.isFinite ||
            position.accuracy < 0 ||
            position.accuracy > 100) {
          _state = 'poor_accuracy';
        } else {
          _state = 'ok';
          await _capture(position);
        }
      }
      if (_stopped) return;
      await prefs.setString(geoStateKey, _state);
      await prefs.setInt(geoCheckedKey, clock().millisecondsSinceEpoch);
      // Network I/O must never hold the collection lock. Each fix is durable
      // before sending, and slow uploads do not prevent the next capture.
      unawaited(flush());
      unawaited(verifyShift());
      await _updateNotification(prefs);
    } catch (error) {
      debugPrint('Geo check failed; will retry: $error');
      if (!_stopped) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              geoStateKey, _state == 'storage_error' ? _state : 'stopped');
        } catch (_) {}
      }
    } finally {
      _lastCheckCompleted = clock();
      _checking = false;
    }
  }

  Future<void> _capture(Position p) async {
    final now = clock();
    if (_stopped ||
        (_lastMeasurement != null && !p.timestamp.isAfter(_lastMeasurement!)) ||
        (_lastCapture != null &&
            now.difference(_lastCapture!) < const Duration(seconds: 15)))
      return;
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180 ||
        (p.latitude == 0 && p.longitude == 0)) {
      _state = 'no_fix';
      return;
    }
    final user = GeoDelivery.userFromToken(await _storage
        .read(key: 'jwt_token')
        .timeout(const Duration(seconds: 5)));
    if (user == null) {
      _state = 'auth_required';
      return;
    }
    if (_owner != null && _owner != user) {
      await stop();
      return;
    }
    _owner = user;
    final pointID = '$user:$shiftId:${p.timestamp.microsecondsSinceEpoch}';
    if (pointID == _lastPointID) return;
    int battery = 0;
    try {
      battery =
          (await Battery().batteryLevel.timeout(const Duration(seconds: 2)))
              .clamp(0, 100);
    } catch (_) {}
    if (_stopped) return;
    try {
      await queue.add(user, {
        'point_id': pointID,
        'shift_id': shiftId,
        'lat': p.latitude,
        'lon': p.longitude,
        'speed': p.speed.isFinite ? p.speed.clamp(0, double.infinity) : 0,
        'accuracy': p.accuracy,
        'battery': battery,
        'timestamp': p.timestamp.toUtc().toIso8601String(),
        'event': 'tracking',
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      _state = 'storage_error';
      rethrow;
    }
    _lastPointID = pointID;
    _lastMeasurement = p.timestamp;
    _lastCapture = now;
  }

  Future<void> flush({bool force = false}) {
    if (_stopped) return Future<void>.value();
    if (_uploading != null) return _uploading!;
    if (!force && _retryAt != null && clock().isBefore(_retryAt!)) {
      return Future<void>.value();
    }
    return _uploading = _flush().whenComplete(() => _uploading = null);
  }

  Future<void> _flush() async {
    try {
      final reportDue = _lastReport == null ||
          clock().difference(_lastReport!) >= const Duration(seconds: 30);
      final result = await delivery.send(
          tracking: reportDue ? {'shift_id': shiftId, 'state': _state} : null);
      if (_stopped) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (_stopped || prefs.getInt(geoShiftKey) != shiftId) return;
      if (result.contacted && reportDue) _lastReport = clock();
      final acceptedAt = result.latestAcceptedAt;
      if (acceptedAt != null) {
        final previous = prefs.getInt(geoLastUploadKey) ?? 0;
        if (acceptedAt.millisecondsSinceEpoch > previous) {
          await prefs.setInt(
              geoLastUploadKey, acceptedAt.millisecondsSinceEpoch);
        }
      }
      if (result.attempted || result.unauthorized) {
        final state = result.unauthorized
            ? 'auth_required'
            : result.rejectedCount > 0 ||
                    (result.contacted && !result.delivered)
                ? 'delivery_pending'
                : result.delivered
                    ? 'ok'
                    : 'offline';
        await prefs.setString(geoDeliveryStateKey, state);
        if (result.delivered) {
          _failures = 0;
          _retryAt = null;
        } else {
          _failures = (_failures + 1).clamp(1, 4);
          _retryAt =
              clock().add(Duration(seconds: 15 * (1 << (_failures - 1))));
        }
      }
      if (result.shiftActive == false) {
        await _closeConfirmedShift();
      } else {
        await _updateNotification(prefs);
      }
    } catch (e) {
      debugPrint('Geo upload retry: $e');
    }
  }

  Future<void> verifyShift() {
    if (_stopped || readActiveShift == null) return Future<void>.value();
    if (_verifyingShift != null) return _verifyingShift!;
    if (_lastShiftCheck != null &&
        clock().difference(_lastShiftCheck!) < const Duration(minutes: 2)) {
      return Future<void>.value();
    }
    _lastShiftCheck = clock();
    return _verifyingShift =
        _verifyShift().whenComplete(() => _verifyingShift = null);
  }

  Future<void> _verifyShift() async {
    try {
      final active =
          await readActiveShift!().timeout(const Duration(seconds: 50));
      if (!_stopped && active != shiftId) await _closeConfirmedShift();
    } catch (e) {
      // An unavailable API is not evidence that the employee ended their shift.
      debugPrint('Geo shift verification deferred: $e');
    }
  }

  Future<void> _closeConfirmedShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (_stopped || prefs.getInt(geoShiftKey) != shiftId) return;
    await prefs.setInt(geoClosedShiftKey, shiftId);
    await prefs.remove(geoShiftKey);
    await stop();
  }

  Future<void> _updateNotification(SharedPreferences prefs) async {
    if (_stopped || service is! AndroidServiceInstance) return;
    final deliveryState = prefs.getString(geoDeliveryStateKey) ?? 'ok';
    final fresh =
        clock().millisecondsSinceEpoch - (prefs.getInt(geoLastUploadKey) ?? 0) <
            90000;
    await (service as AndroidServiceInstance)
        .setForegroundNotificationInfo(
            title: 'EOM START · смена открыта',
            content: geoWarningText(_state) ??
                geoWarningText(deliveryState) ??
                (fresh
                    ? 'Геопозиция передаётся'
                    : 'Координаты записываются. Ожидаем подтверждения сервера.'))
        .timeout(const Duration(seconds: 3));
  }

  Future<void> stop({bool stopService = true}) async {
    _stopped = true;
    _timer?.cancel();
    delivery.close();
    try {
      await _cancelPositionStream();
      await _gpsStatus?.cancel().timeout(const Duration(seconds: 3));
      await _connectivity?.cancel().timeout(const Duration(seconds: 3));
    } finally {
      _latest = null;
      if (stopService && service != null) await service!.stopSelf();
    }
  }
}

String? geoWarningText(String state) {
  switch (state) {
    case 'gps_disabled':
      return 'Смена открыта. Включите геолокацию — маршрут не записывается.';
    case 'permission_denied':
      return 'Разрешите приложению доступ к геопозиции в настройках.';
    case 'no_fix':
      return 'Не удаётся получить свежие координаты. Проверьте GPS.';
    case 'poor_accuracy':
      return 'Низкая точность GPS. Выйдите на открытое место.';
    case 'offline':
      return 'Нет связи с сервером. Маршрут сохраняется на телефоне.';
    case 'stopped':
      return 'Геотрекинг восстанавливается. Проверьте разрешения приложения.';
    case 'auth_required':
      return 'Не удалось подтвердить вход. Откройте профиль и проверьте авторизацию.';
    case 'storage_error':
      return 'Не удаётся сохранить маршрут на телефоне. Проверьте свободное место.';
    case 'delivery_pending':
      return 'Сервер не подтвердил все координаты. Данные сохранены на телефоне.';
    case 'battery_optimization':
      return 'Разрешите приложению работу без ограничений батареи, чтобы маршрут записывался при выключенном экране.';
    case 'background_permission':
      return 'Для работы при свёрнутом приложении разрешите геолокацию «Всегда».';
  }
  return null;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final shiftId = prefs.getInt(geoShiftKey);
    if (shiftId == null) {
      await service.stopSelf();
      return;
    }
    bool stopping = false;
    Future<void>? restarting;
    Future<void> restart() async {
      if (restarting != null) return restarting;
      Future<void> replace() async {
        await _runtime?.stop(stopService: false);
        await prefs.reload();
        final active = prefs.getInt(geoShiftKey);
        if (stopping || active == null) return;
        _runtime = _newRuntime(active,
            service: service, ownerUserId: prefs.getString(geoOwnerKey));
        await _runtime!.start();
      }

      restarting = replace();
      try {
        await restarting;
      } finally {
        restarting = null;
      }
    }

    service.on('stopTracking').listen((event) async {
      stopping = true;
      try {
        await _runtime?.stop(stopService: false);
      } catch (e) {
        debugPrint('Geo stop: $e');
      } finally {
        service.invoke('geoStopped', {'request_id': event?['request_id']});
        await service.stopSelf();
      }
    });
    service.on('geoPing').listen((event) {
      service.invoke('geoPong', {
        'request_id': event?['request_id'],
        'shift_id': _runtime?.shiftId,
        'running': !stopping && (_runtime?.isHealthy ?? false),
      });
    });
    service.on('restartGeo').listen((event) async {
      try {
        if (!stopping) await restart();
        service.invoke('geoRestarted', {
          'request_id': event?['request_id'],
          'shift_id': _runtime?.shiftId,
          'running': !stopping && (_runtime?.isHealthy ?? false),
        });
      } catch (e) {
        debugPrint('Geo recovery: $e');
      }
    });
    service.on('syncGeo').listen((event) {
      unawaited(_runtime?.check() ?? Future<void>.value());
      if (event?['force'] == true) {
        unawaited(_runtime?.flush(force: true) ?? Future<void>.value());
      }
    });
    if (service is AndroidServiceInstance)
      await service.setAsForegroundService();
    await restart();
  } catch (error) {
    debugPrint('Geo startup failed: $error');
    await _runtime?.stop();
    await service.stopSelf();
  }
}

// Retained for installations with an old registered background callback. Background
// fetch is a short flush opportunity, never the mechanism for continuous iOS GPS.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return (await _sendQueued()).delivered;
}

Future<void> requestGeoPermissions() async {
  try {
    if (await Geolocator.checkPermission() == LocationPermission.denied)
      await Geolocator.requestPermission();
    if (await Permission.locationAlways.isDenied)
      await Permission.locationAlways.request();
    if (defaultTargetPlatform == TargetPlatform.android &&
        await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  } catch (e) {
    debugPrint('Geo permissions: $e');
  }
}

Future<bool> startBackgroundTracking(
    {required int shiftId, bool requestPermissions = false}) async {
  if (!supportsGeoTracking || shiftId <= 0) return false;
  if (_stopping != null) await _stopping;
  // Serialize starts from ShiftBloc, ShiftProvider and lifecycle recovery.
  if (_starting != null) {
    await _starting;
    return startBackgroundTracking(
        shiftId: shiftId, requestPermissions: requestPermissions);
  }
  final generation = _generation;
  final operation = _start(shiftId, requestPermissions, generation);
  _starting = operation;
  try {
    return await operation;
  } finally {
    _starting = null;
  }
}

Future<bool> _start(int shiftId, bool askPermissions, int generation) async {
  try {
    if (askPermissions) await requestGeoPermissions();
    if (generation != _generation) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getInt(geoClosedShiftKey) == shiftId) return false;
    final user = GeoDelivery.userFromToken(await _storage
        .read(key: 'jwt_token')
        .timeout(const Duration(seconds: 5)));
    if (user == null) return false;
    final previous = prefs.getInt(geoShiftKey);
    if (previous != null && previous != shiftId) await _stopRuntime();
    if (generation != _generation) return false;
    await prefs.setInt(geoShiftKey, shiftId);
    await prefs.setString(geoOwnerKey, user);
    if (previous != shiftId) {
      await prefs.remove(geoLastUploadKey);
      await prefs.remove(geoCheckedKey);
      await prefs.remove(geoDeliveryStateKey);
      await prefs.setString(geoStateKey, 'no_fix');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (!_configured) {
        for (final key in ['jwt_token', 'refresh_token']) {
          final value = await _storage.read(key: key);
          if (value != null)
            await _storage.write(
                key: key,
                value: value,
                iOptions: const IOSOptions(
                    accessibility: KeychainAccessibility.first_unlock));
        }
        await FlutterBackgroundService().configure(
            androidConfiguration: AndroidConfiguration(
                onStart: onStart, isForegroundMode: true, autoStart: false),
            iosConfiguration: IosConfiguration(
                autoStart: false, onBackground: onIosBackground));
        _configured = true;
      }
      // Keep Core Location on the main Flutter engine. A saved flag from an old
      // process cannot prevent startup; native events wake this engine in background.
      if (_runtime == null ||
          !_runtime!.isHealthy ||
          _runtime!._owner != user ||
          _runtime!.shiftId != shiftId) {
        await _runtime?.stop();
        final runtime = _newRuntime(shiftId, ownerUserId: user);
        _runtime = runtime;
        unawaited(runtime.start().catchError((Object e) async {
          debugPrint('Geo start: $e');
          await runtime.stop();
        }));
      } else {
        unawaited(_runtime!.check());
      }
      return true;
    }
    // Android 14+ requires location services and permission before starting a
    // location foreground service. Starting it first can terminate the app.
    final enabled = await Geolocator.isLocationServiceEnabled()
        .timeout(const Duration(seconds: 5));
    final permission =
        await Geolocator.checkPermission().timeout(const Duration(seconds: 5));
    if (!enabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await prefs.setString(
          geoStateKey, !enabled ? 'gps_disabled' : 'permission_denied');
      return false;
    }
    final service = FlutterBackgroundService();
    if (!_configured) {
      await service.configure(
          androidConfiguration: AndroidConfiguration(
              onStart: onStart,
              autoStart: false,
              autoStartOnBoot: false,
              isForegroundMode: true,
              foregroundServiceTypes: [AndroidForegroundType.location],
              initialNotificationTitle: 'EOM START',
              initialNotificationContent: 'Восстанавливаем геолокацию'),
          iosConfiguration: IosConfiguration(autoStart: false));
      _configured = true;
    }
    if (generation != _generation) return false;
    final ready = await ensureGeoService(service, shiftId);
    return generation == _generation && ready;
  } catch (error) {
    debugPrint('Geo start failed: $error');
    return false;
  }
}

Future<void> _stopRuntime() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await _runtime?.stop();
    _runtime = null;
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      await requestGeoService(service,
          method: 'stopTracking', reply: 'geoStopped');
    }
  }
}

Future<void> stopBackgroundTracking() {
  if (!supportsGeoTracking) return Future<void>.value();
  if (_stopping != null) return _stopping!;
  _generation++;
  final stopping = _stopTracking();
  _stopping = stopping;
  return stopping.whenComplete(() {
    _stopping = null;
  });
}

Future<void> _stopTracking() async {
  if (_starting != null) await _starting;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(geoShiftKey);
  await prefs.remove(geoOwnerKey);
  try {
    await _stopRuntime();
  } catch (e) {
    debugPrint('Geo stop failed: $e');
  }
  await prefs.remove('is_bg_geo_tracking_running');
  await prefs.remove('bg_geo_auth_token');
  await prefs.remove(geoCheckedKey);
  await prefs.remove(geoStateKey);
  await prefs.remove(geoDeliveryStateKey);
  // Closed-shift packets remain queued and may be sent with the next authenticated run.
}

Future<bool> isBackgroundTrackingRunning() async {
  if (defaultTargetPlatform == TargetPlatform.iOS)
    return _runtime?.isHealthy ?? false;
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) return false;
    final health = await requestGeoService(service);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return health?['running'] == true &&
        health?['shift_id'] == prefs.getInt(geoShiftKey);
  } catch (_) {
    return false;
  }
}

Future<void> flushBufferedGeoData() async {
  if (!supportsGeoTracking) return;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    if (_runtime != null && !_runtime!._stopped) {
      await _runtime!.check();
      await _runtime!.flush(force: true);
      return;
    }
  } else if (await isBackgroundTrackingRunning()) {
    FlutterBackgroundService().invoke('syncGeo', {'force': true});
    return;
  }
  await _sendQueued();
}

Future<void> reportForegroundGeoStatus(int shiftId, String state) async {
  if (!supportsGeoTracking || await isBackgroundTrackingRunning()) return;
  await _sendQueued(tracking: {'shift_id': shiftId, 'state': state});
}

Future<GeoDeliveryResult> _sendQueued({Map<String, dynamic>? tracking}) async {
  final delivery = _makeDelivery(SqliteGeoQueue());
  try {
    return await delivery
        .send(tracking: tracking)
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    return const GeoDeliveryResult(false);
  } finally {
    delivery.close();
  }
}
