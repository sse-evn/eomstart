import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_mobility_app/src/core/services/geo/geo_service_probe.dart';

class FakeService extends Fake implements FlutterBackgroundService {
  bool nativeRunning = true;
  bool workerHealthy = true;
  bool respond = true;
  int shiftId = 10;
  int starts = 0, restarts = 0;
  final messages = <String>[];
  final streams = <String, StreamController<Map<String, dynamic>?>>{};
  StreamController<Map<String, dynamic>?> channel(String name) =>
      streams.putIfAbsent(name, () => StreamController.broadcast(sync: true));
  @override
  Stream<Map<String, dynamic>?> on(String method) => channel(method).stream;
  @override
  Future<bool> isRunning() async => nativeRunning;
  @override
  Future<bool> startService() async {
    starts++;
    return true;
  }

  @override
  void invoke(String method, [Map<String, dynamic>? arg]) {
    messages.add(method);
    if (!respond) return;
    if (method == 'restartGeo') {
      restarts++;
      workerHealthy = true;
      shiftId = 10;
    }
    if (method == 'geoPing' || method == 'restartGeo') {
      channel(method == 'geoPing' ? 'geoPong' : 'geoRestarted').add({
        'request_id': arg?['request_id'],
        'running': workerHealthy,
        'shift_id': shiftId,
      });
    }
  }

  Future<void> dispose() async {
    for (final stream in streams.values) {
      await stream.close();
    }
  }
}

void main() {
  late FakeService service;
  setUp(() => service = FakeService());
  tearDown(() => service.dispose());
  test('cold process starts despite any previous persisted running flag',
      () async {
    service.nativeRunning = false;
    expect(await ensureGeoService(service, 10), true);
    expect(service.starts, 1);
  });
  test('native service with unhealthy worker is recovered', () async {
    service.workerHealthy = false;
    expect(await ensureGeoService(service, 10), true);
    expect(service.restarts, 1);
    expect(service.messages.last, 'syncGeo');
  });
  test('healthy worker belonging to another shift is replaced', () async {
    service.shiftId = 9;
    expect(await ensureGeoService(service, 10), true);
    expect(service.restarts, 1);
  });
  test('healthy worker is not repeatedly restarted', () async {
    for (int i = 0; i < 5; i++) {
      expect(await ensureGeoService(service, 10), true);
    }
    expect(service.restarts, 0);
    expect(service.starts, 0);
  });
  test(
      'unresponsive native service is not reported as healthy; listeners close',
      () async {
    service.respond = false;
    expect(
        await ensureGeoService(service, 10,
            timeout: const Duration(milliseconds: 10)),
        false);
    expect(service.channel('geoPong').hasListener, false);
    expect(service.channel('geoRestarted').hasListener, false);
  });
  test('a delayed response from an older probe cannot satisfy a new one',
      () async {
    service.respond = false;
    final pending =
        requestGeoService(service, timeout: const Duration(milliseconds: 10));
    service
        .channel('geoPong')
        .add({'request_id': 'old', 'running': true, 'shift_id': 10});
    expect(await pending, isNull);
    expect(service.channel('geoPong').hasListener, false);
  });
}
