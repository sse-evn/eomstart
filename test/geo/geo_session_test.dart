import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, String> storage;
  setUp(() {
    storage = {'jwt_token': 'access', 'refresh_token': 'refresh'};
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'read':
          return storage[args['key']];
        case 'write':
          storage[args['key']] = args['value'];
          return null;
        case 'delete':
          storage.remove(args['key']);
          return null;
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null));
  test('server error does not masquerade as a closed shift', () async {
    final api = ApiService(
        sessionClient: MockClient(
            (_) async => http.Response('{"error":"unavailable"}', 503)));
    await expectLater(api.getActiveShift('access'), throwsException);
    expect(storage['jwt_token'], 'access');
  });
  test('failed token refresh retains existing session on server outage',
      () async {
    final api = ApiService(
        sessionClient: MockClient((r) async =>
            http.Response('', r.url.path.endsWith('/refresh') ? 503 : 401)));
    await expectLater(api.getActiveShift('access'), throwsException);
    expect(storage, {'jwt_token': 'access', 'refresh_token': 'refresh'});
  });
  test('explicit rejected refresh clears credentials', () async {
    final api = ApiService(
        sessionClient: MockClient((_) async => http.Response('', 401)));
    await expectLater(api.getActiveShift('access'), throwsException);
    expect(storage, isEmpty);
  });
  test('successful refresh retries the original active shift request',
      () async {
    int calls = 0;
    final api = ApiService(sessionClient: MockClient((r) async {
      calls++;
      if (r.url.path.endsWith('/refresh'))
        return http.Response(
            jsonEncode({'token': 'new', 'refresh_token': 'new-refresh'}), 200);
      return r.headers['Authorization'] == 'Bearer new'
          ? http.Response('null', 200)
          : http.Response('', 401);
    }));
    expect(await api.getActiveShift('access'), isNull);
    expect(calls, 3);
    expect(storage['jwt_token'], 'new');
  });
  test('malformed response does not end the shift', () async {
    final api = ApiService(
        sessionClient: MockClient((_) async => http.Response('{broken', 200)));
    await expectLater(api.getActiveShift('access'), throwsFormatException);
  });
  test('empty successful response is unknown, not a closed shift', () async {
    final api = ApiService(
        sessionClient: MockClient((_) async => http.Response('', 200)));
    await expectLater(api.getActiveShift('access'), throwsFormatException);
  });
  test('incomplete successful object is unknown, not a different active shift',
      () async {
    for (final body in [
      '{}',
      '{"error":"unavailable"}',
      '{"id":10,"user_id":1}'
    ]) {
      final api = ApiService(
          sessionClient: MockClient((_) async => http.Response(body, 200)));
      await expectLater(api.getActiveShift('access'), throwsFormatException);
      api.close();
    }
  });
  test('background rejection preserves credentials for foreground recovery',
      () async {
    final api = ApiService(
        clearRejectedSession: false,
        sessionClient: MockClient((_) async => http.Response('', 401)));
    await expectLater(api.getActiveShift('access'), throwsException);
    expect(storage, {'jwt_token': 'access', 'refresh_token': 'refresh'});
  });
  test('late rejected refresh cannot erase a newer login', () async {
    final api = ApiService(sessionClient: MockClient((_) async {
      storage['jwt_token'] = 'other-access';
      storage['refresh_token'] = 'other-refresh';
      return http.Response('', 401);
    }));
    expect(await api.refreshToken(), 'other-access');
    expect(storage['refresh_token'], 'other-refresh');
  });
  test('late successful refresh cannot overwrite a newer login', () async {
    final api = ApiService(sessionClient: MockClient((_) async {
      storage['jwt_token'] = 'other-access';
      storage['refresh_token'] = 'other-refresh';
      return http.Response(
          '{"token":"late","refresh_token":"late-refresh"}', 200);
    }));
    expect(await api.refreshToken(), 'other-access');
    expect(storage['refresh_token'], 'other-refresh');
  });
}
