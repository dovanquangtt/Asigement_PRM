import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/attendance_management_screen.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/shift_timeline.dart';

import 'database_fixture.dart';

/// Quản lý xem tình trạng điểm danh của nhân viên theo ngày: ca hoàn thành, lượt điểm danh đang
/// chờ duyệt, ca vắng và người nghỉ phép đều phải hiện rõ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Một ngày cố định trong quá khứ: mọi ca đã kết thúc nên kết quả không phụ thuộc giờ chạy test.
  final day = DateTime(2026, 3, 11);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);
  String sql(DateTime local) {
    final u = local.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:00';
  }

  late DatabaseFixture f;
  late WorkforceRepository employee, manager;
  late int employeeId;

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

  Future<void> seed() async {
    employeeId = employee.session.profile['id'] as int;
    // Ca 1: đã vào và ra ca => Ca đã hoàn thành.
    final done = await assigned(at(8));
    await f.db.insert('attendance_records', {
      'assignment_id': done,
      'check_in_at': sql(at(8, 2)),
      'check_out_at': sql(at(12, 1)),
      'worked_minutes': 239,
      'arrival_status': 'ON_TIME',
      'attendance_state': 'COMPLETED',
      'status': 'present',
    });
    // Ca 2: nhân viên gửi điểm danh nhưng Wi-Fi sai => chờ duyệt, chưa ghi công.
    final pending = await assigned(at(13));
    await employee.submitAttendance(
      pending,
      'check_in',
      AttendanceEvidence(
        deviceIdentifier: 'real-phone',
        platform: 'android',
        collectedAt: at(13, 1).toUtc(),
        latitude: 10.77,
        longitude: 106.69,
        accuracy: 5,
        ssid: 'Other Wifi',
        bssid: '00:00:00:00:00:00',
      ),
      now: at(13, 1),
    );
    // Ca 3: không điểm danh, ca đã kết thúc => vắng ("Nghỉ").
    await assigned(at(18));
    // Quản lý có đợt nghỉ phép đã duyệt trong ngày này.
    final annual = (await f.db.query(
      'leave_types',
      where: "code='ANNUAL'",
    )).single['id'];
    await f.db.insert('leave_requests', {
      'employee_id': manager.session.profile['id'],
      'leave_type_id': annual,
      'starts_at': sql(at(0)),
      'ends_at': sql(at(23, 59)),
      'requested_minutes': 480,
      'reason': 'Việc gia đình',
      'status': 'approved',
      'reviewed_by': (await f.db.query(
        'users',
        where: "username='admin'",
      )).single['id'],
      'reviewed_at': sql(at(0)),
    });
  }

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
  });
  tearDown(() => f.dispose());

  test('Manager sees completed, pending-review and absent shifts plus approved leave', () async {
    await seed();
    final now = at(23);
    final view = await manager.attendanceManagement(day: day, now: now);
    final rows = (view['rows'] as List<RowData>)
        .where((r) => r['employee_id'] == employeeId)
        .toList();
    expect(rows.map((r) => shiftPhase(r, now.toUtc())), [
      ShiftPhase.completed,
      ShiftPhase.pendingReview,
      ShiftPhase.absent,
    ]);
    // Lượt chờ duyệt không được tính là đã ghi công nhưng phải hiện ra.
    final pending = rows[1];
    expect(pending['check_in_at'], isNull);
    expect(pending['pending_exceptions'], 1);
    expect(view['checked_in'], 1);
    expect(view['pending'], greaterThanOrEqualTo(1));
    final leaves = view['leaves'] as List<RowData>;
    expect(leaves, hasLength(1));
    expect(leaves.single['full_name'], manager.session.profile['full_name']);
    expect(view['on_leave'], 1);
  });

  test('Leave that ended at midnight of the previous day is not shown, a later day is not either', () async {
    await seed();
    final next = await manager.attendanceManagement(
      day: day.add(const Duration(days: 1)),
      now: at(23),
    );
    expect(next['leaves'], isEmpty);
    expect(next['rows'], isEmpty);
  });

  test(
    'Only reviewers may open the branch view; employee sees own shifts only',
    () async {
      await seed();
      final own = await employee.attendanceManagement(
        day: day,
        self: true,
        now: at(23),
      );
      expect(
        (own['rows'] as List).every(
          (r) => (r as RowData)['employee_id'] == employeeId,
        ),
        isTrue,
      );
      await expectLater(
        employee.attendanceManagement(day: day, now: at(23)),
        throwsA(isA<AuthException>()),
      );
    },
  );

  testWidgets('Management screen highlights each status and filters leave', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(seed);
    Future<void> settle(Finder until) async {
      for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceManagementScreen(repository: manager, initialDay: day),
      ),
    );
    await settle(find.text('Ca đã hoàn thành'));

    expect(find.text('11/3/2026'), findsOneWidget);
    // Ba ca của nhân viên, mỗi ca một nhãn trạng thái đặc màu.
    expect(find.text('Ca đã hoàn thành'), findsOneWidget);
    expect(find.text('Chờ duyệt điểm danh'), findsWidgets);
    expect(find.text('Không điểm danh'), findsOneWidget);
    expect(
      find.text('Bấm để xem bằng chứng và duyệt hoặc từ chối.'),
      findsOneWidget,
    );
    // Ca vắng và ngày nghỉ phép đều ghi "Nghỉ".
    expect(find.text('Nghỉ'), findsNWidgets(2));
    expect(find.byKey(const Key('attendance-leave-status-1')), findsOneWidget);
    expect(
      find.textContaining('Giờ vào: 08:02   Giờ ra: 12:01'),
      findsOneWidget,
    );
    // Màu nhãn khớp bộ nhãn dùng chung với lịch của nhân viên.
    final statusKeys = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          '${(w.key as ValueKey).value}'.startsWith('attendance-status-'),
    );
    expect(statusKeys, findsNWidgets(3));
    final colors = [
      for (final e in statusKeys.evaluate())
        ((e.widget as Container).decoration as BoxDecoration).color,
    ];
    expect(colors, contains(phaseStyle(ShiftPhase.completed).color));
    expect(colors, contains(phaseStyle(ShiftPhase.pendingReview).color));
    expect(colors, contains(phaseStyle(ShiftPhase.absent).color));

    // Bộ lọc "Nghỉ phép" chỉ còn thẻ nghỉ phép.
    await tester.tap(find.text('Nghỉ phép').last);
    await tester.pump();
    expect(find.text('Ca đã hoàn thành'), findsNothing);
    expect(find.byKey(const Key('attendance-leave-status-1')), findsOneWidget);

    // Nút chuyển ngày.
    await tester.tap(find.byKey(const Key('attendance-next-day')));
    await settle(find.text('12/3/2026'));
    expect(find.text('12/3/2026'), findsOneWidget);
    for (
      var i = 0;
      i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
