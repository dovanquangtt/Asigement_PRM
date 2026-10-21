import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/local_database.dart';
import 'package:quanlinhansunhahang/services/feature_sample_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Opening old empty demo database adds assignments once', () async {
    final f = await DatabaseFixture.open(keepSampleUsers: true);
    final path = f.db.path;
    final originalUsers = await f.db.query('users');
    await f.db.close();
    final db = await LocalDatabase.openBundledDatabase(
      databaseFactoryFfi,
      path,
    );
    try {
      expect(await db.query('shifts'), hasLength(13));
      expect(await db.query('shift_assignments'), hasLength(18));
      expect(await db.query('users'), originalUsers);
      expect(
        await db.rawQuery('''
        SELECT a.id FROM shift_assignments a
        JOIN employees e ON e.id=a.employee_id
        JOIN users u ON u.id=e.user_id WHERE u.username='employee'
      '''),
        isNotEmpty,
      );
      expect(
        await installFeatureSamples(db, onlyForDemoAccounts: true),
        isFalse,
      );
      expect(await db.query('shifts'), hasLength(13));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await db.close();
      await f.directory.delete(recursive: true);
    }
  });

  test(
    'Automatic backfill adds samples and preserves manual template',
    () async {
      final f = await DatabaseFixture.open(keepSampleUsers: true);
      try {
        await f.db.insert('shift_templates', {
          'code': 'REAL',
          'name': 'Ca đã nhập',
          'start_time': '08:00',
          'end_time': '16:00',
        });
        expect(
          await installFeatureSamples(f.db, onlyForDemoAccounts: true),
          isTrue,
        );
        expect(await f.db.query('shift_templates'), hasLength(5));
        expect(
          await f.db.query(
            'shift_templates',
            where: 'code=?',
            whereArgs: ['REAL'],
          ),
          hasLength(1),
        );
        expect(await f.db.query('shifts'), hasLength(13));
      } finally {
        await f.dispose();
      }
    },
  );

  test('Changed sample identity is skipped without blocking startup', () async {
    final f = await DatabaseFixture.open(keepSampleUsers: true);
    try {
      await f.db.update(
        'users',
        {'username': 'real_employee'},
        where: 'username=?',
        whereArgs: ['employee'],
      );
      expect(
        await installFeatureSamples(f.db, onlyForDemoAccounts: true),
        isFalse,
      );
      expect(await f.db.query('shifts'), isEmpty);
    } finally {
      await f.dispose();
    }
  });
}
