import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager, admin;
  late int assignment;
  final start = DateTime.utc(2026, 10, 16, 1);
  final after = start.add(const Duration(days: 2));
  final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 31);

  AttendanceEvidence sample(
    DateTime at, {
    String bssid = 'aa:bb:cc:dd:ee:ff',
  }) => AttendanceEvidence(
    deviceIdentifier: 'sheet-phone',
    platform: 'android',
    collectedAt: at,
    latitude: 10.77,
    longitude: 106.69,
    accuracy: 5,
    ssid: 'Restaurant',
    bssid: bssid,
  );

  Future<RowData> row({WorkforceRepository? as, int? employeeId}) async {
    final sheet = await (as ?? employee).attendanceSheet(
      employeeId: employeeId,
      from: from,
      to: to,
      now: after,
    );
    return (sheet['rows'] as List<RowData>).singleWhere(
      (r) => r['assignment_id'] == assignment,
    );
  }

  Future<void> fullShift() async {
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    final out = start.add(const Duration(hours: 8));
    await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
  }

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    Future<WorkforceRepository> repo(String name, String pass) async =>
        WorkforceRepository(
          await f.auth.signIn(name, pass),
          openDatabase: () async => f.db,
        );
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    admin = await repo('admin', 'Admin@12345');
    await manager.configureBranch(
      1,
      latitude: 10.77,
      longitude: 106.69,
      radius: 100,
      ssid: 'Restaurant',
      bssid: 'aa:bb:cc:dd:ee:ff',
    );
    await employee.registerDevice(sample(start));
    await manager.approveDevice(
      (await employee.myAttendanceDevices()).single['id'] as int,
    );
    final shift = await manager.createShift(
      branchId: employee.session.profile['branch_id'] as int,
      start: start,
      end: start.add(const Duration(hours: 8)),
    );
    await manager.assignShift(shift, employee.session.profile['id'] as int);
    assignment =
        (await f.db.query(
              'shift_assignments',
              where: 'shift_id=?',
              whereArgs: [shift],
            )).single['id']
            as int;
  });
  tearDown(() => f.dispose());

  test(
    'Employee sees own sheet: missing, then success after check-in/out',
    () async {
      expect((await row())['sheet_status'], 'MISSING_CHECK_IN');
      await fullShift();
      final r = await row();
      expect(r['sheet_status'], 'SUCCESS');
      expect(r['worked_minutes'], 480);
      final sheet = await employee.attendanceSheet(
        from: from,
        to: to,
        now: after,
      );
      expect((sheet['summary'] as RowData)['success'], 1);
      expect((sheet['summary'] as RowData)['worked_minutes'], 480);
    },
  );

  test('Employee cannot read another sheet or edit/void attendance', () async {
    final other = employee.session.profile['id'] as int;
    await expectLater(
      employee.attendanceSheet(employeeId: other + 100, from: from, to: to),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      employee.adminEditAttendance(assignment, checkIn: start, reason: 'x'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      employee.voidAttendance(assignment, reason: 'x'),
      throwsA(isA<AuthException>()),
    );
    expect(
      (await manager.attendanceSheetEmployees()).map((e) => e['id']),
      contains(other),
    );
    expect(await employee.attendanceSheetEmployees(), hasLength(1));
  });

  test(
    'Manager edits times directly; reason is required and employee is notified',
    () async {
      await expectLater(
        manager.adminEditAttendance(assignment, checkIn: start, reason: ' '),
        throwsA(isA<AuthException>()),
      );
      final out = start.add(const Duration(hours: 9));
      await manager.adminEditAttendance(
        assignment,
        checkIn: start,
        checkOut: out,
        reason: 'Quên điểm danh',
      );
      final r = await row(
        as: manager,
        employeeId: employee.session.profile['id'] as int,
      );
      expect(r['sheet_status'], 'SUCCESS');
      expect(r['worked_minutes'], 540);
      expect(r['record_status'], 'adjusted');
      final notes = await employee.notifications();
      expect(notes.any((n) => n['title'] == 'Giờ công đã được chỉnh'), isTrue);
      final audit = await f.db.query(
        'audit_logs',
        where: "action='attendance.admin_edit'",
      );
      expect(audit, hasLength(1));
    },
  );

  test('Void blocks employee check-in; editing restores the record', () async {
    await fullShift();
    await admin.voidAttendance(assignment, reason: 'Nghỉ không báo');
    expect((await row())['sheet_status'], 'VOIDED');
    final voided = (await f.db.query('attendance_records')).single;
    expect(voided['worked_minutes'], 0);
    expect(voided['check_in_at'], isNull);
    await expectLater(
      employee.submitAttendance(
        assignment,
        'check_in',
        sample(start),
        now: start,
      ),
      throwsA(isA<AuthException>()),
    );
    await admin.adminEditAttendance(
      assignment,
      checkIn: start,
      checkOut: start.add(const Duration(hours: 8)),
      reason: 'Khôi phục sau khi xác minh',
    );
    expect((await row())['sheet_status'], 'SUCCESS');
  });

  test(
    'Pending exception shows as pending review and direct edit settles it',
    () async {
      await employee.submitAttendance(
        assignment,
        'check_in',
        sample(start, bssid: '00:00:00:00:00:01'),
        now: start,
      );
      expect((await row())['sheet_status'], 'PENDING_REVIEW');
      await manager.adminEditAttendance(
        assignment,
        checkIn: start,
        reason: 'Đã xác minh tại quán',
      );
      final events = await f.db.query('attendance_events');
      expect(events.single['result'], 'rejected');
      expect((await row())['sheet_status'], isNot('PENDING_REVIEW'));
    },
  );
}
