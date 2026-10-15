import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quanlinhansunhahang/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Bundled database is valid and reopening preserves local changes',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'prm_sqlite_test_',
      );
      final filename = p.join(directory.path, 'prm_database.db');
      final db = await LocalDatabase.openBundledDatabase(
        databaseFactoryFfi,
        filename,
      );
      try {
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
          1,
        );
        expect(
          (await db.rawQuery(
            "SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )).single['n'],
          32,
        );
        expect(
          (await db.rawQuery(
            "SELECT count(*) AS n FROM sqlite_master WHERE type='view'",
          )).single['n'],
          5,
        );
        expect(await db.query('roles'), hasLength(3));
        expect(await db.query('permissions'), hasLength(20));
        await expectLater(
          db.insert('user_roles', {'user_id': -1, 'role_id': 1}),
          throwsA(isA<DatabaseException>()),
        );
        await db.insert('departments', {
          'code': 'LOCAL_TEST',
          'name': 'Lưu cục bộ',
        });
      } finally {
        await db.close();
      }
      final reopened = await LocalDatabase.openBundledDatabase(
        databaseFactoryFfi,
        filename,
      );
      try {
        expect(
          await reopened.query(
            'departments',
            where: 'code = ?',
            whereArgs: ['LOCAL_TEST'],
          ),
          hasLength(1),
        );
      } finally {
        await reopened.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
