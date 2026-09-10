import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../lib/src/core/services/geo/geo_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'real SQLite retains history, prioritizes newest fix, acknowledges exact IDs',
    () async {
      final dir = await Directory.systemTemp.createTemp('eom-geo-sqlite-');
      await databaseFactory.setDatabasesPath(dir.path);
      final first = SqliteGeoQueue();
      final now = DateTime.now().toUtc();
      for (int i = 0; i < 150; i++) {
        await first.add('1', {
          'point_id': '1:$i',
          'timestamp': now.add(Duration(seconds: i)).toIso8601String(),
        });
      }
      final second = SqliteGeoQueue();
      final packet = await second.read('1');
      expect(packet.length, 100);
      expect(packet.last['point_id'], '1:149');
      expect(packet.first['point_id'], '1:0');
      final ack = packet.map((p) => p['point_id'] as String).toSet();
      await Future.wait([
        first.acknowledge('1', ack),
        second.add('1', {
          'point_id': '1:new',
          'timestamp': now.add(const Duration(hours: 1)).toIso8601String(),
        }),
        second.add('2', {
          'point_id': '2:other',
          'timestamp': now.toIso8601String(),
        }),
      ]);
      final remaining = await second.read('1');
      expect(remaining.length, 51);
      expect(remaining.any((p) => p['point_id'] == '1:new'), true);
      expect((await first.read('2')).single['point_id'], '2:other');
      await first.add('1', {
        'point_id': '1:new',
        'timestamp': now.toIso8601String(),
      });
      expect((await first.read('1')).length, 51);
      await (await first.database).close();
      // Reopening demonstrates persistence, independently of Dart object lifetime.
      final reopened = SqliteGeoQueue();
      expect((await reopened.read('1')).length, 51);
      await (await reopened.database).close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'upgrade preserves queued points; rejected payloads survive reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('eom-geo-upgrade-');
      await databaseFactory.setDatabasesPath(dir.path);
      final legacy = await openDatabase(
        '${dir.path}/eom_geo_queue.db',
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE points (point_id TEXT PRIMARY KEY,user_id TEXT NOT NULL,payload TEXT NOT NULL,recorded_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX points_user_time ON points(user_id,recorded_at)',
          );
          await db.insert('points', {
            'point_id': 'old',
            'user_id': '1',
            'payload': '{"point_id":"old"}',
            'recorded_at': '2026-09-10T01:00:00Z',
          });
        },
      );
      await legacy.close();
      final upgraded = SqliteGeoQueue();
      expect((await upgraded.read('1')).single['point_id'], 'old');
      await upgraded.reject('1', {'old'});
      expect(await upgraded.read('1'), isEmpty);
      await (await upgraded.database).close();
      final reopened = SqliteGeoQueue();
      final archived = await (await reopened.database).query(
        'points',
        where: 'point_id = ?',
        whereArgs: ['old'],
      );
      expect(archived.single['payload'], '{"point_id":"old"}');
      expect(archived.single['rejected_at'], isNotNull);
      await (await reopened.database).close();
      await dir.delete(recursive: true);
    },
  );
}
