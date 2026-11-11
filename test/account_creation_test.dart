import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Admin tạo tài khoản Quản lý/Nhân viên (không tạo được Admin); tài khoản mới có hồ sơ nhân viên
/// và dùng được đầy đủ chức năng như tài khoản mẫu Đỗ Văn Quang.
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

  Future<WorkforceRepository> newAccount(
    String username, {
    String role = 'employee',
    String name = 'Lê Thị Mai',
    int? salary,
  }) async {
    await admin.createUser(
      username: username,
      password: 'Mai@123456',
      role: role,
      fullName: name,
      monthlySalary: salary,
    );
    return repo(username, 'Mai@123456');
  }

  test(
    'Admin cannot create an Admin account; only Quản lý or Nhân viên',
    () async {
      await expectLater(
        admin.createUser(
          username: 'admin2',
          password: 'Admin2@12345',
          role: 'admin',
          fullName: 'Admin hai',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Chỉ tạo được tài khoản Quản lý hoặc Nhân viên.',
          ),
        ),
      );
      expect(await f.db.query('users', where: "username='admin2'"), isEmpty);
      for (final role in ['manager', 'employee']) {
        await admin.createUser(
          username: 'ok_$role',
          password: 'Valid@12345',
          role: role,
          fullName: 'Người $role',
        );
      }
      expect(
        await f.db.query('users', where: "username LIKE 'ok_%'"),
        hasLength(2),
      );
    },
  );

  test(
    'Invalid input creates nothing (no account without a profile)',
    () async {
      Future<void> rejects(Future<int> call, String part) => expectLater(
        call,
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains(part),
          ),
        ),
      );
      final users = (await f.db.query('users')).length;
      final employees = (await f.db.query('employees')).length;
      await rejects(
        admin.createUser(
          username: 'x1',
          password: 'Valid@12345',
          role: 'employee',
        ),
        'họ tên',
      );
      await rejects(
        admin.createUser(
          username: ' ',
          password: 'Valid@12345',
          role: 'employee',
          fullName: 'A',
        ),
        'Tên đăng nhập',
      );
      await rejects(
        admin.createUser(
          username: 'employee',
          password: 'Valid@12345',
          role: 'employee',
          fullName: 'A',
        ),
        'đã tồn tại',
      );
      await rejects(
        admin.createUser(
          username: 'x2',
          password: 'Valid@12345',
          role: 'employee',
          fullName: 'A',
          branchId: 99999,
        ),
        'Chi nhánh',
      );
      await rejects(
        admin.createUser(
          username: 'x3',
          password: 'Valid@12345',
          role: 'employee',
          fullName: 'A',
          monthlySalary: -1,
        ),
        'Lương',
      );
      await expectLater(
        admin.createUser(
          username: 'x4',
          password: 'short',
          role: 'employee',
          fullName: 'A',
        ),
        throwsA(isA<AuthException>()),
      );
      // Chỉ Admin có quyền tạo tài khoản.
      await expectLater(
        manager.createUser(
          username: 'x5',
          password: 'Valid@12345',
          role: 'employee',
          fullName: 'A',
        ),
        throwsA(isA<AuthException>()),
      );
      expect((await f.db.query('users')).length, users);
      expect((await f.db.query('employees')).length, employees);
    },
  );

  test('A new employee account comes with a linked profile, annual leave and optional contract', () async {
    final id = await admin.createUser(
      username: 'mai',
      password: 'Mai@123456',
      role: 'employee',
      fullName: 'Lê Thị Mai',
      phone: '0901234567',
      monthlySalary: 9000000,
    );
    final user = (await f.db.query('users', where: "username='mai'")).single;
    final profile = (await f.db.query(
      'employees',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    expect(profile['user_id'], user['id']);
    expect(profile['full_name'], 'Lê Thị Mai');
    expect(profile['phone'], '0901234567');
    expect(profile['status'], 'active');
    expect(profile['employee_code'], startsWith('NV'));
    expect(profile['branch_id'], quang.session.profile['branch_id']);
    // Cùng bộ phận Phục vụ và chức danh Nhân viên phục vụ như hồ sơ mẫu.
    expect(profile['department_id'], quang.session.profile['department_id']);
    expect(profile['position_id'], quang.session.profile['position_id']);
    final balance = (await f.db.query(
      'leave_balances',
      where: 'employee_id=?',
      whereArgs: [id],
    )).single;
    expect(balance['granted_minutes'], 5760);
    expect(balance['used_minutes'], 0);
    final contract = (await f.db.query(
      'contracts',
      where: 'employee_id=?',
      whereArgs: [id],
    )).single;
    expect(contract['base_salary_vnd'], 9000000);
    expect(contract['status'], 'active');
    // Không nhập lương thì không tạo hợp đồng.
    final other = await admin.createUser(
      username: 'lan',
      password: 'Lan@123456',
      role: 'employee',
      fullName: 'Nguyễn Lan',
    );
    expect(
      await f.db.query('contracts', where: 'employee_id=?', whereArgs: [other]),
      isEmpty,
    );
    // Mã nhân viên không trùng nhau.
    final codes = (await f.db.query('employees'))
        .map((e) => e['employee_code'])
        .toList();
    expect(codes.toSet().length, codes.length);
    expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'The new employee has exactly the same permissions as Đỗ Văn Quang',
    () async {
      final mai = await newAccount('mai');
      Future<Set<Object?>> perms(WorkforceRepository r) async =>
          (await f.db.rawQuery(
            'SELECT p.code FROM user_roles ur JOIN role_permissions rp ON rp.role_id=ur.role_id JOIN permissions p ON p.id=rp.permission_id WHERE ur.user_id=?',
            [r.session.userId],
          )).map((r) => r['code']).toSet();
      expect(await perms(mai), await perms(quang));
      expect(mai.session.role, 'Nhân viên');
      expect(
        mai.session.profile['branch_id'],
        quang.session.profile['branch_id'],
      );
    },
  );

  test('The new employee can use every employee function from the first login', () async {
    final mai = await newAccount('mai');
    // Các màn của nhân viên đều tải được (trước đây báo chưa có hồ sơ nhân viên).
    expect((await mai.overview())['shifts'], 0);
    expect(await mai.shifts(), isEmpty);
    expect(await mai.employeeSchedule(), isEmpty);
    expect(await mai.swappableShifts(), isEmpty);
    expect(await mai.swaps(), isEmpty);
    expect(await mai.payslips(), isEmpty);
    expect(await mai.closures(), isEmpty);
    expect(await mai.attendanceHistory(), isEmpty);
    expect(await mai.notifications(), isEmpty);
    expect(await mai.myAttendanceDevices(), isEmpty);
    expect((await mai.attendanceManagement(self: true))['employees'], 1);
    final annual = (await mai.leaveBalances()).firstWhere(
      (b) => b['code'] == 'ANNUAL',
    );
    expect(annual['granted_minutes'], 5760);
    expect(annual['remaining_minutes'], 5760);

    // Xin nghỉ phép: quản lý nhận thông báo và duyệt được, số ngày phép bị trừ.
    final from = DateTime.now().toUtc().add(const Duration(days: 20));
    await mai.createLeaveRequest(
      leaveTypeId: annual['leave_type_id'] as int,
      start: from,
      end: from.add(const Duration(hours: 8)),
      reason: 'Việc gia đình',
    );
    expect(
      (await manager.notifications()).any(
        (n) => n['title'] == 'Yêu cầu nghỉ phép mới',
      ),
      isTrue,
    );
    final leave = (await manager.leaveRequestsForReview()).first;
    await manager.reviewLeaveRequest(leave['id'] as int, true, note: 'OK');
    expect(
      (await mai.leaveBalances()).firstWhere(
        (b) => b['code'] == 'ANNUAL',
      )['used_minutes'],
      480,
    );

    // Quản lý phân ca: nhân viên mới nhận thông báo, chấp nhận ca và thấy ca trong lịch.
    final start = DateTime.now().toUtc().add(const Duration(days: 3));
    final shift = await manager.createShift(
      branchId: mai.session.profile['branch_id'] as int,
      start: start,
      end: start.add(const Duration(hours: 4)),
    );
    await manager.assignShift(shift, mai.session.profile['id'] as int);
    expect(
      (await mai.notifications()).any((n) => n['title'] == 'Bạn có ca làm mới'),
      isTrue,
    );
    final assignment =
        (await mai.employeeSchedule()).single['assignment_id'] as int;
    await mai.respondAssignment(assignment, true);
    expect(
      (await mai.employeeSchedule()).single['response_status'],
      'accepted',
    );
    expect(await mai.shifts(), hasLength(1));

    // Đăng ký thiết bị và điểm danh: bằng chứng chưa được duyệt nên chờ quản lý xử lý.
    final evidence = AttendanceEvidence(
      deviceIdentifier: 'mai-phone',
      platform: 'android',
      collectedAt: DateTime.now().toUtc(),
      latitude: 10.77,
      longitude: 106.69,
      accuracy: 5,
      ssid: 'Wifi',
      bssid: 'aa:bb:cc:dd:ee:ff',
    );
    await mai.registerDevice(evidence);
    expect(await mai.myAttendanceDevices(), hasLength(1));
    final event = await mai.submitAttendance(
      assignment,
      'check_in',
      evidence,
      now: start,
    );
    expect(
      (await manager.attendanceSubmissions()).any((e) => e['id'] == event),
      isTrue,
    );
    expect((await mai.attendanceHistory()).single['id'], event);

    // Đổi ca với một đồng nghiệp: có người để đổi cùng.
    final qStart = start.add(const Duration(days: 1));
    final qShift = await manager.createShift(
      branchId: mai.session.profile['branch_id'] as int,
      start: qStart,
      end: qStart.add(const Duration(hours: 4)),
    );
    await manager.assignShift(qShift, quang.session.profile['id'] as int);
    final qAssignment =
        (await quang.employeeSchedule()).single['assignment_id'] as int;
    // Ca của Mai đã có điểm danh nên không đổi được; thêm ca thứ hai chưa điểm danh.
    final second = start.add(const Duration(days: 2));
    final s2 = await manager.createShift(
      branchId: mai.session.profile['branch_id'] as int,
      start: second,
      end: second.add(const Duration(hours: 4)),
    );
    await manager.assignShift(s2, mai.session.profile['id'] as int);
    final maiSecond =
        (await mai.employeeSchedule()).firstWhere(
              (s) => s['shift_id'] == s2,
            )['assignment_id']
            as int;
    await mai.requestSwap(maiSecond, qAssignment, 'Có việc riêng');
    expect(
      (await quang.notifications()).any(
        (n) => n['title'] == 'Yêu cầu đổi ca mới',
      ),
      isTrue,
    );
    await quang.respondSwap((await mai.swaps()).single['id'] as int, true);
    await admin.respondSwap(
      (await mai.swaps()).single['id'] as int,
      true,
      review: true,
    );
    expect(
      (await mai.employeeSchedule()).any(
        (s) => s['assignment_id'] == qAssignment,
      ),
      isTrue,
    );
  });

  test('A new manager account works as a manager of its branch', () async {
    final qlm = await newAccount(
      'ql_mai',
      role: 'manager',
      name: 'Quản lý Mai',
    );
    expect(qlm.session.role, 'Quản lý');
    final employees = await qlm.shiftTableEmployees();
    expect(employees.any((e) => e['full_name'] == 'Quản lý Mai'), isTrue);
    expect(employees.any((e) => e['full_name'] == 'Đỗ Văn Quang'), isTrue);
    final start = DateTime.now().toUtc().add(const Duration(days: 4));
    final shift = await qlm.createShift(
      branchId: qlm.session.profile['branch_id'] as int,
      start: start,
      end: start.add(const Duration(hours: 4)),
    );
    await qlm.assignShift(shift, quang.session.profile['id'] as int);
    expect((await qlm.allShifts()).any((s) => s['id'] == shift), isTrue);
    expect(await qlm.leaveRequestsForReview(), isEmpty);
    final now = DateTime.now();
    expect(
      (await qlm.dashboardSummary(
        from: DateTime(now.year, now.month),
        to: DateTime(now.year, now.month + 1, 0),
      ))['employees'],
      isNotNull,
    );
    // Quản lý không quản lý tài khoản người dùng.
    await expectLater(qlm.users(), throwsA(isA<AuthException>()));
    // Quản lý có số ngày phép như nhân viên.
    expect(
      (await qlm.leaveBalances()).firstWhere(
        (b) => b['code'] == 'ANNUAL',
      )['granted_minutes'],
      5760,
    );
  });

  group('screens', () {
    Future<void> settle(WidgetTester tester, Finder until) async {
      for (var i = 0; i < 50 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> openWorkspace(
      WidgetTester tester,
      WorkforceRepository who,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(session: who.session, repository: who),
        ),
      );
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }

    testWidgets(
      'Logging in as the new employee shows a working home with the employee features',
      (tester) async {
        final mai = await tester.runAsync(() => newAccount('mai'));
        await openWorkspace(tester, mai!);
        await settle(tester, find.text('Chức năng'));
        expect(find.text('Chào Lê Thị Mai'), findsOneWidget);
        expect(find.text('Đổi ca'), findsOneWidget);
        expect(find.text('Lịch sử điểm danh'), findsOneWidget);
        expect(find.text('Ảnh & báo cáo đóng ca'), findsOneWidget);
        expect(find.text('Công của tôi & yêu cầu sửa công'), findsOneWidget);
        expect(find.text('Lịch ca, phân ca & điểm danh'), findsNothing);
        expect(find.textContaining('chưa được liên kết'), findsNothing);
        // Tab "Lịch ca" mở được và hiện số ngày phép.
        await tester.tap(find.text('Lịch ca').last);
        await tester.pump();
        await settle(tester, find.byKey(const Key('leave-balances')));
        expect(find.byKey(const Key('leave-balances')), findsOneWidget);
        await close(tester);
      },
    );
  });
}
