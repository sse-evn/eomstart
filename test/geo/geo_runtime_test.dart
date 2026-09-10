import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micro_mobility_app/src/core/services/geo/geo_delivery.dart';
import 'package:micro_mobility_app/src/core/services/geo_tracking_service.dart';
import 'geo_delivery_test.dart' show MemoryGeoQueue, testToken;

class FakeGeo extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.always;
  late Position position;
  Future<Position>? pendingProbe;
  final positions = StreamController<Position>.broadcast();
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      pendingProbe ?? Future.value(position);
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      positions.stream;
}

Position pointAt(DateTime time, {double accuracy = 10}) => Position(
    longitude: 76.9,
    latitude: 43.2,
    timestamp: time,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGeo geo;
  late GeolocatorPlatform original;
  late MemoryGeoQueue queue;
  late GeoRuntime runtime;
  late DateTime now;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    now = DateTime.now().toUtc();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({geoShiftKey: 10});
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'read' ? testToken('1') : null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/battery'),
        (_) async => 90);
    original = GeolocatorPlatform.instance;
    geo = FakeGeo()..position = pointAt(now);
    GeolocatorPlatform.instance = geo;
    queue = MemoryGeoQueue();
    final delivery = GeoDelivery(
        queue: queue,
        client: MockClient((_) async => http.Response('', 503)),
        url: Uri.parse('https://example.invalid/api/geo'),
        readToken: () async => testToken('1'),
        refreshToken: () async => null);
    runtime =
        GeoRuntime(10, queue: queue, delivery: delivery, clock: () => now);
  });
  tearDown(() async {
    await runtime.stop();
    await geo.positions.close();
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/battery'), null);
  });
  test('turn GPS off and on repeatedly without stale points or exceptions',
      () async {
    await runtime.check();
    expect((await queue.read('1')).length, 1);
    for (int i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 30));
      geo.enabled = false;
      await runtime.check();
      expect((await SharedPreferences.getInstance()).getString(geoStateKey),
          'gps_disabled');
      expect((await queue.read('1')).length, i + 1);
      geo.enabled = true;
      now = now.add(const Duration(seconds: 30));
      geo.position = pointAt(now);
      await runtime.check();
      expect(
          (await SharedPreferences.getInstance()).getString(geoStateKey), 'ok');
      expect((await queue.read('1')).length, i + 2);
    }
  });
  test('cached old position is never timestamped as now', () async {
    geo.position = pointAt(now.subtract(const Duration(minutes: 5)));
    await runtime.check();
    expect(await queue.read('1'), isEmpty);
    expect((await SharedPreferences.getInstance()).getString(geoStateKey),
        'no_fix');
  });
  test('revoked permission gives warning and recovers after regrant', () async {
    geo.permission = LocationPermission.deniedForever;
    await runtime.check();
    expect(await queue.read('1'), isEmpty);
    expect((await SharedPreferences.getInstance()).getString(geoStateKey),
        'permission_denied');
    geo.permission = LocationPermission.always;
    now = now.add(const Duration(seconds: 30));
    geo.position = pointAt(now);
    await runtime.check();
    expect((await queue.read('1')).length, 1);
  });
  test('poor accuracy is reported without manufacturing a trustworthy position',
      () async {
    geo.position = pointAt(now, accuracy: 500);
    await runtime.check();
    expect(await queue.read('1'), isEmpty);
    expect((await SharedPreferences.getInstance()).getString(geoStateKey),
        'poor_accuracy');
  });
  test('closed local shift stops collection', () async {
    await (await SharedPreferences.getInstance()).remove(geoShiftKey);
    await runtime.check();
    expect(await queue.read('1'), isEmpty);
  });
  test('repeated cached fix is only stored once with original measurement time',
      () async {
    final measured = now;
    await runtime.check();
    now = now.add(const Duration(seconds: 20));
    await runtime.check();
    final points = await queue.read('1');
    expect(points.length, 1);
    expect(points.single['timestamp'], measured.toIso8601String());
  });

  Future<void> settleGeo() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('Android does not start a location service without its prerequisites',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    geo.enabled = false;
    expect(await startBackgroundTracking(shiftId: 10), false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(geoStateKey), 'gps_disabled');
    expect(prefs.getInt(geoShiftKey), 10);
    geo.enabled = true;
    geo.permission = LocationPermission.deniedForever;
    expect(await startBackgroundTracking(shiftId: 10), false);
    expect(prefs.getString(geoStateKey), 'permission_denied');
    expect(prefs.getInt(geoShiftKey), 10);
  });

  test('a delayed probe cannot overwrite a newer streamed measurement',
      () async {
    final probed = Completer<Position>();
    geo.pendingProbe = probed.future;
    final collecting = runtime.check();
    await settleGeo();
    final newest = pointAt(now.add(const Duration(seconds: 1)));
    geo.positions.add(newest);
    await settleGeo();
    probed.complete(pointAt(now.subtract(const Duration(seconds: 20))));
    await collecting;
    expect((await queue.read('1')).single['timestamp'],
        newest.timestamp.toIso8601String());
  });

  test('switching accounts cannot attach new user coordinates to the old shift',
      () async {
    await runtime.check();
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'read' ? testToken('2') : null);
    now = now.add(const Duration(seconds: 16));
    geo.positions.add(pointAt(now));
    await settleGeo();
    expect(await queue.read('2'), isEmpty);
    expect((await queue.read('1')).length, 1);
    expect(runtime.isHealthy, false);
  });

  test(
      'new fixes persist on both platforms while an earlier HTTP request waits',
      () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await runtime.stop();
      debugDefaultTargetPlatformOverride = platform;
      queue = MemoryGeoQueue();
      final started = Completer<void>();
      final response = Completer<http.Response>();
      List<dynamic> sent = [];
      runtime = GeoRuntime(10,
          queue: queue,
          clock: () => now,
          delivery: GeoDelivery(
              queue: queue,
              client: MockClient((request) async {
                sent = jsonDecode(request.body)['data'] as List;
                started.complete();
                return response.future;
              }),
              url: Uri.parse('https://example.invalid/api/geo'),
              readToken: () async => testToken('1'),
              refreshToken: () async => null));
      geo.position = pointAt(now);
      await runtime.check();
      await started.future;
      for (int i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 16));
        geo.positions.add(pointAt(now));
        await settleGeo();
      }
      expect((await queue.read('1')).length, 4);
      expect(sent.length, 1);
      response.complete(http.Response(jsonEncode({'points_saved': 1}), 200));
      await runtime.flush();
      expect((await queue.read('1')).length, 3);
      expect(runtime.isHealthy, true);
    }
  });

  test(
      'failed shift verification never stops collection; confirmed closure does',
      () async {
    await runtime.stop();
    bool unavailable = true;
    runtime = GeoRuntime(10,
        queue: queue,
        clock: () => now,
        readActiveShift: () async {
          if (unavailable) throw const SocketException('offline');
          return null;
        },
        delivery: GeoDelivery(
            queue: queue,
            client: MockClient((_) async => http.Response('', 503)),
            url: Uri.parse('https://example.invalid/api/geo'),
            readToken: () async => testToken('1'),
            refreshToken: () async => null));
    await runtime.check();
    await runtime.verifyShift();
    expect((await SharedPreferences.getInstance()).getInt(geoShiftKey), 10);
    expect(runtime.isHealthy, true);
    unavailable = false;
    now = now.add(const Duration(minutes: 2));
    await runtime.verifyShift();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(geoShiftKey), isNull);
    expect(prefs.getInt(geoClosedShiftKey), 10);
    expect(runtime.isHealthy, false);
    expect((await queue.read('1')).length, 1);
  });

  test('server closure for a previous runtime cannot close a newer shift',
      () async {
    await runtime.stop();
    final active = Completer<int?>();
    runtime = GeoRuntime(10,
        queue: queue,
        clock: () => now,
        readActiveShift: () => active.future,
        delivery: GeoDelivery(
            queue: queue,
            client: MockClient((_) async => http.Response('', 503)),
            url: Uri.parse('https://example.invalid/api/geo'),
            readToken: () async => testToken('1'),
            refreshToken: () async => null));
    final verifying = runtime.verifyShift();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(geoShiftKey, 11);
    active.complete(null);
    await verifying;
    expect(prefs.getInt(geoShiftKey), 11);
    expect(prefs.getInt(geoClosedShiftKey), isNull);
  });

  test('stream errors recover repeatedly and fresh samples resume', () async {
    await runtime.check();
    for (int i = 0; i < 3; i++) {
      geo.positions.addError(StateError('GPS interrupted'));
      await settleGeo();
      now = now.add(const Duration(seconds: 16));
      await runtime.check();
      geo.positions.add(pointAt(now));
      await settleGeo();
      expect((await queue.read('1')).length, i + 2);
    }
  });

  test('empty status acknowledgement never marks a GPS upload as fresh',
      () async {
    await runtime.stop();
    runtime = GeoRuntime(10,
        queue: queue,
        clock: () => now,
        delivery: GeoDelivery(
            queue: queue,
            client: MockClient((_) async => http.Response(
                '{"status":"ok","message":"No points received"}', 200)),
            url: Uri.parse('https://example.invalid/api/geo'),
            readToken: () async => testToken('1'),
            refreshToken: () async => null));
    geo.enabled = false;
    await runtime.check();
    await runtime.flush();
    expect((await SharedPreferences.getInstance()).getInt(geoLastUploadKey),
        isNull);
  });

  test('two simulated hours survive outages and repeated permission changes',
      () async {
    await runtime.stop();
    bool online = true;
    final accepted = <String>{};
    runtime = GeoRuntime(10,
        queue: queue,
        clock: () => now,
        delivery: GeoDelivery(
            queue: queue,
            client: MockClient((request) async {
              if (!online) throw const SocketException('offline');
              final data = jsonDecode(request.body)['data'] as List;
              accepted.addAll(data.map((p) => p['point_id'] as String));
              return http.Response(
                  jsonEncode({'status': 'ok', 'points_saved': data.length}),
                  200);
            }),
            url: Uri.parse('https://example.invalid/api/geo'),
            readToken: () async => testToken('1'),
            refreshToken: () async => null));
    for (int i = 0; i < 480; i++) {
      now = now.add(const Duration(seconds: 15));
      online = i % 60 >= 10;
      geo.enabled = i % 90 != 0;
      geo.permission = i % 100 == 0
          ? LocationPermission.deniedForever
          : LocationPermission.always;
      geo.position = pointAt(now);
      geo.positions.add(geo.position);
      await settleGeo();
      await runtime.check();
      await runtime.flush();
      expect(runtime.isHealthy, true);
      expect((await SharedPreferences.getInstance()).getInt(geoShiftKey), 10);
    }
    online = true;
    await runtime.flush(force: true);
    expect(accepted.length, greaterThan(400));
    expect(await queue.read('1'), isEmpty);
  });
}
