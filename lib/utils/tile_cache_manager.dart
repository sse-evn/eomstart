// // lib/utils/tile_cache_manager.dart
// import 'dart:io';
// import 'dart:typed_data';
// import 'package:http/http.dart' as http;
// import 'package:path/path.dart';
// import 'package:sqflite/sqflite.dart';
// import 'package:path_provider/path_provider.dart';

// class TileCacheManager {
//   static final TileCacheManager _instance = TileCacheManager._internal();
//   factory TileCacheManager() => _instance;
//   TileCacheManager._internal();

//   static Database? _db;
//   static const String _tableName = 'tiles';
//   static const int _maxTileCount = 5000;
//   static const Duration _cacheTtl = Duration(days: 30);

//   Future<Database> get db async {
//     _db ??= await _initDb();
//     return _db!;
//   }

//   Future<Database> _initDb() async {
//     final dir = await getApplicationDocumentsDirectory();
//     final dbPath = join(dir.path, 'map_tiles.db');

//     final db = await openDatabase(
//       dbPath,
//       version: 1,
//       onCreate: (db, version) {
//         return db.execute('''
//           CREATE TABLE $_tableName (
//             url TEXT PRIMARY KEY,
//             data BLOB NOT NULL,
//             timestamp INTEGER NOT NULL
//           )
//         ''');
//       },
//     );

//     // Очистка устаревших записей при запуске
//     await _cleanup(db);
//     return db;
//   }

//   Future<void> _cleanup(Database db) async {
//     final now = DateTime.now().millisecondsSinceEpoch;
//     final cutoff = now - _cacheTtl.inMilliseconds;

//     // Удаляем устаревшие
//     await db.delete(_tableName, where: 'timestamp < ?', whereArgs: [cutoff]);

//     // Проверяем количество записей
//     final count = Sqflite.firstIntValue(
//           await db.rawQuery('SELECT COUNT(*) FROM $_tableName'),
//         ) ??
//         0;

//     if (count > _maxTileCount) {
//       // Удаляем самые старые записи, чтобы уложиться в лимит
//       final excess = count - _maxTileCount + 100; // немного запаса
//       await db.rawQuery('''
//         DELETE FROM $_tableName
//         WHERE url IN (
//           SELECT url FROM $_tableName
//           ORDER BY timestamp ASC
//           LIMIT ?
//         )
//       ''', [excess]);
//     }
//   }

//   Future<Uint8List?> getTile(String url) async {
//     final db = await this.db;
//     final result = await db.query(
//       _tableName,
//       where: 'url = ?',
//       whereArgs: [url],
//     );

//     if (result.isEmpty) return null;

//     final row = result.first;
//     final timestamp = row['timestamp'] as int;
//     if (DateTime.now().millisecondsSinceEpoch - timestamp >
//         _cacheTtl.inMilliseconds) {
//       // Устарело — удаляем и возвращаем null
//       await db.delete(_tableName, where: 'url = ?', whereArgs: [url]);
//       return null;
//     }

//     return row['data'] as Uint8List;
//   }

//   Future<void> putTile(String url, Uint8List data) async {
//     final db = await this.db;
//     final timestamp = DateTime.now().millisecondsSinceEpoch;

//     // Вставляем или заменяем
//     await db.insert(
//       _tableName,
//       {'url': url, 'data': data, 'timestamp': timestamp},
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );
//   }

//   Future<Uint8List> fetchTile(String url) async {
//     final cached = await getTile(url);
//     if (cached != null) return cached;

//     final response = await http.get(Uri.parse(url));
//     if (response.statusCode == 200) {
//       final bytes = response.bodyBytes;
//       await putTile(url, bytes);
//       return bytes;
//     } else {
//       throw Exception('Failed to load tile: ${response.statusCode}');
//     }
//   }
// }
