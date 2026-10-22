import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quanlinhansunhahang/services/feature_migrations.dart';
import 'package:quanlinhansunhahang/services/sample_data.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Upgrade original 32-table schema preserves accounts and is idempotent',
    () async {
      sqfliteFfiInit();
      final folder = await Directory.systemTemp.createTemp('prm_migrate_');
      final db = await databaseFactoryFfi.openDatabase('${folder.path}/old.db');
      try {
        for (final statement in await fixtureSqlStatements(
          'database/prm_schema.sql',
        )) {
          await db.execute(statement);
        }
        for (final statement in await fixtureSqlStatements(
          'database/prm_seed.sql',
        )) {
          await db.execute(statement);
        }
        await installSampleData(db);
        final hash = (await db.query(
          'users',
          where: 'username=?',
          whereArgs: ['admin'],
        )).single['password_hash'];
        await migrateFeatures(db);
        await migrateFeatures(db);
        final team = await db.rawQuery(
          'SELECT u.username,e.full_name,r.code FROM users u JOIN employees e ON e.user_id=u.id JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id ORDER BY u.username',
        );
        expect(team, [
          {
            'username': 'admin',
            'full_name': 'Nguyễn Xuân Bắc',
            'code': 'admin',
          },
          {
            'username': 'employee',
            'full_name': 'Đỗ Văn Quang',
            'code': 'employee',
          },
          {
            'username': 'manager',
            'full_name': 'Nguyễn Văn Trường',
            'code': 'manager',
          },
        ]);
        expect(
          await db.query(
            'audit_logs',
            where: 'action=?',
            whereArgs: ['configure_team_identity_20261022'],
          ),
          hasLength(3),
        );
        await db.update(
          'employees',
          {'full_name': 'Tên được cập nhật sau đó'},
          where: 'employee_code=?',
          whereArgs: ['DEMO_EMPLOYEE'],
        );
        await migrateFeatures(db);
        expect(
          (await db.query(
            'employees',
            where: 'employee_code=?',
            whereArgs: ['DEMO_EMPLOYEE'],
          )).single['full_name'],
          'Tên được cập nhật sau đó',
        );
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          6,
        );
        expect(
          (await db.query(
            'users',
            where: 'username=?',
            whereArgs: ['admin'],
          )).single['password_hash'],
          hash,
        );
        expect(await db.query('users'), hasLength(3));
        expect(
          (await db.rawQuery(
            "SELECT COUNT(*) n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )).single['n'],
          34,
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
      } finally {
        await db.close();
        await folder.delete(recursive: true);
      }
    },
  );
}
