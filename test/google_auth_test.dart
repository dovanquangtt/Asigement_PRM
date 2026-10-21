import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/google_auth.dart';

import 'database_fixture.dart';

class FakeGoogleAuth implements GoogleAuth {
  String id = 'google-linh';
  String email = 'LINH@gmail.com';
  Object? failure;
  int signOuts = 0;
  bool failSignOut = false;

  @override
  Future<({String id, String email})> authenticate() async {
    if (failure != null) throw failure!;
    return (id: id, email: email);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    if (failSignOut) throw Exception('offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture fixture;
  late FakeGoogleAuth google;
  late AuthService auth;
  late int userId;

  setUp(() async {
    fixture = await DatabaseFixture.open();
    userId = await fixture.addUser();
    await fixture.db.update(
      'users',
      {'email': 'linh@gmail.com'},
      where: 'id = ?',
      whereArgs: [userId],
    );
    google = FakeGoogleAuth();
    auth = AuthService(
      openDatabase: () async => fixture.db,
      googleAuth: google,
    );
  });
  tearDown(() => fixture.dispose());

  test(
    'Google identity matches provisioned email and preserves assigned role',
    () async {
      final session = await auth.signInGoogle();
      expect(session.userId, userId);
      expect(session.role, 'Nhân viên');
      expect(
        (await fixture.db.query('users')).single['google_subject'],
        google.id,
      );
      expect((await auth.signInGoogle()).userId, userId);
      await auth.signOut();
      expect(google.signOuts, 1);
    },
  );

  test(
    'Unknown and disabled Gmail cannot sign in or create accounts',
    () async {
      google.email = 'unknown@gmail.com';
      await expectLater(auth.signInGoogle(), throwsA(isA<AuthException>()));
      google.email = 'linh@gmail.com';
      await fixture.db.update('users', {'is_active': 0});
      await expectLater(auth.signInGoogle(), throwsA(isA<AuthException>()));
      expect(await fixture.db.query('users'), hasLength(1));
      expect(google.signOuts, 2);
    },
  );

  test('Mismatched Google subject is rejected and cleaned up', () async {
    await fixture.db.update('users', {'google_subject': 'other-subject'});
    await expectLater(auth.signInGoogle(), throwsA(isA<AuthException>()));
    expect(google.signOuts, 1);
    expect(
      (await fixture.db.query('users')).single['google_subject'],
      'other-subject',
    );
  });

  test('Missing role rolls back identity link', () async {
    await fixture.db.delete('user_roles');
    await expectLater(auth.signInGoogle(), throwsA(isA<AuthException>()));
    expect((await fixture.db.query('users')).single['google_subject'], isNull);
    expect(google.signOuts, 1);
  });

  test('Cancellation has a user-facing message and permits retry', () async {
    google.failure = const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );
    await expectLater(
      auth.signInGoogle(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('hủy'),
        ),
      ),
    );
    google.failure = null;
    expect((await auth.signInGoogle()).userId, userId);
  });

  test('Google cleanup failure does not block local logout', () async {
    google.failSignOut = true;
    await auth.signOut();
    expect(google.signOuts, 1);
  });
}
