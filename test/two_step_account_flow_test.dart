import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Luồng thêm người gồm hai bước: (1) Admin thêm nhân viên (hồ sơ), (2) Admin tạo tài khoản
/// cho hồ sơ đó. Tài khoản tạo xong phải dùng được mọi chức năng.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager, quang;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    admin = await repo('admin', 'Admin@12345');
    manager = await repo('manager', 'Manager@12345');
    quang = await repo('employee', 'Employee@12345');
  });
  tearDown(() => f.dispose());

  Future<void> rejects(Future<Object?> call, String part) => expectLater(
    call,
    throwsA(
      isA<AuthException>().having((e) => e.message, 'message', contains(part)),
    ),
  );

  group('step 1: employee profile', () {
    test('creates a complete profile without an account', () async {
      final id = await admin.createEmployee(
        name: ' Lê Thị Mai ',
        phone: '0901234567',
        monthlySalary: 9000000,
      );
      final p = (await f.db.query(
        'employees',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(p['full_name'], 'Lê Thị Mai');
      expect(p['user_id'], isNull);
      expect(p['status'], 'active');
      expect(p['employee_code'], startsWith('NV'));
      expect(p['department_id'], quang.session.profile['department_id']);
      expect(p['position_id'], quang.session.profile['position_id']);
      expect(p['branch_id'], quang.session.profile['branch_id']);
      expect(
        (await f.db.query(
          'leave_balances',
          where: 'employee_id=?',
          whereArgs: [id],
        )).single['granted_minutes'],
        5760,
      );
      expect(
        (await f.db.query(
          'contracts',
          where: 'employee_id=?',
          whereArgs: [id],
        )).single['base_salary_vnd'],
        9000000,
      );
    });

    test('validates input and permissions', () async {
      await rejects(admin.createEmployee(name: ' '), 'họ tên');
      await rejects(
        admin.createEmployee(name: 'A', code: 'DEMO_EMPLOYEE'),
        'đã tồn tại',
      );
      await rejects(
        admin.createEmployee(name: 'A', branchId: 99999),
        'Chi nhánh',
      );
      await rejects(
        admin.createEmployee(name: 'A', monthlySalary: -5),
        'Lương',
      );
      await expectLater(
        quang.createEmployee(name: 'A'),
        throwsA(isA<AuthException>()),
      );
      final a = await admin.createEmployee(name: 'A');
      final b = await admin.createEmployee(name: 'B');
      final codes = (await f.db.query(
        'employees',
        where: 'id IN (?,?)',
        whereArgs: [a, b],
      )).map((e) => e['employee_code']).toSet();
      expect(codes, hasLength(2), reason: 'auto codes are unique');
    });
  });

  group('step 2: account for an existing profile', () {
    test('only profiles without an account are offered', () async {
      expect(
        await admin.employeesWithoutAccount(),
        isEmpty,
        reason: 'sample users are all linked',
      );
      final id = await admin.createEmployee(name: 'Lê Thị Mai');
      final list = await admin.employeesWithoutAccount();
      expect(list.single['id'], id);
      await expectLater(
        manager.employeesWithoutAccount(),
        throwsA(isA<AuthException>()),
      );
      await admin.createAccountForEmployee(
        employeeId: id,
        username: 'mai',
        password: 'Mai@123456',
        role: 'employee',
      );
      expect(await admin.employeesWithoutAccount(), isEmpty);
    });

    test('validates role, profile, duplicates and permissions; nothing is left behind', () async {
      final id = await admin.createEmployee(name: 'Lê Thị Mai');
      final users = (await f.db.query('users')).length;
      await rejects(
        admin.createAccountForEmployee(
          employeeId: id,
          username: 'x',
          password: 'Valid@12345',
          role: 'admin',
        ),
        'Quản lý hoặc Nhân viên',
      );
      await rejects(
        admin.createAccountForEmployee(
          employeeId: 99999,
          username: 'x',
          password: 'Valid@12345',
          role: 'employee',
        ),
        'Nhân sự',
      );
      await rejects(
        admin.createAccountForEmployee(
          employeeId: id,
          username: ' ',
          password: 'Valid@12345',
          role: 'employee',
        ),
        'Tên đăng nhập',
      );
      await rejects(
        admin.createAccountForEmployee(
          employeeId: id,
          username: 'EMPLOYEE',
          password: 'Valid@12345',
          role: 'employee',
        ),
        'đã tồn tại',
      );
      await expectLater(
        admin.createAccountForEmployee(
          employeeId: id,
          username: 'x',
          password: 'short',
          role: 'employee',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        manager.createAccountForEmployee(
          employeeId: id,
          username: 'x',
          password: 'Valid@12345',
          role: 'employee',
        ),
        throwsA(isA<AuthException>()),
      );
      expect((await f.db.query('users')).length, users);
      await admin.createAccountForEmployee(
        employeeId: id,
        username: 'mai',
        password: 'Mai@123456',
        role: 'employee',
      );
      await rejects(
        admin.createAccountForEmployee(
          employeeId: id,
          username: 'mai2',
          password: 'Mai@123456',
          role: 'employee',
        ),
        'đã có tài khoản',
      );
      // Hồ sơ đã nghỉ việc không cấp tài khoản.
      final gone = await admin.createEmployee(name: 'Đã nghỉ');
      await f.db.update(
        'employees',
        {'status': 'terminated'},
        where: 'id=?',
        whereArgs: [gone],
      );
      await rejects(
        admin.createAccountForEmployee(
          employeeId: gone,
          username: 'gone',
          password: 'Valid@12345',
          role: 'employee',
        ),
        'đang làm việc',
      );
    });

    test('the account is linked to the profile with the role permissions and position', () async {
      final emp = await admin.createEmployee(name: 'Lê Thị Mai');
      final mgr = await admin.createEmployee(name: 'Quản Lý Hoa');
      final eUser = await admin.createAccountForEmployee(
        employeeId: emp,
        username: 'mai',
        password: 'Mai@123456',
        role: 'employee',
      );
      final mUser = await admin.createAccountForEmployee(
        employeeId: mgr,
        username: 'hoa',
        password: 'Hoa@123456',
        role: 'manager',
      );
      expect(
        (await f.db.query(
          'employees',
          where: 'id=?',
          whereArgs: [emp],
        )).single['user_id'],
        eUser,
      );
      final mProfile = (await f.db.query(
        'employees',
        where: 'id=?',
        whereArgs: [mgr],
      )).single;
      expect(mProfile['user_id'], mUser);
      final managerPosition = (await f.db.query(
        'positions',
        where: "code='MANAGER'",
      )).single['id'];
      expect(mProfile['position_id'], managerPosition);
      final mai = await repo('mai', 'Mai@123456');
      expect(mai.session.role, 'Nhân viên');
      Future<Set<Object?>> perms(WorkforceRepository r) async =>
          (await f.db.rawQuery(
            'SELECT p.code FROM user_roles ur JOIN role_permissions rp ON rp.role_id=ur.role_id JOIN permissions p ON p.id=rp.permission_id WHERE ur.user_id=?',
            [r.session.userId],
          )).map((r) => r['code']).toSet();
      expect(await perms(mai), await perms(quang));
      expect((await repo('hoa', 'Hoa@123456')).session.role, 'Quản lý');
    });
  });

  test('a fresh employee works end to end after the two steps', () async {
    final id = await admin.createEmployee(
      name: 'Lê Thị Mai',
      monthlySalary: 9000000,
    );
    await admin.createAccountForEmployee(
      employeeId: id,
      username: 'mai',
      password: 'Mai@123456',
      role: 'employee',
    );
    final mai = await repo('mai', 'Mai@123456');
    expect(mai.session.profile['id'], id);
    expect(mai.session.profile['full_name'], 'Lê Thị Mai');
    expect(await mai.shifts(), isEmpty);
    expect(await mai.employeeSchedule(), isEmpty);
    expect(await mai.myPayrolls(), isEmpty);
    expect((await mai.estimatePay())['has_period'], isFalse);
    expect(await mai.closureTasks(), isEmpty);
    expect(await mai.swaps(), isEmpty);
    expect(
      (await mai.leaveBalances()).firstWhere(
        (b) => b['code'] == 'ANNUAL',
      )['remaining_minutes'],
      5760,
    );
    // Quản lý phân ca và nhân viên thấy ngay.
    final start = DateTime.now().toUtc().add(const Duration(days: 3));
    final shift = await manager.createShift(
      branchId: mai.session.profile['branch_id'] as int,
      start: start,
      end: start.add(const Duration(hours: 4)),
    );
    await manager.assignShift(shift, id);
    expect(
      (await mai.notifications()).any((n) => n['title'] == 'Bạn có ca làm mới'),
      isTrue,
    );
    expect(await mai.employeeSchedule(), hasLength(1));
  });

  test(
    'legacy account without a profile is listed and can be linked to a profile',
    () async {
      final orphan = await f.addUser(username: 'cu');
      final row = (await admin.users()).firstWhere((u) => u['id'] == orphan);
      expect(row['employee_id'], isNull);
      // Hồ sơ bị chặn bởi thông báo rõ ràng.
      final legacy = WorkforceRepository(
        await f.auth.signIn('cu', 'TestPass123!'),
        openDatabase: () async => f.db,
      );
      await expectLater(
        legacy.leaveBalances(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'm',
            contains('Admin liên kết'),
          ),
        ),
      );
      final profile = await admin.createEmployee(name: 'Người cũ');
      await admin.linkEmployee(profile, orphan);
      expect(
        (await admin.users()).firstWhere(
          (u) => u['id'] == orphan,
        )['employee_name'],
        'Người cũ',
      );
      final fixed = WorkforceRepository(
        await f.auth.signIn('cu', 'TestPass123!'),
        openDatabase: () async => f.db,
      );
      expect(await fixed.leaveBalances(), isNotEmpty);
    },
  );

  group('screens', () {
    Future<void> settle(WidgetTester tester, Finder until) async {
      for (var i = 0; i < 60 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }

    testWidgets(
      'Admin adds the employee first, then creates the account, and the new login works',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Workspace(session: admin.session, repository: admin),
          ),
        );
        await settle(tester, find.text('Nhân sự'));

        // Chưa có hồ sơ nào cần tài khoản: form tài khoản chỉ dẫn quay lại bước 1.
        await tester.tap(find.text('Tài khoản').last);
        await tester.pump();
        await settle(tester, find.text('Tạo tài khoản'));
        await tester.tap(find.text('Tạo tài khoản'));
        await settle(tester, find.byKey(const Key('account-no-employee')));
        expect(find.byKey(const Key('account-no-employee')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('create-save')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Hủy'));
        await tester.pump(const Duration(milliseconds: 400));

        // Bước 1: thêm nhân viên.
        await tester.tap(find.text('Nhân sự').last);
        await tester.pump();
        await settle(tester, find.text('Thêm nhân viên'));
        await tester.tap(find.text('Thêm nhân viên'));
        await settle(tester, find.byKey(const Key('employee-name')));
        await tester.tap(find.byKey(const Key('create-save')));
        await tester.pump();
        expect(find.text('Không được để trống'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('employee-name')),
          'Lê Thị Mai',
        );
        await tester.enterText(
          find.byKey(const Key('employee-phone')),
          '0901234567',
        );
        await tester.tap(find.byKey(const Key('create-save')));
        await settle(tester, find.textContaining('Đã thêm nhân viên'));
        expect(find.textContaining('Đã thêm nhân viên'), findsOneWidget);
        expect(find.text('Lê Thị Mai'), findsWidgets);

        // Bước 2: tạo tài khoản cho hồ sơ vừa thêm.
        await tester.pump(
          const Duration(seconds: 5),
        ); // thanh thông báo trước đó tự tắt
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Tài khoản').last);
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester, find.text('Tạo tài khoản'));
        await tester.tap(find.text('Tạo tài khoản'));
        await settle(tester, find.byKey(const Key('account-employee')));
        final roles = tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: find.byKey(const Key('account-role')),
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .items!
            .map((i) => i.value)
            .toList();
        expect(roles, ['manager', 'employee']);
        await tester.enterText(
          find.byKey(const Key('account-username')),
          'mai_ui',
        );
        await tester.enterText(
          find.byKey(const Key('account-password')),
          'Mai@123456',
        );
        await tester.tap(find.byKey(const Key('create-save')));
        await settle(tester, find.textContaining('Đã tạo tài khoản'));
        expect(find.textContaining('Đã tạo tài khoản'), findsOneWidget);
        final linked = (await tester.runAsync(
          () => f.db.rawQuery(
            "SELECT e.full_name FROM users u JOIN employees e ON e.user_id=u.id WHERE u.username='mai_ui'",
          ),
        ))!;
        expect(linked.single['full_name'], 'Lê Thị Mai');
        await close(tester);

        // Đăng nhập bằng tài khoản mới: màn chính chạy bình thường, không báo thiếu hồ sơ.
        final mai = (await tester.runAsync(
          () => repo('mai_ui', 'Mai@123456'),
        ))!;
        await tester.pumpWidget(
          MaterialApp(
            home: Workspace(session: mai.session, repository: mai),
          ),
        );
        await settle(tester, find.text('Chức năng'));
        expect(find.text('Chào Lê Thị Mai'), findsOneWidget);
        await tester.tap(find.text('Lịch ca').last);
        await tester.pump();
        await settle(tester, find.byKey(const Key('leave-balances')));
        expect(find.byKey(const Key('leave-balances')), findsOneWidget);
        expect(find.textContaining('chưa được liên kết'), findsNothing);
        await close(tester);
      },
    );
  });
}
