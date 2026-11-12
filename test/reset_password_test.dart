import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Admin đặt lại mật khẩu: mật khẩu cũ hết hiệu lực, mật khẩu mới đăng nhập được.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager;
  late int quangUser;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    admin = await repo('admin', 'Admin@12345');
    manager = await repo('manager', 'Manager@12345');
    quangUser =
        (await f.db.query('users', where: "username='employee'")).single['id']
            as int;
  });
  tearDown(() => f.dispose());

  Future<void> rejects(Future<void> call, String part) => expectLater(
    call,
    throwsA(isA<AuthException>().having((e) => e.message, 'm', contains(part))),
  );

  test('the new password works and the old one stops working', () async {
    await admin.resetPassword(quangUser, 'MatKhauMoi@1');
    await rejects(f.auth.signIn('employee', 'Employee@12345'), 'không đúng');
    expect(
      (await f.auth.signIn('employee', 'MatKhauMoi@1')).username,
      'employee',
    );
    // Nhật ký ghi lại việc đặt lại, không lưu mật khẩu.
    final log = (await f.db.query(
      'audit_logs',
      where: "action='user.reset_password'",
    )).single;
    expect(log['entity_id'], quangUser);
    expect('${log['after_json']}', isNot(contains('MatKhauMoi')));
  });

  test('only Admin can reset, the password must be valid and the account must exist', () async {
    await rejects(manager.resetPassword(quangUser, 'MatKhauMoi@1'), 'quyền');
    await rejects(admin.resetPassword(quangUser, 'short'), 'ít nhất 8');
    await rejects(admin.resetPassword(99999, 'MatKhauMoi@1'), 'Không tìm thấy');
    // Không đổi gì khi lỗi.
    expect(
      (await f.auth.signIn('employee', 'Employee@12345')).username,
      'employee',
    );
  });

  test('an Admin can reset their own password', () async {
    final id =
        (await f.db.query('users', where: "username='admin'")).single['id']
            as int;
    await admin.resetPassword(id, 'AdminMoi@123');
    expect((await f.auth.signIn('admin', 'AdminMoi@123')).username, 'admin');
  });

  test('a locked account cannot sign in until unlocked, even after a password reset', () async {
    // Xóa nhân viên khóa tài khoản và chuyển hồ sơ sang đã nghỉ việc.
    final profile =
        (await f.db.query(
              'employees',
              where: 'user_id=?',
              whereArgs: [quangUser],
            )).single['id']
            as int;
    await admin.deleteEmployee(profile);
    expect(
      (await f.db.query(
        'users',
        where: 'id=?',
        whereArgs: [quangUser],
      )).single['is_active'],
      0,
    );
    await admin.resetPassword(quangUser, 'MatKhauMoi@1');
    await rejects(f.auth.signIn('employee', 'MatKhauMoi@1'), 'không đúng');
    await admin.setUserActive(quangUser, true);
    final session = await f.auth.signIn('employee', 'MatKhauMoi@1');
    // Hồ sơ được khôi phục nên dùng được chức năng ngay.
    final back = WorkforceRepository(session, openDatabase: () async => f.db);
    expect(await back.leaveBalances(), isNotEmpty);
    expect(
      (await f.db.query(
        'employees',
        where: 'id=?',
        whereArgs: [profile],
      )).single['status'],
      'active',
    );
    expect(
      await f.db.query('audit_logs', where: "action='user.unlock'"),
      hasLength(1),
    );
  });

  test('locking blocks sign in; only Admin can lock or unlock; Admin cannot lock themselves', () async {
    await admin.setUserActive(quangUser, false);
    await rejects(f.auth.signIn('employee', 'Employee@12345'), 'không đúng');
    await admin.setUserActive(quangUser, true);
    expect(
      (await f.auth.signIn('employee', 'Employee@12345')).username,
      'employee',
    );
    await rejects(manager.setUserActive(quangUser, false), 'quyền');
    await rejects(admin.setUserActive(admin.session.userId, false), 'tự khóa');
    await rejects(admin.setUserActive(99999, true), 'Không tìm thấy');
  });

  testWidgets(
    'The Tài khoản list has a reset button that validates and saves',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(session: admin.session, repository: admin),
        ),
      );
      for (
        var i = 0;
        i < 60 && find.text('Tài khoản').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Tài khoản').last);
      for (
        var i = 0;
        i < 60 &&
            find.byKey(Key('reset-password-$quangUser')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byKey(Key('reset-password-$quangUser')));
      await tester.pump(const Duration(milliseconds: 500));
      // Quá ngắn và không khớp: báo lỗi, chưa lưu.
      await tester.enterText(find.byKey(const Key('reset-password')), 'abc');
      await tester.tap(find.byKey(const Key('reset-save')));
      await tester.pump();
      expect(find.text('Mật khẩu cần ít nhất 8 ký tự'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('reset-password')),
        'MatKhauMoi@1',
      );
      await tester.enterText(
        find.byKey(const Key('reset-confirm')),
        'KhacNhau@123',
      );
      await tester.tap(find.byKey(const Key('reset-save')));
      await tester.pump();
      expect(find.text('Hai mật khẩu chưa khớp'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('reset-confirm')),
        'MatKhauMoi@1',
      );
      await tester.tap(find.byKey(const Key('reset-save')));
      for (
        var i = 0;
        i < 60 && find.textContaining('Đã đặt lại mật khẩu').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.textContaining('Đã đặt lại mật khẩu cho employee'),
        findsOneWidget,
      );
      expect(
        (await tester.runAsync(
          () => f.auth.signIn('employee', 'MatKhauMoi@1'),
        ))!.username,
        'employee',
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    },
  );
}
