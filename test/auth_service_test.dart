import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture fixture;
  setUp(() async => fixture = await DatabaseFixture.open());
  tearDown(() => fixture.dispose());

  test('Reject unknown username, SQL injection, wrong password, locked user and missing role', () async {
    await fixture.addUser();
    await fixture.addUser(username: 'locked', active: 0);
    await fixture.addUser(username: 'unassigned', role: null);
    for (final input in [
      ('unknown', 'TestPass123!'),
      ("' OR 1=1 --", 'TestPass123!'),
      ('linh', 'wrong'),
      ('locked', 'TestPass123!'),
      ('unassigned', 'TestPass123!'),
    ]) {
      await expectLater(
        fixture.auth.signIn(input.$1, input.$2),
        throwsA(isA<AuthException>()),
      );
    }
  });
  test('Identity, role and permissions are read from SQLite, including role changes', () async {
    final id = await fixture.addUser();
    final session = await fixture.auth.signIn(' LINH ', 'TestPass123!');
    expect(session.userId, id);
    expect(session.username, 'linh');
    expect(session.role, 'Nhân viên');
    expect(session.permissions, contains('profile.self'));
    expect(session.permissions, isNot(contains('users.manage')));
    final manager = await fixture.db.query(
      'roles',
      where: 'code = ?',
      whereArgs: ['manager'],
    );
    await fixture.db.update(
      'user_roles',
      {'role_id': manager.single['id']},
      where: 'user_id = ?',
      whereArgs: [id],
    );
    expect((await fixture.auth.signIn('linh', 'TestPass123!')).role, 'Quản lý');
  });
  test(
    'First admin has a hashed password and cannot be created again',
    () async {
      expect(await fixture.auth.hasUsers(), isFalse);
      await fixture.auth.createFirstAdmin('owner', 'OwnerPass123!');
      final row = (await fixture.db.query('users')).single;
      expect(row['password_hash'], isNot('OwnerPass123!'));
      expect((row['password_hash'] as String).startsWith(r'$2'), isTrue);
      final session = await fixture.auth.signIn('owner', 'OwnerPass123!');
      expect(session.role, 'Admin');
      expect(session.permissions, contains('users.manage'));
      await expectLater(
        fixture.auth.createFirstAdmin('other', 'OwnerPass123!'),
        throwsA(isA<AuthException>()),
      );
      expect(await fixture.db.query('users'), hasLength(1));
    },
  );
  test('Malformed or plaintext password_hash is rejected', () async {
    final id = await fixture.addUser();
    for (final hash in ['TestPass123!', r'$2broken']) {
      await fixture.db.update(
        'users',
        {'password_hash': hash},
        where: 'id = ?',
        whereArgs: [id],
      );
      await expectLater(
        fixture.auth.signIn('linh', 'TestPass123!'),
        throwsA(isA<AuthException>()),
      );
    }
  });
  test(
    'Bootstrap validates input and rolls back when role is missing',
    () async {
      await expectLater(
        fixture.auth.createFirstAdmin('owner', 'short'),
        throwsA(isA<AuthException>()),
      );
      expect(await fixture.db.query('users'), isEmpty);
      await fixture.db.delete('role_permissions', where: 'role_id = 1');
      await fixture.db.delete('roles', where: 'id = 1');
      await expectLater(
        fixture.auth.createFirstAdmin('owner', 'OwnerPass123!'),
        throwsA(isA<AuthException>()),
      );
      expect(await fixture.db.query('users'), isEmpty);
    },
  );
  test('Database failure never produces a session', () async {
    final auth = AuthService(
      openDatabase: () => Future.error(StateError('database unavailable')),
    );
    await expectLater(auth.signIn('linh', 'TestPass123!'), throwsStateError);
  });
}
