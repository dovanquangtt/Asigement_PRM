import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/schedule_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/shift_timeline.dart';

import 'database_fixture.dart';

/// Quản lý phân ca => nhân viên nhận thông báo, thấy ca xếp theo ngày tăng dần và ca mới được
/// đánh dấu nổi bật (cả khi đang mở sẵn màn "Lịch ca").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager;
  late int branch, employeeId;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  Future<int> shift(DateTime localStart) async => manager.createShift(
    branchId: branch,
    start: localStart.toUtc(),
    end: localStart.add(const Duration(hours: 4)).toUtc(),
  );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    branch = employee.session.profile['branch_id'] as int;
    employeeId = employee.session.profile['id'] as int;
  });
  tearDown(() => f.dispose());

  DateTime nextMonday8() {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day - (t.weekday - 1) + 7, 8);
  }

  test('Assigning a shift notifies the employee (unread, linked to the shift) and not the manager', () async {
    final id = await shift(nextMonday8());
    await manager.assignShift(id, employeeId);

    final mine = (await employee.notifications())
        .where((n) => n['title'] == 'Bạn có ca làm mới')
        .toList();
    expect(mine, hasLength(1));
    expect(mine.single['read_at'], isNull);
    expect(mine.single['related_entity'], 'shifts');
    expect(mine.single['related_id'], id);
    expect(mine.single['body'], contains('Hãy chấp nhận hoặc từ chối'));
    expect(
      (await manager.notifications()).any(
        (n) => n['title'] == 'Bạn có ca làm mới',
      ),
      isFalse,
    );
    // Gỡ rồi phân lại: nhân viên được báo lần nữa.
    await manager.unassignShift(id, employeeId);
    await manager.assignShift(id, employeeId);
    expect(
      (await employee.notifications()).where(
        (n) => n['title'] == 'Bạn có ca làm mới',
      ),
      hasLength(2),
    );
  });

  test('Employee shifts are listed by date from earliest to latest', () async {
    final base = nextMonday8();
    // Tạo và phân theo thứ tự lộn xộn.
    for (final days in [4, 0, 2, 1, 3]) {
      final id = await shift(base.add(Duration(days: days)));
      await manager.assignShift(id, employeeId);
    }
    final starts = [
      for (final r in await employee.shifts()) '${r['starts_at']}',
    ];
    expect(starts, hasLength(5));
    expect([...starts]..sort(), starts);
    final schedule = await employee.employeeSchedule();
    expect(schedule.every((r) => r['assigned_at'] != null), isTrue);
    expect(
      schedule.every((r) => shiftIsNew(r, DateTime.now().toUtc())),
      isTrue,
      reason: 'ca vừa phân (và chưa trả lời) là ca mới',
    );
  });

  testWidgets(
    'An open schedule screen reloads when a new shift is assigned and highlights it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final token = ValueNotifier<int>(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: token,
              builder: (_, t, _) =>
                  ScheduleScreen(repository: employee, reloadToken: t),
            ),
          ),
        ),
      );
      Future<void> settle(Finder until) async {
        for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await settle(find.byKey(const Key('timeline-next')));
      expect(find.byKey(const Key('timeline-empty')), findsOneWidget);
      expect(find.byKey(const Key('new-shifts-banner')), findsNothing);

      // Quản lý phân ca vào thứ Hai tuần sau (tuần mà màn hình đang không hiển thị).
      final assignmentId = await tester.runAsync(() async {
        final id = await shift(nextMonday8());
        await manager.assignShift(id, employeeId);
        return (await f.db.query(
              'shift_assignments',
              where: 'shift_id=?',
              whereArgs: [id],
            )).single['id']
            as int;
      });
      // Chưa có tín hiệu tải lại thì màn hình chưa đổi; sau khi có thông báo (token đổi) thì tự cập nhật.
      expect(find.byKey(const Key('new-shifts-banner')), findsNothing);
      token.value++;
      await tester.pump();
      await settle(find.byKey(const Key('new-shifts-banner')));
      expect(find.textContaining('Bạn có 1 ca mới được phân'), findsOneWidget);
      // Vẫn đang ở tuần này nên chưa thấy thẻ ca; bấm "Xem" để nhảy tới ca đó.
      expect(find.byKey(Key('timeline-shift-$assignmentId')), findsNothing);
      await tester.tap(find.byKey(const Key('new-shifts-go')));
      await tester.pump();
      expect(find.byKey(Key('timeline-shift-$assignmentId')), findsOneWidget);
      expect(find.byKey(Key('timeline-new-$assignmentId')), findsOneWidget);
      expect(find.text('MỚI'), findsOneWidget);
      expect(find.text('Chưa vào ca'), findsOneWidget);
      // Có sẵn nút trả lời ca mới.
      expect(find.text('Chấp nhận'), findsOneWidget);
    },
  );
}
