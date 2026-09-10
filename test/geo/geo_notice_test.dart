import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/core/services/geo/geo_tracking_notice.dart';
import 'package:micro_mobility_app/src/core/services/geo_tracking_service.dart';
import 'geo_runtime_test.dart' show FakeGeo;

class MockShiftProvider extends Mock implements ShiftProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  setUp(() {
    original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = FakeGeo()..enabled = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({geoShiftKey: 10});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null);
  });
  testWidgets(
      'GPS warning is visible without blocking work and clears after shift ends',
      (tester) async {
    int actions = 0;
    final provider = MockShiftProvider();
    when(() => provider.activeShift).thenReturn(null);
    await tester.pumpWidget(ChangeNotifierProvider<ShiftProvider>.value(
        value: provider,
        child: MaterialApp(
          builder: (context, child) => GeoTrackingNotice(child: child!),
          home: Scaffold(
              body: Center(
                  child: ElevatedButton(
                      onPressed: () => actions++,
                      child: const Text('Рабочее действие')))),
        )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Включите геолокацию'), findsOneWidget);
    await tester.tap(find.text('Рабочее действие'));
    expect(actions, 1);
    expect(tester.takeException(), isNull);
    await (await SharedPreferences.getInstance()).remove(geoShiftKey);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('Включите геолокацию'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
