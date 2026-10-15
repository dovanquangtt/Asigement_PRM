import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quanlinhansunhahang/services/sample_data.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final filename = File('database/prm_database.db').absolute.path;
  if (!File(filename).existsSync()) throw StateError('Không tìm thấy database');
  final db = await databaseFactoryFfi.openDatabase(filename);
  try {
    await db.execute('PRAGMA foreign_keys = ON');
    await installSampleData(db);
    stdout.writeln(
      await db.rawQuery(
        'SELECT u.username, r.code AS role, e.full_name FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id LEFT JOIN employees e ON e.user_id=u.id',
      ),
    );
    stdout.writeln(await db.rawQuery('PRAGMA integrity_check'));
    stdout.writeln(await db.rawQuery('PRAGMA foreign_key_check'));
  } finally {
    await db.close();
  }
}
