import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/employee_attendance_history_screen.dart';
import 'package:quanlinhansunhahang/widgets/attendance_outcome.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/shift_timeline.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('attendanceOutcome', () {
    test('success is a tick, failures are crosses, pending and future are separate', () {
      expect(
        attendanceOutcome(ShiftPhase.completed),
        AttendanceOutcome.present,
      );
      for (final p in [
        ShiftPhase.absent,
        ShiftPhase.missingCheckOut,
        ShiftPhase.voided,
      ]) {
        expect(attendanceOutcome(p), AttendanceOutcome.absent, reason: '$p');
      }
      expect(
        attendanceOutcome(ShiftPhase.pendingReview),
        AttendanceOutcome.pending,
      );
      expect(attendanceOutcome(ShiftPhase.notYet), AttendanceOutcome.future);
      expect(attendanceOutcome(ShiftPhase.working), AttendanceOutcome.future);
      expect(outcomeIcon(AttendanceOutcome.present), Icons.check_rounded);
      expect(outcomeIcon(AttendanceOutcome.absent), Icons.close_rounded);
    });
  });

  // Tháng 3/2026, mọi ca đã kết thúc so với "bây giờ" là 20/03 nên kết quả không phụ thuộc giờ chạy.
  final month = DateTime(2026, 3);
  final now = DateTime(2026, 3, 20, 12);
  DateTime at(int day, [int hour = 8]) => DateTime(2026, 3, day, hour);
  String sql(DateTime local) {
    final u = local.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:00';
  }

  late DatabaseFixture f;
  late WorkforceRepository employee, manager;
  late int employeeId;
  final ids = <String, int>{};

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  Future<int> assigned(DateTime start) async {
    final shift = await manager.createShift(
      branchId: employee.session.profile['branch_id'] as int,
      start: start.toUtc(),
      end: start.add(const Duration(hours: 4)).toUtc(),
    );
    await manager.assignShift(shift, employeeId);
    return (await f.db.query(
          'shift_assignments',
          where: 'shift_id=?',
          whereArgs: [shift],
        )).single['id']
        as int;
  }

  AttendanceEvidence wrongWifi(DateTime at) => AttendanceEvidence(
    deviceIdentifier: 'real-phone',
    platform: 'android',
    collectedAt: at.toUtc(),
    latitude: 10.77,
    longitude: 106.69,
    accuracy: 5,
    ssid: 'Other Wifi',
    bssid: '00:00:00:00:00:00',
  );

  Future<void> seed() async {
    employeeId = employee.session.profile['id'] as int;
    // 03/03: đã vào và ra ca => thành công (✓).
    ids['ok'] = await assigned(at(3));
    await f.db.insert('attendance_records', {
      'assignment_id': ids['ok'],
      'check_in_at': sql(at(3, 8).add(const Duration(minutes: 3))),
      'check_out_at': sql(at(3, 12)),
      'worked_minutes': 237,
      'arrival_status': 'ON_TIME',
      'attendance_state': 'COMPLETED',
      'status': 'present',
    });
    // 05/03: không điểm danh => ✗ "Không điểm danh".
    ids['absent'] = await assigned(at(5));
    // 07/03: chỉ có giờ vào => ✗ thiếu giờ ra.
    ids['noout'] = await assigned(at(7));
    await f.db.insert('attendance_records', {
      'assignment_id': ids['noout'],
      'check_in_at': sql(at(7, 8)),
      'arrival_status': 'ON_TIME',
      'attendance_state': 'IN_PROGRESS',
      'status': 'present',
    });
    // 09/03: gửi điểm danh nhưng chưa duyệt => chờ duyệt.
    ids['pending'] = await assigned(at(9));
    await employee.submitAttendance(
      ids['pending']!,
      'check_in',
      wrongWifi(at(9)),
      now: at(9),
    );
    // 11/03: gửi điểm danh rồi bị từ chối => ✗ "Điểm danh bị từ chối".
    ids['rejected'] = await assigned(at(11));
    final event = await employee.submitAttendance(
      ids['rejected']!,
      'check_in',
      wrongWifi(at(11)),
      now: at(11),
    );
    await manager.reviewAttendance(event, false, note: 'Sai Wi-Fi');
    // 25/03: chưa tới => "Sắp tới".
    ids['future'] = await assigned(at(25));
  }

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
  });
  tearDown(() => f.dispose());

  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder iconIn(String key, IconData icon) =>
      find.descendant(of: find.byKey(Key(key)), matching: find.byIcon(icon));

  Future<void> open(WidgetTester tester, WorkforceRepository r) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeAttendanceHistoryScreen(
          repository: r,
          initialMonth: month,
          now: now,
        ),
      ),
    );
  }

  testWidgets(
    'Employee history: tick for successful past shifts, cross for missed or failed ones',
    (tester) async {
      await tester.runAsync(seed);
      await open(tester, employee);
      await settle(tester, find.byKey(Key('history-row-${ids['ok']}')));

      expect(find.text('Lịch sử điểm danh'), findsOneWidget);
      expect(find.text('Tháng 3/2026'), findsOneWidget);
      // Thanh tổng hợp như ảnh mẫu: Có mặt / Vắng / (Chờ duyệt) / Sắp tới.
      String count(String key) =>
          (tester.widget<Column>(find.byKey(Key(key))).children.first
                      as Container)
                  .child
              is Text
          ? ((tester.widget<Column>(find.byKey(Key(key))).children.first
                            as Container)
                        .child
                    as Text)
                .data!
          : '';
      expect(count('history-count-present'), '1');
      expect(count('history-count-absent'), '3');
      expect(count('history-count-pending'), '1');
      expect(count('history-count-future'), '1');

      // ✓ cho ca thành công.
      expect(
        iconIn('history-icon-${ids['ok']}', Icons.check_rounded),
        findsOneWidget,
      );
      // ✗ cho ca không điểm danh, thiếu giờ ra và điểm danh bị từ chối.
      for (final k in ['absent', 'noout', 'rejected']) {
        expect(
          iconIn('history-icon-${ids[k]}', Icons.close_rounded),
          findsOneWidget,
          reason: k,
        );
      }
      expect(
        iconIn('history-icon-${ids['pending']}', Icons.hourglass_top_rounded),
        findsOneWidget,
      );
      expect(
        iconIn('history-icon-${ids['future']}', Icons.schedule_rounded),
        findsOneWidget,
      );
      // Lý do hiện ngay dưới mỗi ca.
      String note(String k) =>
          tester.widget<Text>(find.byKey(Key('history-note-${ids[k]}'))).data!;
      expect(note('ok'), 'Vào 08:03 • Ra 12:00');
      expect(note('absent'), 'Không điểm danh');
      expect(note('noout'), 'Có giờ vào 08:00 nhưng thiếu giờ ra');
      expect(note('rejected'), 'Điểm danh bị từ chối');
      expect(note('pending'), 'Đang chờ quản lý duyệt');
      expect(note('future'), 'Chưa tới giờ điểm danh');
      // Nội dung thẻ theo form: ngày, ca (giờ), chi nhánh.
      expect(find.text('Ngày: 03/03/2026'), findsOneWidget);
      expect(find.text('Ca: Ca sáng (08:00–12:00)'), findsWidgets);
      // Các ca xếp theo ngày từ bé đến lớn.
      final tops = [
        for (final k in [
          'ok',
          'absent',
          'noout',
          'pending',
          'rejected',
          'future',
        ])
          tester.getTopLeft(find.byKey(Key('history-row-${ids[k]}'))).dy,
      ];
      expect([...tops]..sort(), tops);
    },
  );

  testWidgets('Month arrows switch the month and the counters follow', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await open(tester, employee);
    await settle(tester, find.byKey(Key('history-row-${ids['ok']}')));
    await tester.tap(find.byKey(const Key('history-next-month')));
    await tester.pump();
    expect(find.text('Tháng 4/2026'), findsOneWidget);
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
    expect(find.byKey(Key('history-row-${ids['ok']}')), findsNothing);
    await tester.tap(find.byKey(const Key('history-prev-month')));
    await tester.tap(find.byKey(const Key('history-prev-month')));
    await tester.pump();
    expect(find.text('Tháng 2/2026'), findsOneWidget);
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
  });

  testWidgets('Manager picks an employee and sees the same history', (
    tester,
  ) async {
    await tester.runAsync(seed);
    await open(tester, manager);
    await settle(tester, find.byKey(const Key('history-employee')));
    await tester.tap(find.byKey(const Key('history-employee')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.textContaining('DEMO_EMPLOYEE').last);
    await tester.pump();
    await settle(tester, find.byKey(Key('history-row-${ids['ok']}')));
    expect(
      iconIn('history-icon-${ids['ok']}', Icons.check_rounded),
      findsOneWidget,
    );
    expect(
      iconIn('history-icon-${ids['absent']}', Icons.close_rounded),
      findsOneWidget,
    );
    // Chờ ô tải xong trước khi kết thúc để DB không bị đóng giữa chừng.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  });
}
