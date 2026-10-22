import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/attendance_sensors.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

class _MissingSensors extends AttendanceSensors {
  @override
  Future<AttendanceEvidence> collect({
    bool location = true,
    bool gps = true,
    bool wifi = true,
  }) async {
    if (location) throw const AuthException('Chưa cấp quyền vị trí');
    return AttendanceEvidence(
      deviceIdentifier: 'real-phone',
      platform: 'android',
      collectedAt: DateTime.now().toUtc(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager, admin;
  late int assignment;
  final start = DateTime.utc(2026, 10, 22, 1);
  AttendanceEvidence sample(DateTime at) => AttendanceEvidence(
    deviceIdentifier: 'real-phone',
    platform: 'android',
    collectedAt: at,
    latitude: 10.77,
    longitude: 106.69,
    accuracy: 5,
    ssid: 'Other Wifi',
    bssid: '00:00:00:00:00:00',
  );
  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    Future<WorkforceRepository> repo(String name, String password) async =>
        WorkforceRepository(
          await f.auth.signIn(name, password),
          openDatabase: () async => f.db,
        );
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    admin = await repo('admin', 'Admin@12345');
    final shift = await manager.createShift(
      branchId: employee.session.profile['branch_id'] as int,
      start: start,
      end: start.add(const Duration(hours: 8)),
    );
    await manager.assignShift(shift, employee.session.profile['id'] as int);
    assignment = (await f.db.query('shift_assignments')).single['id'] as int;
  });
  tearDown(() => f.dispose());
  test(
    'Missing GPS and Wi-Fi are preserved as warnings, not a submission blocker',
    () async {
      final collected = await _MissingSensors().collectForReview();
      expect(collected.issues, hasLength(2));
      final id = await employee.submitAttendance(
        assignment,
        'check_in',
        collected.evidence,
        collectionIssues: collected.issues,
        now: start,
      );
      final row = (await f.db.query(
        'attendance_events',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(row['result'], 'pending_review');
      expect(row['latitude'], isNull);
      expect(row['wifi_ssid'], isNull);
      expect(
        row['checks_snapshot'].toString(),
        contains('Chưa cấp quyền vị trí'),
      );
      expect(await f.db.query('attendance_records'), isEmpty);
    },
  );

  test(
    'Review rejects changed assignment and sender keeps access to own history',
    () async {
      final id = await employee.submitAttendance(
        assignment,
        'check_in',
        sample(start),
        now: start,
      );
      await f.db.update(
        'shift_assignments',
        {'employee_id': manager.session.profile['id']},
        where: 'id=?',
        whereArgs: [assignment],
      );
      await expectLater(
        admin.reviewAttendance(id, true, note: 'Đã kiểm tra'),
        throwsA(isA<AuthException>()),
      );
      expect((await employee.attendanceHistory()).single['id'], id);
      expect(
        (await admin.attendanceSubmissions()).single['full_name'],
        employee.session.displayName,
      );
      expect(await f.db.query('attendance_records'), isEmpty);
    },
  );

  test('Admin cannot approve their own submission', () async {
    final shift = await manager.createShift(
      branchId: admin.session.profile['branch_id'] as int,
      start: start,
      end: start.add(const Duration(hours: 8)),
      requiredStaff: 2,
    );
    await manager.assignShift(shift, admin.session.profile['id'] as int);
    final own =
        (await f.db.query(
              'shift_assignments',
              where: 'shift_id=?',
              whereArgs: [shift],
            )).single['id']
            as int;
    final id = await admin.submitAttendance(
      own,
      'check_in',
      sample(start),
      now: start,
    );
    await expectLater(
      admin.reviewAttendance(id, true, note: 'Tự xác nhận'),
      throwsA(isA<AuthException>()),
    );
    expect(await f.db.query('attendance_records'), isEmpty);
  });

  test('Pending submission notifies Admin but does not record work; scoped reviewers can approve with a reason', () async {
    final id = await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    final event = (await f.db.query('attendance_events')).single;
    expect(event['result'], 'pending_review');
    expect(event['actual_device_identifier'], 'real-phone');
    expect(await f.db.query('attendance_records'), isEmpty);
    expect((await admin.notifications()).single['related_id'], id);
    expect((await manager.notifications()).single['related_id'], id);
    await expectLater(
      employee.attendanceSubmissions(),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      admin.reviewAttendance(id, true, note: ''),
      throwsA(isA<AuthException>()),
    );
    await admin.reviewAttendance(
      id,
      true,
      note: 'Đã đối chiếu trực tiếp với ca trưởng',
    );
    final record = (await f.db.query('attendance_records')).single;
    expect(record['check_in_at'], sqlTime(start));
    expect(record['approved_by'], admin.session.userId);
    expect(
      (await employee.attendanceHistory()).single['review_note'],
      contains('đối chiếu'),
    );
    expect(
      (await employee.notifications()).single['title'],
      'Kết quả duyệt điểm danh',
    );
    await expectLater(
      admin.reviewAttendance(id, true, note: 'lặp'),
      throwsA(isA<AuthException>()),
    );
    expect(await f.db.query('attendance_records'), hasLength(1));
  });

  test('Duplicate pending is blocked, rejection preserves evidence and allows resubmission', () async {
    final id = await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    await expectLater(
      employee.submitAttendance(
        assignment,
        'check_in',
        sample(start),
        now: start,
      ),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      admin.reviewAttendance(id, false, note: ''),
      throwsA(isA<AuthException>()),
    );
    await admin.reviewAttendance(id, false, note: 'Không có mặt tại chi nhánh');
    expect(
      (await f.db.query('attendance_events'))
          .single['actual_device_identifier'],
      'real-phone',
    );
    expect(await f.db.query('attendance_records'), isEmpty);
    await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    expect(await f.db.query('attendance_events'), hasLength(2));
  });

  test('Checkout may be submitted while check-in waits but cannot be approved first', () async {
    final inId = await employee.submitAttendance(
      assignment,
      'check_in',
      sample(start),
      now: start,
    );
    final out = start.add(const Duration(hours: 8));
    final outId = await employee.submitAttendance(
      assignment,
      'check_out',
      sample(out),
      now: out,
    );
    await expectLater(
      admin.reviewAttendance(outId, true, note: 'Đã kiểm tra'),
      throwsA(isA<AuthException>()),
    );
    expect(await f.db.query('attendance_records'), isEmpty);
    await admin.reviewAttendance(inId, true, note: 'Đã kiểm tra vào ca');
    await admin.reviewAttendance(outId, true, note: 'Đã kiểm tra ra ca');
    expect(
      (await f.db.query('attendance_records')).single['worked_minutes'],
      480,
    );
    expect(
      (await f.db.query('attendance_events'))
          .every((r) => r['result'] == 'accepted'),
      isTrue,
    );
  });

  test(
    'Chosen device belongs to caller and never replaces actual sender identity',
    () async {
      await employee.registerDevice(sample(start));
      final mine = (await employee.myAttendanceDevices()).single;
      await manager.registerDevice(
        AttendanceEvidence(
          deviceIdentifier: 'manager-phone',
          platform: 'android',
          collectedAt: start,
        ),
      );
      final others = (await manager.myAttendanceDevices()).single;
      await expectLater(
        employee.submitAttendance(
          assignment,
          'check_in',
          sample(start),
          selectedDeviceId: others['id'] as int,
          now: start,
        ),
        throwsA(isA<AuthException>()),
      );
      final different = AttendanceEvidence(
        deviceIdentifier: 'another-real-phone',
        platform: 'android',
        collectedAt: start,
      );
      await employee.submitAttendance(
        assignment,
        'check_in',
        different,
        selectedDeviceId: mine['id'] as int,
        now: start,
      );
      final event = (await f.db.query('attendance_events')).single;
      expect(event['actual_device_identifier'], 'another-real-phone');
      expect(event['selected_device_identifier'], 'real-phone');
      expect(
        event['checks_snapshot'].toString(),
        contains('khác thiết bị thực tế'),
      );
      expect(await f.db.query('attendance_records'), isEmpty);
    },
  );
}
