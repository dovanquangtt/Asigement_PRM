import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager, employee;
  final start = DateTime.utc(2026, 10, 16, 1);
  final end = DateTime.utc(2026, 10, 16, 9);
  Future<WorkforceRepository> repo(String name, String pass) async =>
      WorkforceRepository(
        await f.auth.signIn(name, pass),
        openDatabase: () async => f.db,
      );
  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    admin = await repo('admin', 'Admin@12345');
    manager = await repo('manager', 'Manager@12345');
    employee = await repo('employee', 'Employee@12345');
  });
  tearDown(() async => f.dispose());
  Future<int> assigned({DateTime? at, int count = 1}) async {
    final s = at ?? start;
    final id = await manager.createShift(
      branchId: employee.session.profile['branch_id'] as int,
      start: s,
      end: s.add(const Duration(hours: 8)),
      requiredStaff: count,
    );
    await manager.assignShift(id, employee.session.profile['id'] as int);
    return (await f.db.query(
          'shift_assignments',
          where: 'shift_id=?',
          whereArgs: [id],
        )).single['id']
        as int;
  }

  AttendanceEvidence evidence(
    DateTime at, {
    String device = 'test_device',
    String bssid = 'aa:bb:cc:dd:ee:ff',
    bool mock = false,
  }) => AttendanceEvidence(
    deviceIdentifier: device,
    platform: 'android',
    collectedAt: at,
    latitude: 10.77,
    longitude: 106.69,
    accuracy: 5,
    ssid: 'Moc',
    bssid: bssid,
    mocked: mock,
  );
  Future<void> ready() async {
    await manager.configureBranch(
      employee.session.profile['branch_id'] as int,
      latitude: 10.77,
      longitude: 106.69,
      radius: 100,
      ssid: 'Moc',
      bssid: 'aa:bb:cc:dd:ee:ff',
    );
    await employee.registerDevice(evidence(start));
    final d = (await f.db.query('employee_devices')).single;
    await manager.approveDevice(d['id'] as int);
  }

  test(
    'M04 assign enforces permission, capacity, overlaps and reads real roster',
    () async {
      final a = await assigned();
      final shift =
          (await f.db.query(
                'shift_assignments',
                where: 'id=?',
                whereArgs: [a],
              )).single['shift_id']
              as int;
      expect((await manager.shiftDetail(shift))['roster'], hasLength(1));
      await expectLater(
        employee.createShift(branchId: 1, start: start, end: end),
        throwsA(isA<AuthException>()),
      );
      final other = await manager.createShift(
        branchId: 1,
        start: start,
        end: end,
      );
      await expectLater(
        manager.assignShift(other, employee.session.profile['id'] as int),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        manager.assignShift(shift, manager.session.profile['id'] as int),
        throwsA(isA<AuthException>()),
      );
      expect(await f.db.query('shift_assignments'), hasLength(1));
    },
  );
  test('M01 rejected checks persist; accepted check-in/out persist work and overtime without duplicates', () async {
    final a = await assigned();
    await ready();
    final rejected = await employee.recordAttendance(
      a,
      'check_in',
      evidence(start, bssid: '00:00:00:00:00:00'),
      now: start,
    );
    expect(rejected['accepted'], isFalse);
    expect(await f.db.query('attendance_records'), isEmpty);
    final mocked = await employee.recordAttendance(
      a,
      'check_in',
      evidence(start, mock: true),
      now: start,
    );
    expect(mocked['accepted'], isFalse);
    expect(
      (await employee.recordAttendance(
        a,
        'check_in',
        evidence(start),
        now: start,
      ))['accepted'],
      isTrue,
    );
    await expectLater(
      employee.recordAttendance(a, 'check_in', evidence(start), now: start),
      throwsA(isA<AuthException>()),
    );
    final out = end.add(const Duration(hours: 1));
    expect(
      (await employee.recordAttendance(
        a,
        'check_out',
        evidence(out),
        now: out,
      ))['accepted'],
      isTrue,
    );
    final record = (await f.db.query('attendance_records')).single;
    expect(record['worked_minutes'], 540);
    expect(record['overtime_minutes'], 60);
    expect(await f.db.query('attendance_events'), hasLength(4));
    expect(await employee.attendanceHistory(), hasLength(4));
  });
  test('M01 device approval, ownership, expiry and check-out sequence are enforced', () async {
    final a = await assigned();
    await expectLater(
      employee.recordAttendance(a, 'check_out', evidence(start), now: start),
      throwsA(isA<AuthException>()),
    );
    await employee.registerDevice(evidence(start));
    expect(
      (await employee.inspectAttendance(
        a,
        evidence(start),
        now: start,
      ))['device_status'],
      'pending',
    );
    await expectLater(
      manager.registerDevice(evidence(start)),
      throwsA(isA<AuthException>()),
    );
    final rejected = await employee.recordAttendance(
      a,
      'check_in',
      evidence(start),
      now: start,
    );
    expect(rejected['accepted'], isFalse);
    await ready();
    expect(
      (await employee.recordAttendance(
        a,
        'check_in',
        evidence(start.subtract(const Duration(minutes: 3))),
        now: start,
      ))['accepted'],
      isFalse,
    );
    await expectLater(
      manager.recordAttendance(a, 'check_in', evidence(start), now: start),
      throwsA(isA<AuthException>()),
    );
  });
  test('M01 preview is read-only and final confirmation rechecks revoked device and changed Wi-Fi', () async {
    final assignment = await assigned();
    await ready();
    final preview = await employee.inspectAttendance(
      assignment,
      evidence(start),
      now: start,
    );
    expect(preview['accepted'], isTrue);
    expect(preview['device_ok'], isTrue);
    expect(preview['gps_ok'], isTrue);
    expect(preview['wifi_ok'], isTrue);
    expect(preview['distance_m'], closeTo(0, .01));
    expect(await f.db.query('attendance_events'), isEmpty);
    expect(await f.db.query('attendance_records'), isEmpty);
    final device = (await f.db.query('employee_devices')).single;
    await manager.approveDevice(device['id'] as int, revoke: true);
    final rejected = await employee.recordAttendance(
      assignment,
      'check_in',
      evidence(start),
      now: start,
    );
    expect(rejected['accepted'], isFalse);
    await manager.approveDevice(device['id'] as int);
    expect(
      (await employee.recordAttendance(
        assignment,
        'check_in',
        evidence(start, bssid: '00:00:00:00:00:00'),
        now: start,
      ))['accepted'],
      isFalse,
    );
    expect(await f.db.query('attendance_records'), isEmpty);
    expect(await f.db.query('attendance_events'), hasLength(2));
  });

  test('M01 preview rejects invalid coordinates, poor accuracy, stale data and another employee', () async {
    final assignment = await assigned();
    await ready();
    for (final sample in [
      AttendanceEvidence(
        deviceIdentifier: 'test_device',
        platform: 'android',
        collectedAt: start,
        latitude: 999,
        longitude: 106.69,
        accuracy: 5,
        ssid: 'Moc',
        bssid: 'aa:bb:cc:dd:ee:ff',
      ),
      AttendanceEvidence(
        deviceIdentifier: 'test_device',
        platform: 'android',
        collectedAt: start,
        latitude: 10.77,
        longitude: 106.69,
        accuracy: 150,
        ssid: 'Moc',
        bssid: 'aa:bb:cc:dd:ee:ff',
      ),
      evidence(start, mock: true),
      evidence(start.subtract(const Duration(minutes: 3))),
    ]) {
      expect(
        (await employee.inspectAttendance(
          assignment,
          sample,
          now: start,
        ))['accepted'],
        isFalse,
      );
    }
    await expectLater(
      manager.inspectAttendance(assignment, evidence(start), now: start),
      throwsA(isA<AuthException>()),
    );
    expect(await f.db.query('attendance_events'), isEmpty);
  });
  test(
    'M02 six payroll checks, item totals, own data, approval lock and rollback',
    () async {
      final a = await assigned();
      await ready();
      await employee.recordAttendance(
        a,
        'check_in',
        evidence(start),
        now: start,
      );
      final out = end.add(const Duration(hours: 1));
      await employee.recordAttendance(a, 'check_out', evidence(out), now: out);
      for (final e in await manager.employees()) {
        await manager.saveContract(
          e['id'] as int,
          'CT_${e['id']}',
          12480000,
          12480,
          DateTime.utc(2026, 10, 1),
        );
      }
      final period = await manager.createPeriod(
        'OCT_2026',
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 31),
        1.5,
      );
      final calculated = await employee.calculatePay(period);
      final own = (await employee.payslips()).single;
      expect(own['net_pay_vnd'], 570000);
      expect(calculated['payslip_id'], own['id']);
      var detail = await employee.payslipDetail(own['id'] as int);
      expect(detail['checks'], hasLength(6));
      expect(detail['checks_current'], isTrue);
      expect(detail['period_code'], 'OCT_2026');
      expect(detail['starts_on'], '2026-10-01');
      expect(detail['gross_pay_vnd'], 570000);
      expect(detail['deductions_vnd'], 0);
      expect(
        (detail['checks'] as List<RowData>)
            .map((check) => check['step_number'])
            .toList(),
        [1, 2, 3, 4, 5, 6],
      );
      await expectLater(
        employee.calculatePay(
          period,
          employeeId: manager.session.profile['id'] as int,
        ),
        throwsA(isA<AuthException>()),
      );
      await manager.addPayItem(
        own['id'] as int,
        'BONUS',
        'Thưởng',
        'bonus',
        10000,
      );
      detail = await employee.payslipDetail(own['id'] as int);
      expect(detail['checks'], isEmpty);
      expect(detail['checks_current'], isFalse);
      expect(detail['items'], hasLength(1));
      expect(detail['gross_pay_vnd'], 580000);
      expect(detail['net_pay_vnd'], 580000);
      await expectLater(
        manager.approvePayroll(period),
        throwsA(isA<AuthException>()),
      );
      await manager.calculatePay(period);
      expect(await f.db.query('payroll_calculation_steps'), hasLength(6));
      expect((await employee.payslips()).single['net_pay_vnd'], 580000);
      final otherPayslips = await f.db.query(
        'payslips',
        where: 'period_id=? AND employee_id<>?',
        whereArgs: [period, employee.session.profile['id']],
      );
      expect(otherPayslips, isNotEmpty);
      await expectLater(
        employee.payslipDetail(otherPayslips.first['id'] as int),
        throwsA(isA<AuthException>()),
      );
      await f.db.update('attendance_records', {'late_minutes': 1});
      detail = await employee.payslipDetail(own['id'] as int);
      expect(detail['checks'], hasLength(6));
      expect(detail['checks_current'], isFalse);
      await expectLater(
        manager.approvePayroll(period),
        throwsA(isA<AuthException>()),
      );
      await manager.calculatePay(period);
      detail = await employee.payslipDetail(own['id'] as int);
      expect(detail['checks'], hasLength(6));
      expect(detail['checks_current'], isTrue);
      await manager.approvePayroll(period);
      await expectLater(
        employee.calculatePay(period),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        manager.addPayItem(own['id'] as int, 'EDIT', 'Sai', 'bonus', 100),
        throwsA(isA<AuthException>()),
      );
    },
  );
  test('M05 swaps require counterpart and manager, update both assignments atomically', () async {
    final future = DateTime.now().toUtc().add(const Duration(days: 3));
    final a = await assigned(at: future);
    final shift = await manager.createShift(
      branchId: 1,
      start: future.add(const Duration(days: 1)),
      end: future.add(const Duration(days: 1, hours: 8)),
    );
    await manager.assignShift(shift, manager.session.profile['id'] as int);
    final b =
        (await f.db.query(
              'shift_assignments',
              where: 'shift_id=?',
              whereArgs: [shift],
            )).single['id']
            as int;
    await employee.requestSwap(a, b, 'Đổi lịch cá nhân');
    final request =
        (await f.db.query('shift_swap_requests')).single['id'] as int;
    await expectLater(
      admin.respondSwap(request, true, review: true),
      throwsA(isA<AuthException>()),
    );
    await manager.respondSwap(request, true);
    await expectLater(
      manager.respondSwap(request, true, review: true),
      throwsA(isA<AuthException>()),
    );
    await admin.respondSwap(request, true, review: true);
    expect(
      (await f.db.query(
        'shift_assignments',
        where: 'id=?',
        whereArgs: [a],
      )).single['employee_id'],
      manager.session.profile['id'],
    );
    expect(
      (await f.db.query(
        'shift_assignments',
        where: 'id=?',
        whereArgs: [b],
      )).single['employee_id'],
      employee.session.profile['id'],
    );
    expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    'M06 stars persist in view, employee cannot award or read others',
    () async {
      await manager.awardStars(
        employee.session.profile['id'] as int,
        2,
        'Làm tốt',
      );
      expect((await employee.stars()).single['total_stars'], 2);
      await expectLater(
        employee.awardStars(
          manager.session.profile['id'] as int,
          1,
          'Không có quyền',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(await employee.stars(), hasLength(1));
    },
  );
  test('M07 needs checkout/photo, persists closure/photos and closes only after review', () async {
    final a = await assigned();
    final file = File('${f.directory.path}/photo.jpg');
    await file.writeAsBytes([255, 216, 255, 217]);
    await expectLater(
      employee.closeAssignment(a, 'Bàn giao', file.path),
      throwsA(isA<AuthException>()),
    );
    await ready();
    await employee.recordAttendance(a, 'check_in', evidence(start), now: start);
    await employee.recordAttendance(a, 'check_out', evidence(end), now: end);
    await employee.closeAssignment(a, 'Bàn giao hoàn tất', file.path);
    final closure = (await employee.closures()).single;
    expect(closure['photos'], hasLength(1));
    await expectLater(
      employee.reviewClosure(closure['id'] as int, true),
      throwsA(isA<AuthException>()),
    );
    await manager.reviewClosure(closure['id'] as int, false);
    await employee.closeAssignment(a, 'Đã bổ sung ghi chú', file.path);
    expect(await f.db.query('shift_closures'), hasLength(1));
    await manager.reviewClosure(closure['id'] as int, true);
    expect(
      (await f.db.query(
        'shift_assignments',
        where: 'id=?',
        whereArgs: [a],
      )).single['status'],
      'completed',
    );
    expect((await f.db.query('shifts')).single['status'], 'closed');
    expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
