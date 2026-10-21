import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/sample_data.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Bundled database contains three usable accounts and employee profiles',
    () async {
      final fixture = await DatabaseFixture.open(
        keepSampleUsers: true,
        bundledData: true,
      );
      try {
        for (final input in [
          ('admin', 'Admin@12345', 'Admin'),
          ('manager', 'Manager@12345', 'Quản lý'),
          ('employee', 'Employee@12345', 'Nhân viên'),
        ]) {
          final session = await fixture.auth.signIn(input.$1, input.$2);
          expect(session.role, input.$3);
          expect(session.profile['user_id'], session.userId);
        }
      } finally {
        await fixture.dispose();
      }
    },
  );
  test('Seed installs three real users with correct roles and preserves later changes', () async {
    final fixture = await DatabaseFixture.open();
    try {
      await fixture.db.execute('PRAGMA user_version = 1');
      await installSampleData(fixture.db);
      for (final account in [
        ('admin', 'Admin@12345', 'Admin'),
        ('manager', 'Manager@12345', 'Quản lý'),
        ('employee', 'Employee@12345', 'Nhân viên'),
      ]) {
        final session = await fixture.auth.signIn(account.$1, account.$2);
        expect(session.role, account.$3);
        expect(session.profile['employee_code'], isNotNull);
      }
      expect(await fixture.db.query('users'), hasLength(3));
      expect(await fixture.db.query('employees'), hasLength(3));
      await fixture.db.update(
        'users',
        {'is_active': 0},
        where: 'username = ?',
        whereArgs: ['employee'],
      );
      await installSampleData(fixture.db);
      expect(await fixture.db.query('users'), hasLength(3));
      expect(
        (await fixture.db.query(
          'users',
          where: 'username = ?',
          whereArgs: ['employee'],
        )).single['is_active'],
        0,
      );
      expect(await fixture.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await fixture.dispose();
    }
  });
}
