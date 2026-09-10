import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:micro_mobility_app/src/core/services/geo_tracking_service.dart';
import 'package:micro_mobility_app/src/features/app/models/active_shift.dart';
import 'geo_delivery_test.dart' show testToken;

class ShiftApi extends ApiService {
  bool unavailable = true;
  @override
  Future<ActiveShift?> getActiveShift(String token) async {
    if (unavailable) throw const SocketException('temporarily offline');
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');
  late ShiftProvider provider;
  late SharedPreferences prefs;
  late ShiftApi api;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(storageChannel,
        (call) async => call.method == 'read' ? testToken('1') : null);
    messenger.setMockMethodCallHandler(connectivityChannel, (_) async => null);
    SharedPreferences.setMockInitialValues({geoShiftKey: 10});
    prefs = await SharedPreferences.getInstance();
    api = ShiftApi();
  });
  tearDown(() {
    provider.dispose();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(storageChannel, null);
    messenger.setMockMethodCallHandler(connectivityChannel, null);
  });
  Future<void> createProvider() async {
    provider = ShiftProvider(
        apiService: api,
        storage: const FlutterSecureStorage(),
        prefs: prefs,
        initialToken: testToken('1'));
    await provider.initialized;
  }

  test('offline startup with unknown shift does not clear persisted tracking',
      () async {
    await createProvider();
    await provider.syncGeoTrackingWithShiftState();
    expect(prefs.getInt(geoShiftKey), 10);
    expect(await provider.getTrackingShiftId(), 10);
  });
  test('failed refresh retains cached active shift and tracking', () async {
    await prefs.setString(
        'shifts_cache',
        jsonEncode({
          'timestamp': DateTime.now().toIso8601String(),
          'shifts': [],
          'activeShift': {
            'id': 10,
            'user_id': 1,
            'username': 'worker',
            'slot_time_range': '00:00-23:59',
            'start_time': DateTime.now().toIso8601String(),
            'is_active': true
          },
        }));
    await createProvider();
    expect((await provider.getActiveShift())?.id, 10);
    expect(provider.activeShift?.id, 10);
    expect(prefs.getInt(geoShiftKey), 10);
  });
  test('only a confirmed absent shift clears persisted tracking', () async {
    await createProvider();
    api.unavailable = false;
    await provider.syncGeoTrackingWithShiftState();
    expect(prefs.getInt(geoShiftKey), isNull);
    expect(provider.activeShift, isNull);
    expect(await provider.getTrackingShiftId(), isNull);
  });
}
