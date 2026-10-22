import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager, admin;
  late int assignment;
  final start = DateTime.utc(2026, 10, 16, 1);
  AttendanceEvidence sample(DateTime at) => AttendanceEvidence(
    deviceIdentifier: 'policy-phone',
    platform: 'android',
    collectedAt: at,
    latitude: 10.77,
    longitude: 106.69,
    accuracy: 5,
    ssid: 'Restaurant',
    bssid: 'aa:bb:cc:dd:ee:ff',
  );
  Future<int> assign(DateTime at) async {
    final shift = await manager.createShift(
      branchId: employee.session.profile['branch_id'] as int,
      start: at,
      end: at.add(const Duration(hours: 8)),
    );
    await manager.assignShift(shift, employee.session.profile['id'] as int);
    return (await f.db.query(
          'shift_assignments',
          where: 'shift_id=?',
          whereArgs: [shift],
        )).single['id']
        as int;
  }

  Future<RowData> record() async => (await f.db.query(
    'attendance_records',
    where: 'assignment_id=?',
    whereArgs: [assignment],
  )).single;
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
    assignment = await assign(start);
  });
  tearDown(() => f.dispose());
  test('Rejected overtime stays recorded but is not payable', () async {
    await admin.configureBranch(
      1,
      latitude: 10.77,
      longitude: 106.69,
      radius: 100,
      ssid: 'Restaurant',
      bssid: 'aa:bb:cc:dd:ee:ff',
      requireOvertimeApproval: true,
    );
    final out = start.add(const Duration(hours: 9));
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
    await manager.reviewAttendanceOvertime(
      assignment,
      false,
      note: 'Không có yêu cầu làm thêm',
    );
    final r = await record();
    expect(r['worked_minutes'], 540);
    expect(r['overtime_minutes'], 0);
    expect(r['overtime_requested_minutes'], 60);
    expect(r['overtime_status'], 'REJECTED');
  });

  test('Approved payroll prevents retroactive attendance adjustment', () async {
    final out = start.add(const Duration(hours: 8));
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
    await manager.saveContract(
      employee.session.profile['id'] as int,
      'LOCKED_PAY',
      12480000,
      12480,
      DateTime.utc(2026, 10, 1),
    );
    final period = await manager.createPeriod(
      'LOCKED_PAY',
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 31),
      1.5,
    );
    await employee.calculatePay(period);
    await f.db.update(
      'payslips',
      {
        'status': 'approved',
        'approved_by': admin.session.userId,
        'approved_at': sqlTime(DateTime.now()),
      },
      where: 'period_id=?',
      whereArgs: [period],
    );
    await expectLater(
      employee.requestAttendanceAdjustment(
        assignment,
        checkIn: start,
        reason: 'Sửa sau chốt lương',
      ),
      throwsA(isA<AuthException>()),
    );
    expect((await record())['check_in_at'], sqlTime(start));
  });
  test('Missing check-in can be supplemented before reviewing a captured checkout exception', () async {
    final out = start.add(const Duration(hours: 8));
    final event = await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
    expect(
      (await f.db.query('attendance_events')).single['result'],
      'pending_review',
    );
    final request = await employee.requestAttendanceAdjustment(
      assignment,
      checkIn: start,
      reason: 'Quên điểm danh vào',
    );
    await manager.reviewAttendanceAdjustment(
      request,
      true,
      note: 'Đã xác nhận giờ vào',
    );
    await manager.reviewAttendance(
      event,
      true,
      note: 'Giờ ra đã được thiết bị ghi nhận',
    );
    expect((await record())['check_out_at'], sqlTime(out));
    expect((await record())['worked_minutes'], 480);
  });

  test(
    'Legacy pending event can be rejected without losing original evidence',
    () async {
      final event = await f.db.insert('attendance_events', {
        'assignment_id': assignment,
        'event_type': 'check_in',
        'occurred_at': sqlTime(start),
        'device_valid': 0,
        'gps_valid': 0,
        'wifi_valid': 0,
        'result': 'pending_review',
      });
      await manager.reviewAttendance(
        event,
        false,
        note: 'Dữ liệu cũ chưa đủ căn cứ',
      );
      final row = (await f.db.query('attendance_events')).single;
      expect(row['occurred_at'], sqlTime(start));
      expect(row['result'], 'rejected');
      expect(row['reviewed_by'], manager.session.userId);
    },
  );
  for (final offset in [-30, 0, 17]) {
    test(
      'Valid check-in offset $offset automatically records without review or penalty',
      () async {
        final at = start.add(Duration(minutes: offset));
        final id = await employee.submitAttendance(
          assignment,
          'check_in',
          sample(at),
          now: at,
        );
        final event = (await f.db.query(
          'attendance_events',
          where: 'id=?',
          whereArgs: [id],
        )).single;
        expect(event['result'], 'accepted');
        final r = await record();
        expect(r['check_in_at'], sqlTime(at));
        expect(r['arrival_status'], offset > 0 ? 'LATE' : 'ON_TIME');
        expect(r['late_minutes'], offset > 0 ? offset : 0);
        expect(await f.db.query('payslip_items'), isEmpty);
        expect(
          (await manager.attendanceSubmissions()).where(
            (r) => r['result'] == 'pending_review',
          ),
          isEmpty,
        );
      },
    );
  }
  test(
    'Night checkout after midnight belongs to the original assignment',
    () async {
      final night = DateTime.utc(
        2026,
        10,
        17,
        15,
      ); // 22:00 VN, ends at 06:00 next day.
      assignment = await assign(night);
      await employee.submitAttendance(
        assignment,
        'check_in',
        sample(night),
        now: night,
      );
      final out = night.add(const Duration(hours: 9));
      await employee.submitAttendance(
        assignment,
        'check_out',
        sample(out),
        now: out,
      );
      final r = await record();
      expect(r['assignment_id'], assignment);
      expect(r['check_out_at'], sqlTime(out));
      expect(r['overtime_minutes'], 60);
      expect(r['overtime_status'], 'NOT_REQUIRED');
      final overview = await manager.attendanceManagement(
        day: DateTime(2026, 10, 17),
      );
      expect(
        (overview['rows'] as List<RowData>).single['assignment_id'],
        assignment,
      );
    },
  );
  test('Late arrival is separate from overtime and pending overtime is excluded from payroll', () async {
    await admin.configureBranch(
      1,
      latitude: 10.77,
      longitude: 106.69,
      radius: 100,
      ssid: 'Restaurant',
      bssid: 'aa:bb:cc:dd:ee:ff',
      requireOvertimeApproval: true,
    );
    final late = start.add(const Duration(minutes: 15));
    final out = start.add(const Duration(hours: 9));
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(late),
      now: late,
    );
    await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
    var r = await record();
    expect(r['arrival_status'], 'LATE');
    expect(r['worked_minutes'], 525);
    expect(r['overtime_status'], 'PENDING');
    expect(r['overtime_requested_minutes'], 60);
    expect(r['overtime_minutes'], 0);
    await manager.saveContract(
      employee.session.profile['id'] as int,
      'POLICY_TEST',
      12480000,
      12480,
      DateTime.utc(2026, 10, 1),
    );
    final period = await manager.createPeriod(
      'POLICY',
      DateTime.utc(2026, 10, 1),
      DateTime.utc(2026, 10, 31),
      1.5,
    );
    await employee.calculatePay(period);
    var pay = (await employee.payslips()).single;
    expect(pay['regular_minutes'], 465);
    expect(pay['overtime_minutes'], 0);
    await manager.reviewAttendanceOvertime(
      assignment,
      true,
      note: 'Đã xác nhận làm thêm',
    );
    r = await record();
    expect(r['overtime_minutes'], 60);
    expect(r['late_minutes'], 15);
    await employee.calculatePay(period);
    pay = (await employee.payslips()).single;
    expect(pay['regular_minutes'], 465);
    expect(pay['overtime_minutes'], 60);
    expect(pay['overtime_pay_vnd'], 90000);
  });
  test('Missing check-in is flagged; approved supplement does not invent original events', () async {
    final overview = await employee.attendanceManagement(
      day: DateTime(2026, 10, 16),
      self: true,
    );
    expect(
      (overview['rows'] as List<RowData>).single['work_state'],
      'MISSING_CHECK_IN',
    );
    final request = await employee.requestAttendanceAdjustment(
      assignment,
      checkIn: start,
      checkOut: start.add(const Duration(hours: 8)),
      reason: 'Quên điểm danh, ca trưởng xác nhận',
    );
    expect((await record())['check_in_at'], isNull);
    expect(await f.db.query('attendance_events'), isEmpty);
    expect(
      (await employee.attendanceManagement(
        day: DateTime(2026, 10, 16),
        self: true,
      ))['pending'],
      1,
    );
    await manager.reviewAttendanceAdjustment(
      request,
      true,
      note: 'Đối chiếu phân ca và camera',
    );
    expect((await record())['check_in_at'], sqlTime(start));
    expect((await record())['status'], 'adjusted');
    expect(await f.db.query('attendance_events'), isEmpty);
    final detail = await employee.attendanceCaseDetail(assignment);
    expect(
      (detail['adjustments'] as List<RowData>).single['status'],
      'approved',
    );
    expect(
      (detail['audit'] as List<RowData>).any(
        (r) => r['actor_name'] == 'manager',
      ),
      isTrue,
    );
  });
  test('Adjustment preserves original times, rejects stale changes and cannot be self-approved', () async {
    final first = start.add(const Duration(minutes: 10)),
        out = start.add(const Duration(hours: 8));
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(first),
      now: first,
    );
    await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
    final request = await employee.requestAttendanceAdjustment(
      assignment,
      checkIn: start,
      reason: 'Máy chậm, đã có mặt từ đầu ca',
    );
    expect((await record())['check_in_at'], sqlTime(first));
    await expectLater(
      employee.reviewAttendanceAdjustment(request, true, note: 'Tự duyệt'),
      throwsA(isA<AuthException>()),
    );
    await manager.reviewAttendanceAdjustment(
      request,
      true,
      note: 'Có xác nhận ca trưởng',
    );
    expect((await record())['check_in_at'], sqlTime(start));
    expect(
      (await f.db.query(
        'attendance_events',
        where: "event_type='check_in'",
      )).single['occurred_at'],
      sqlTime(first),
    );
    final again = await employee.requestAttendanceAdjustment(
      assignment,
      checkOut: out.add(const Duration(minutes: 5)),
      reason: 'Bổ sung giờ ra',
    );
    await manager.reviewAttendanceAdjustment(
      again,
      false,
      note: 'Không có minh chứng',
    );
    expect((await record())['check_out_at'], sqlTime(out));
    expect(
      (await f.db.query(
        'attendance_adjustment_requests',
        where: 'id=?',
        whereArgs: [again],
      )).single['status'],
      'rejected',
    );
  });
  test('Missing checkout can be supplemented and finalized records reject further edits', () async {
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    var overview = await manager.attendanceManagement(
      day: DateTime(2026, 10, 16),
    );
    expect(
      (overview['rows'] as List<RowData>).single['work_state'],
      'MISSING_CHECK_OUT',
    );
    await expectLater(
      manager.closeAttendanceDay(DateTime(2026, 10, 16)),
      throwsA(isA<AuthException>()),
    );
    final q = await employee.requestAttendanceAdjustment(
      assignment,
      checkOut: start.add(const Duration(hours: 8)),
      reason: 'Quên bấm ra ca',
    );
    await manager.reviewAttendanceAdjustment(q, true, note: 'Đã kiểm tra');
    await manager.closeAttendanceDay(
      DateTime(2026, 10, 16),
      note: 'Đủ dữ liệu',
    );
    expect((await record())['locked_at'], isNotNull);
    await expectLater(
      employee.requestAttendanceAdjustment(
        assignment,
        checkIn: start,
        reason: 'Sửa lại',
      ),
      throwsA(isA<AuthException>()),
    );
  });
  test('Manager is limited to their branch, Admin sees all and may review an exception', () async {
    final branch = await f.db.insert('branches', {
      'code': 'OTHER',
      'name': 'Nhà hàng khác',
    });
    await f.db.update(
      'employees',
      {'branch_id': branch},
      where: 'id=?',
      whereArgs: [employee.session.profile['id']],
    );
    final shift = await admin.createShift(
      branchId: branch,
      start: start.add(const Duration(days: 1)),
      end: start.add(const Duration(days: 1, hours: 8)),
    );
    await admin.assignShift(shift, employee.session.profile['id'] as int);
    assignment =
        (await f.db.query(
              'shift_assignments',
              where: 'shift_id=?',
              whereArgs: [shift],
            )).single['id']
            as int;
    final at = start.add(const Duration(days: 1));
    final id = await employee.submitAttendance(
      assignment,
      'check_in',
      sample(at),
      now: at,
    ); // No GPS/Wi-Fi config at this branch.
    expect(
      (await manager.attendanceSubmissions()).any((r) => r['id'] == id),
      isFalse,
    );
    await expectLater(
      manager.reviewAttendance(id, true, note: 'Sai chi nhánh'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      manager.attendanceCaseDetail(assignment),
      throwsA(isA<AuthException>()),
    );
    expect(
      (await admin.attendanceSubmissions()).any((r) => r['id'] == id),
      isTrue,
    );
    await admin.reviewAttendance(
      id,
      true,
      note: 'Đã đối chiếu tại nhà hàng khác',
    );
    expect((await record())['check_in_at'], sqlTime(at));
  });
}
