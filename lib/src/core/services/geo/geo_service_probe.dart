import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';

int _requestSequence = 0;

Future<bool> ensureGeoService(FlutterBackgroundService service, int shiftId,
    {Duration timeout = const Duration(seconds: 3)}) async {
  if (!await service.isRunning().timeout(timeout)) {
    return service.startService().timeout(timeout);
  }
  var health = await requestGeoService(service, timeout: timeout);
  if (health?['running'] != true || health?['shift_id'] != shiftId) {
    health = await requestGeoService(service,
        method: 'restartGeo', reply: 'geoRestarted', timeout: timeout);
  }
  if (health?['running'] != true || health?['shift_id'] != shiftId)
    return false;
  service.invoke('syncGeo');
  return true;
}

/// Native service existence does not prove that its Dart worker is alive.
/// Correlate each reply, and cancel the listener even when the worker is silent.
Future<Map<String, dynamic>?> requestGeoService(
  FlutterBackgroundService service, {
  String method = 'geoPing',
  String reply = 'geoPong',
  Duration timeout = const Duration(seconds: 3),
}) async {
  final requestId =
      '${DateTime.now().microsecondsSinceEpoch}:${_requestSequence++}';
  final result = Completer<Map<String, dynamic>?>();
  final subscription = service.on(reply).listen((event) {
    if (event?['request_id'] == requestId && !result.isCompleted) {
      result.complete(event);
    }
  }, onError: (Object _) {
    if (!result.isCompleted) result.complete(null);
  });
  try {
    service.invoke(method, {'request_id': requestId});
    return await result.future.timeout(timeout, onTimeout: () => null);
  } finally {
    await subscription.cancel();
  }
}
