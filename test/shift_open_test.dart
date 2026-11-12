import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/schedule_screen.dart';
import 'package:quanlinhansunhahang/screens/shift_swap_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Quản lý tạo ca → nhân viên được báo "Có ca làm mới" nhưng ca chưa thuộc ai. Nhân viên phải thấy
/// ca đó ở "Ca còn trống", đăng ký được, và sau đó ca nằm trong lịch và danh sách đổi ca.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager, quang;
  late int branch;

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
    branch = quang.session.profile['branch_id'] as int;
  });
  tearDown(() => f.dispose());

  Future<int> newShift({int days = 13, int staff = 2, int? branchId}) {
    final start = DateTime.now().toUtc().add(Duration(days: days));
    return admin.createShift(
      branchId: branchId ?? branch,
      start: start,
      end: start.add(const Duration(hours: 8)),
      requiredStaff: staff,
    );
  }

  test('an unassigned new shift notifies employees, is open, and is not in the personal schedule', () async {
    final id = await newShift();
    expect(
      (await quang.notifications()).any((n) => n['title'] == 'Có ca làm mới'),
      isTrue,
    );
    expect(await quang.employeeSchedule(), isEmpty);
    expect(await quang.swappableShifts(), isEmpty);
    final open = await quang.openShifts();
    expect(open.single['id'], id);
    expect(open.single['assigned_count'], 0);
  });

  test(
    'registering puts the shift in the schedule and notifies managers',
    () async {
      final id = await newShift();
      await quang.registerForShift(id);
      expect(await quang.openShifts(), isEmpty);
      final schedule = await quang.employeeSchedule();
      expect(schedule.single['shift_id'], id);
      expect(schedule.single['response_status'], 'accepted');
      expect(
        (await manager.notifications()).any(
          (n) => n['title'] == 'Nhân viên đăng ký ca',
        ),
        isTrue,
      );
      expect(
        (await admin.notifications()).any(
          (n) => n['title'] == 'Nhân viên đăng ký ca',
        ),
        isTrue,
      );
      // Quản lý vẫn gỡ được phân công.
      await manager.unassignShift(id, quang.session.profile['id'] as int);
      expect(await quang.employeeSchedule(), isEmpty);
      expect(await quang.openShifts(), hasLength(1));
      // Đăng ký lại sau khi bị gỡ được.
      await quang.registerForShift(id);
      expect(await quang.employeeSchedule(), hasLength(1));
    },
  );

  test('registering is refused for full, overlapping, past, other-branch and duplicate shifts', () async {
    Future<void> rejects(Future<void> call, String part) => expectLater(
      call,
      throwsA(
        isA<AuthException>().having((e) => e.message, 'm', contains(part)),
      ),
    );
    final full = await newShift(staff: 1);
    final other = await admin.createEmployee(name: 'Người khác');
    await admin.createAccountForEmployee(
      employeeId: other,
      username: 'khac',
      password: 'Khac@12345',
      role: 'employee',
    );
    final khac = await repo('khac', 'Khac@12345');
    await khac.registerForShift(full);
    await rejects(quang.registerForShift(full), 'đủ nhân viên');
    expect(
      (await quang.openShifts()).where((s) => s['id'] == full),
      isEmpty,
      reason: 'full shifts are hidden',
    );

    final mine = await newShift(days: 14, staff: 3);
    await quang.registerForShift(mine);
    await rejects(quang.registerForShift(mine), 'trùng giờ');
    final overlap = await newShift(days: 14, staff: 3);
    await rejects(quang.registerForShift(overlap), 'trùng giờ');

    final past = await f.db.insert('shifts', {
      'branch_id': branch,
      'starts_at': '2020-01-01 01:00:00',
      'ends_at': '2020-01-01 09:00:00',
      'required_staff': 2,
      'created_by': admin.session.userId,
    });
    await rejects(quang.registerForShift(past), 'đã bắt đầu');
    await rejects(quang.registerForShift(999999), 'Không tìm thấy');

    final b2 = await f.db.insert('branches', {
      'code': 'B2',
      'name': 'Chi nhánh 2',
      'address': 'x',
    });
    final far = await f.db.insert('shifts', {
      'branch_id': b2,
      'starts_at': sqlNext(20),
      'ends_at': sqlNext(20, hours: 8),
      'required_staff': 2,
      'created_by': admin.session.userId,
    });
    await rejects(quang.registerForShift(far), 'chi nhánh khác');
    expect((await quang.openShifts()).where((s) => s['id'] == far), isEmpty);
  });

  test('a registered shift can then be swapped', () async {
    final id = await newShift(days: 15);
    await quang.registerForShift(id);
    final swappable = await quang.swappableShifts();
    expect(swappable.map((s) => s['shift_id']), contains(id));
  });

  testWidgets(
    'The schedule tab shows open shifts and registering moves them into the schedule',
    (tester) async {
      final id = (await tester.runAsync(() => newShift(days: 16)))!;
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScheduleScreen(repository: quang)),
        ),
      );
      for (
        var i = 0;
        i < 60 && find.byKey(const Key('open-shifts')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Ca còn trống (1)'), findsOneWidget);
      await tester.tap(find.byKey(Key('register-shift-$id')));
      for (
        var i = 0;
        i < 60 && find.byKey(const Key('open-shifts')).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('open-shifts')), findsNothing);
      final mine = (await tester.runAsync(quang.employeeSchedule))!;
      expect(mine.single['shift_id'], id);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    },
  );
  group('swap to open shift', swapToOpenTests);

  testWidgets('The swap screen offers open shifts and swaps to one in a tap', (
    tester,
  ) async {
    final (mineShift, openShift) = (await tester.runAsync(() async {
      final a = await newShift(days: 17);
      final b = await newShift(days: 18);
      await quang.registerForShift(a);
      return (a, b);
    }))!;
    await tester.binding.setSurfaceSize(const Size(420, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ShiftSwapScreen(repository: quang)),
    );
    for (
      var i = 0;
      i < 60 && find.text('1 ca còn trống').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('1 ca còn trống'), findsOneWidget);
    final assignment = (await tester.runAsync(quang.employeeSchedule))!
        .single['assignment_id'];
    await tester.tap(find.byKey(Key('swap-pick-$assignment')));
    for (
      var i = 0;
      i < 60 && find.byKey(Key('swap-open-$openShift')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byKey(Key('swap-open-$openShift')));
    for (
      var i = 0;
      i < 30 && find.byKey(const Key('swap-confirm')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('swap-confirm')));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final now = (await tester.runAsync(quang.employeeSchedule))!;
      if (now.isNotEmpty && now.single['shift_id'] == openShift) break;
    }
    final now = (await tester.runAsync(quang.employeeSchedule))!;
    expect(now.single['shift_id'], openShift);
    expect(mineShift, isNot(openShift));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  });
}

String sqlNext(int days, {int hours = 0}) {
  final t = DateTime.now().toUtc().add(Duration(days: days, hours: hours));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Đổi ca của mình sang một ca còn trống (không cần đồng nghiệp đồng ý).
void swapToOpenTests() {
  late DatabaseFixture f;
  late WorkforceRepository admin, manager, quang;
  late int branch;

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
    branch = quang.session.profile['branch_id'] as int;
  });
  tearDown(() => f.dispose());

  Future<int> shift(int days, {int staff = 2}) {
    final start = DateTime.now().toUtc().add(Duration(days: days));
    return admin.createShift(
      branchId: branch,
      start: start,
      end: start.add(const Duration(hours: 8)),
      requiredStaff: staff,
    );
  }

  test(
    'a shift with no coworker shifts can still be swapped for an open shift',
    () async {
      final mineShift = await shift(20);
      final openShift = await shift(21);
      await quang.registerForShift(mineShift);
      final card = (await quang.swappableShifts()).single;
      expect(card['options_count'], 0);
      expect(card['open_count'], 1);
      final mine = card['id'] as int;
      expect((await quang.openSwapTargets(mine)).single['id'], openShift);
      await quang.swapToOpenShift(mine, openShift);
      final schedule = await quang.employeeSchedule();
      expect(schedule.single['shift_id'], openShift);
      // Ca cũ trở lại danh sách ca còn trống; quản lý được báo.
      expect((await quang.openShifts()).single['id'], mineShift);
      expect(
        (await manager.notifications()).any(
          (n) => n['title'] == 'Nhân viên đổi sang ca còn trống',
        ),
        isTrue,
      );
    },
  );

  test('swapToOpenShift validates and is atomic', () async {
    Future<void> rejects(Future<void> call, String part) => expectLater(
      call,
      throwsA(
        isA<AuthException>().having((e) => e.message, 'm', contains(part)),
      ),
    );
    final a = await shift(20);
    final full = await shift(21, staff: 1);
    final b = await shift(22);
    await quang.registerForShift(a);
    final mine = (await quang.swappableShifts()).single['id'] as int;
    final other = await admin.createEmployee(name: 'Người khác');
    await admin.createAccountForEmployee(
      employeeId: other,
      username: 'khac',
      password: 'Khac@12345',
      role: 'employee',
    );
    await (await repo('khac', 'Khac@12345')).registerForShift(full);
    await rejects(quang.swapToOpenShift(mine, full), 'đủ nhân viên');
    await rejects(quang.swapToOpenShift(mine, a), 'khác');
    await rejects(quang.swapToOpenShift(mine, 999999), 'khác');
    // Lỗi thì ca cũ vẫn còn nguyên.
    expect((await quang.employeeSchedule()).single['shift_id'], a);
    // Ca đã điểm danh/đã bắt đầu thì không đổi được.
    final other2 =
        (await quang.employeeSchedule()).single['assignment_id'] as int;
    await f.db.update(
      'shifts',
      {'starts_at': '2020-01-01 01:00:00', 'ends_at': '2020-01-01 09:00:00'},
      where: 'id=?',
      whereArgs: [a],
    );
    expect(await quang.openSwapTargets(other2), isEmpty);
    await rejects(quang.swapToOpenShift(other2, b), 'Ca của bạn');
    // Không đổi ca của người khác.
    await expectLater(
      manager.swapToOpenShift(other2, b),
      throwsA(isA<AuthException>()),
    );
  });
}
