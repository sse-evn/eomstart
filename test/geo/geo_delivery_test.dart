import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:micro_mobility_app/src/core/services/geo/geo_delivery.dart';

class MemoryGeoQueue implements GeoQueue {
  final Map<String, Map<String, dynamic>> points = {};
  final Set<String> rejected = {};
  @override
  Future<void> add(String user, Map<String, dynamic> point) async {
    points.putIfAbsent('$user/${point['point_id']}', () => Map.of(point));
  }

  @override
  Future<List<Map<String, dynamic>>> read(String user,
          {int limit = 100}) async =>
      points.entries
          .where((e) => e.key.startsWith('$user/') && !rejected.contains(e.key))
          .take(limit)
          .map((e) => e.value)
          .toList();
  @override
  Future<void> acknowledge(String user, Set<String> ids) async {
    for (final id in ids) {
      points.remove('$user/$id');
    }
  }

  @override
  Future<void> reject(String user, Set<String> ids) async {
    rejected.addAll(ids.map((id) => '$user/$id'));
  }
}

String testToken(String user) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode({
          'user_id': user
        })))}.signature';

void main() {
  late MemoryGeoQueue queue;
  setUp(() async {
    queue = MemoryGeoQueue();
    await queue.add('1', {'point_id': 'a'});
    await queue.add('1', {'point_id': 'b'});
  });
  GeoDelivery delivery(Future<http.Response> Function(http.Request) respond,
          {Future<String?> Function()? refresh}) =>
      GeoDelivery(
          queue: queue,
          client: MockClient(respond),
          url: Uri.parse('https://example.invalid/api/geo'),
          readToken: () async => testToken('1'),
          refreshToken: refresh ?? () async => null);

  test('network failure retains every queued point', () async {
    final result =
        await delivery((_) async => throw const SocketException('offline'))
            .send();
    expect(result.delivered, false);
    expect((await queue.read('1')).length, 2);
  });
  test('partial acknowledgement removes only accepted/rejected IDs', () async {
    await delivery((_) async => http.Response(
        jsonEncode({
          'accepted_ids': ['a'],
          'rejected_ids': []
        }),
        503)).send();
    expect((await queue.read('1')).map((p) => p['point_id']), ['b']);
  });
  test('points captured during upload are not deleted with old packet',
      () async {
    await delivery((_) async {
      await queue.add('1', {'point_id': 'new'});
      return http.Response(
          jsonEncode({
            'accepted_ids': ['a', 'b', 'new'],
            'rejected_ids': []
          }),
          200);
    }).send();
    expect((await queue.read('1')).map((p) => p['point_id']), ['new']);
  });
  test('old backend partial success retains packet for retry', () async {
    final result =
        await delivery((_) async => http.Response('{"points_saved":1}', 200))
            .send();
    expect(result.delivered, false);
    expect(result.acceptedCount, 0);
    expect((await queue.read('1')).length, 2);
  });
  test('HTTP 200 without a persistence acknowledgement never clears data',
      () async {
    final result =
        await delivery((_) async => http.Response('{"status":"ok"}', 200))
            .send();
    expect(result.delivered, false);
    expect((await queue.read('1')).length, 2);
  });
  test('rejected payloads are retained outside the delivery queue', () async {
    final result = await delivery((_) async =>
            http.Response('{"accepted_ids":["a"],"rejected_ids":["b"]}', 200))
        .send();
    expect(result.delivered, false);
    expect(result.acceptedCount, 1);
    expect(result.rejectedCount, 1);
    expect(await queue.read('1'), isEmpty);
    expect(queue.points['1/b']?['point_id'], 'b');
  });
  test('empty legacy heartbeat cannot be confused with a saved GPS point',
      () async {
    await queue.acknowledge('1', {'a', 'b'});
    final result = await delivery((_) async => http.Response(
            '{"status":"ok","message":"No points received"}', 200))
        .send(tracking: {'shift_id': 10, 'state': 'no_fix'});
    expect(result.delivered, true);
    expect(result.acceptedCount, 0);
    expect(result.latestAcceptedAt, isNull);
  });
  test('old backend complete success can acknowledge the packet', () async {
    await delivery((_) async => http.Response('{"points_saved":2}', 200))
        .send();
    expect(await queue.read('1'), isEmpty);
  });
  test('queue is partitioned by authenticated user', () async {
    await queue.add('2', {'point_id': 'other'});
    await delivery((request) async {
      expect((jsonDecode(request.body)['data'] as List).length, 2);
      return http.Response('{"accepted_ids":["a","b"],"rejected_ids":[]}', 200);
    }).send();
    expect((await queue.read('2')).single['point_id'], 'other');
  });
  test('401 refresh retries request but failed refresh preserves queue',
      () async {
    int requests = 0;
    await delivery((_) async {
      requests++;
      return requests == 1
          ? http.Response('', 401)
          : http.Response('{"accepted_ids":["a","b"],"rejected_ids":[]}', 200);
    }, refresh: () async => testToken('1')).send();
    expect(requests, 2);
    expect(await queue.read('1'), isEmpty);
    await queue.add('1', {'point_id': 'c'});
    await delivery((_) async => http.Response('', 401),
        refresh: () async => throw const SocketException('offline')).send();
    expect((await queue.read('1')).single['point_id'], 'c');
  });
  test('changed account during token refresh never sends another user packet',
      () async {
    int count = 0;
    await delivery((_) async {
      count++;
      return http.Response('', 401);
    }, refresh: () async => testToken('2')).send();
    expect(count, 1);
    expect((await queue.read('1')).length, 2);
  });
  test('overlapping flushes share one in-flight request', () async {
    final response = Completer<http.Response>();
    int calls = 0;
    final d = delivery((_) async {
      calls++;
      return response.future;
    });
    final first = d.send();
    await Future<void>.delayed(Duration.zero);
    expect((await d.send()).delivered, false);
    response.complete(
        http.Response('{"accepted_ids":["a","b"],"rejected_ids":[]}', 200));
    await first;
    expect(calls, 1);
  });
  test('confirmed closed shift is surfaced even for empty packets', () async {
    final result = await delivery((_) async => http.Response(
            '{"accepted_ids":[],"rejected_ids":[],"shift_active":false}', 200))
        .send();
    expect(result.shiftActive, false);
  });
  test('stale and future measurements cannot be presented as fresh', () {
    final now = DateTime.utc(2026, 9, 6);
    expect(
        isFreshGeoPoint(now.subtract(const Duration(minutes: 2)), now), false);
    expect(isFreshGeoPoint(now.add(const Duration(minutes: 2)), now), false);
    expect(
        isFreshGeoPoint(now.subtract(const Duration(seconds: 15)), now), true);
  });
}
