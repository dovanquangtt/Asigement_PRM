import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/dashboard_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager, admin;
  late int branch;
  final month = DateTime(DateTime.now().year, DateTime.now().month);
  final last = DateTime(month.year, month.month + 1, 0);
  // Giữa tháng hiện tại (UTC), tránh lệch ngày do múi giờ.
  final mid = DateTime.utc(month.year, month.month, 15, 2);

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    admin = await repo('admin', 'Admin@12345');
    branch = employee.session.profile['branch_id'] as int;
  });
  tearDown(() => f.dispose());

  Future<int> assigned(DateTime start, {int staff = 1}) async {
    final shift = await manager.createShift(
      branchId: branch,
      start: start,
      end: start.add(const Duration(hours: 8)),
      requiredStaff: staff,
    );
    await manager.assignShift(shift, employee.session.profile['id'] as int);
    return (await f.db.query(
          'shift_assignments',
          where: 'shift_id=?',
          whereArgs: [shift],
        )).single['id']
        as int;
  }

  test(
    'Summary counts shifts, attendance, hours, leave and payroll for the month',
    () async {
      final a = await assigned(mid, staff: 2); // thiếu 1 người
      await assigned(mid.add(const Duration(days: 1)));
      await f.db.insert('attendance_records', {
        'assignment_id': a,
        'check_in_at': mid
            .toIso8601String()
            .substring(0, 19)
            .replaceFirst('T', ' '),
        'check_out_at': mid
            .add(const Duration(hours: 8))
            .toIso8601String()
            .substring(0, 19)
            .replaceFirst('T', ' '),
        'worked_minutes': 450,
        'overtime_minutes': 30,
        'late_minutes': 5,
        'arrival_status': 'LATE',
        'attendance_state': 'COMPLETED',
        'status': 'present',
      });
      final annual = (await f.db.query(
        'leave_types',
        where: "code='ANNUAL'",
      )).single['id'];
      await f.db.insert('leave_requests', {
        'employee_id': employee.session.profile['id'],
        'leave_type_id': annual,
        'starts_at': '2026-01-01 00:00:00',
        'ends_at': '2026-01-01 08:00:00',
        'requested_minutes': 480,
        'reason': 'Ngoài tháng',
        'status': 'pending',
      });
      await employee.createLeaveRequest(
        leaveTypeId: annual as int,
        start: mid.add(const Duration(days: 5)),
        end: mid.add(const Duration(days: 5, hours: 8)),
        reason: 'Trong tháng',
      );

      final d = await manager.dashboardSummary(from: month, to: last);
      final shifts = d['shifts'] as RowData;
      expect(shifts['total'], 2);
      expect(shifts['scheduled'], 2);
      expect(shifts['assignments'], 2);
      expect(shifts['understaffed'], 1);
      final att = d['attendance'] as RowData;
      expect(att['records'], 1);
      expect(att['late'], 1);
      expect(att['on_time'], 0);
      final hours = d['hours'] as RowData;
      expect(hours['worked_minutes'], 450);
      expect(hours['overtime_minutes'], 30);
      expect(hours['late_minutes'], 5);
      final leave = d['leave'] as RowData;
      expect(leave['pending'], 1); // yêu cầu tháng 1 không được tính
      expect((d['employees'] as RowData)['active'], greaterThan(0));
      expect((d['payroll'] as RowData)['payslips'], isA<int>());
    },
  );

  test('Manager is limited to the own branch, employee has no access, range is validated', () async {
    final other = await f.db.insert('branches', {
      'code': 'DASH2',
      'name': 'Chi nhánh khác',
    });
    await f.db.insert('employees', {
      'employee_code': 'DASH-X',
      'full_name': 'Người chi nhánh khác',
      'branch_id': other,
      'hire_date': '2026-01-01',
      'status': 'active',
    });
    final all =
        (await admin.dashboardSummary(from: month, to: last))['employees']
            as RowData;
    final own =
        (await manager.dashboardSummary(from: month, to: last))['employees']
            as RowData;
    expect(all['active'] as int, greaterThan(own['active'] as int));

    await expectLater(
      employee.dashboardSummary(from: month, to: last),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      manager.dashboardSummary(from: last, to: month),
      throwsA(isA<AuthException>()),
    );
  });

  testWidgets(
    'Dashboard screen shows each statistics block and changes month',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late DatabaseFixture db;
      late WorkforceRepository m;
      await tester.runAsync(() async {
        db = await DatabaseFixture.open(keepSampleUsers: true);
        m = WorkforceRepository(
          await db.auth.signIn('manager', 'Manager@12345'),
          openDatabase: () async => db.db,
        );
      });
      addTearDown(() => tester.runAsync(() => db.dispose()));
      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(repository: m)),
      );
      for (var i = 0; i < 40 && find.text('Nhân sự').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final title in [
        'Nhân sự',
        'Ca làm',
        'Điểm danh',
        'Nghỉ phép',
        'Giờ làm',
        'Lương',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Tháng ${month.month}/${month.year}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dashboard-prev')));
      await tester.pump();
      final prev = DateTime(month.year, month.month - 1);
      expect(find.text('Tháng ${prev.month}/${prev.year}'), findsOneWidget);
      // Let the previous month finish loading before the test (and its database) is torn down.
      for (var i = 0; i < 40 && find.text('Nhân sự').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Nhân sự'), findsOneWidget);
    },
  );
}
