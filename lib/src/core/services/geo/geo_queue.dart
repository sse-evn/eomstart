import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'geo_delivery.dart';

/// Transactional queue shared by the UI and background Flutter engines.
/// Acknowledgement deletes exact IDs, never a whole buffer that may have grown.
class SqliteGeoQueue implements GeoQueue {
  Future<Database>? _database;
  Future<Database> get database async {
    final opening = _database ??= _open();
    try {
      return await opening;
    } catch (_) {
      if (identical(_database, opening)) _database = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final path = '${await getDatabasesPath()}/eom_geo_queue.db';
    return openDatabase(path, version: 2, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE points (point_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, payload TEXT NOT NULL, recorded_at TEXT NOT NULL, rejected_at TEXT)');
      await db.execute(
          'CREATE INDEX points_user_time ON points(user_id, recorded_at)');
    }, onUpgrade: (db, oldVersion, _) async {
      if (oldVersion < 2)
        await db.execute('ALTER TABLE points ADD COLUMN rejected_at TEXT');
    });
  }

  @override
  Future<void> add(String userId, Map<String, dynamic> point) async {
    await (await database).insert(
        'points',
        {
          'point_id': point['point_id'],
          'user_id': userId,
          'payload': jsonEncode(point),
          'recorded_at': point['timestamp'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<List<Map<String, dynamic>>> read(String userId,
      {int limit = 100}) async {
    if (limit < 2)
      throw ArgumentError.value(limit, 'limit', 'must be at least 2');
    final rows = await (await database).transaction((tx) async {
      final oldest = await tx.query('points',
          where: 'user_id = ? AND rejected_at IS NULL',
          whereArgs: [userId],
          orderBy: 'recorded_at, point_id',
          limit: limit);
      if (oldest.length < limit) return oldest;
      final newest = await tx.query('points',
          where: 'user_id = ? AND rejected_at IS NULL',
          whereArgs: [userId],
          orderBy: 'recorded_at DESC, point_id DESC',
          limit: 1);
      // Drain history and include the current location in the SAME packet, so a
      // long offline queue cannot hide an employee who has regained connection.
      if (newest.isNotEmpty &&
          newest.first['point_id'] != oldest.last['point_id']) {
        return [...oldest.take(limit - 1), newest.first];
      }
      return oldest;
    });
    return rows
        .map((r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>)
        .toList();
  }

  @override
  Future<void> acknowledge(String userId, Set<String> ids) async {
    if (ids.isEmpty) return;
    await (await database).transaction((tx) async {
      for (final id in ids) {
        await tx.delete('points',
            where: 'user_id = ? AND point_id = ?', whereArgs: [userId, id]);
      }
    });
  }

  @override
  Future<void> reject(String userId, Set<String> ids) async {
    // Keep the original payload for diagnosis without letting an invalid point
    // block the rest of an employee's offline history indefinitely.
    final rejectedAt = DateTime.now().toUtc().toIso8601String();
    await (await database).transaction((tx) async {
      for (final id in ids) {
        await tx.update('points', {'rejected_at': rejectedAt},
            where: 'user_id = ? AND point_id = ?', whereArgs: [userId, id]);
      }
    });
  }
}
