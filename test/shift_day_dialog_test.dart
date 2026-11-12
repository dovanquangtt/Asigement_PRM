import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/schedule_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/shift_day_dialog.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Day dialog shows every shift card with its details and closes', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShiftDayDialog(
              context,
              day: DateTime(2026, 11, 11),
              items: [
                ShiftDayItem(
                  slot: 'Ca 1',
                  color: Colors.orange,
                  start: DateTime(2026, 11, 11, 12, 50),
                  end: DateTime(2026, 11, 11, 15, 10),
                  branch: 'Chi nhánh 1',
                  code: 'Mã ca #3',
                  title: 'Ca trưa',
                  highlighted: true,
                  lines: const [
                    MapEntry('Phản hồi', 'Đã chấp nhận'),
                    MapEntry('Giờ vào', 'Chưa có'),
                  ],
                  chips: [
                    const ShiftChip(
                      'CHƯA ĐIỂM DANH',
                      Colors.grey,
                      Colors.white,
                    ),
                    ShiftChip(
                      'Xem chi tiết',
                      Colors.green,
                      Colors.white,
                      onTap: () => opened++,
                    ),
                  ],
                ),
                ShiftDayItem(
                  slot: 'Ca 2',
                  color: Colors.blue,
                  start: DateTime(2026, 11, 11, 15, 20),
                  end: DateTime(2026, 11, 11, 17, 40),
                  branch: 'Chi nhánh 2',
                  code: 'Mã ca #4',
                  title: 'Ca chiều',
                ),
              ],
            ),
            child: const Text('mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('11/11/2026'), findsOneWidget);
    for (final text in [
      'Ca 1',
      '12:50',
      '15:10',
      'Chi nhánh 1',
      'Ca trưa',
      'Phản hồi: Đã chấp nhận',
      'Giờ vào: Chưa có',
      'CHƯA ĐIỂM DANH',
      'Ca 2',
      'Chi nhánh 2',
      'Ca chiều',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    await tester.tap(find.text('Xem chi tiết'));
    expect(opened, 1);
    await tester.tap(find.byKey(const Key('shift-day-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-day-dialog')), findsNothing);
  });

  testWidgets(
    'Employee schedule: info button opens the day table with attendance times',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late DatabaseFixture f;
      late WorkforceRepository employee;
      await tester.runAsync(() async {
        f = await DatabaseFixture.open(keepSampleUsers: true);
        Future<WorkforceRepository> repo(String n, String p) async =>
            WorkforceRepository(
              await f.auth.signIn(n, p),
              openDatabase: () async => f.db,
            );
        final manager = await repo('manager', 'Manager@12345');
        employee = await repo('employee', 'Employee@12345');
        final branch = employee.session.profile['branch_id'] as int;
        // Monday of NEXT week, 08:00 local: always in the future and never on the current week's
        // screen, so the result does not depend on the weekday or hour the test runs at.
        final today = DateTime.now();
        final start = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) + 7,
          8,
        ).toUtc();
        final first = await manager.createShift(
          branchId: branch,
          start: start,
          end: start.add(const Duration(hours: 4)),
          note: 'Chuẩn bị bàn',
        );
        final second = await manager.createShift(
          branchId: branch,
          start: start.add(const Duration(hours: 5)),
          end: start.add(const Duration(hours: 9)),
        );
        final me = employee.session.profile['id'] as int;
        await manager.assignShift(first, me);
        await manager.assignShift(second, me);
        // Pending (not yet approved) punch must not invent a recorded time.
        final row = (await employee.employeeSchedule()).first;
        expect(row.containsKey('check_in_at'), isTrue);
        expect(row['check_in_at'], isNull);
      });
      addTearDown(() => tester.runAsync(() => f.dispose()));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScheduleScreen(repository: employee)),
        ),
      );
      for (
        var i = 0;
        i < 20 && find.byKey(const Key('timeline-next')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      // The current week is empty; the two shifts are on next week's Monday.
      expect(find.byKey(const Key('timeline-empty')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('timeline-next')));
      await tester.tap(find.byKey(const Key('timeline-next')));
      await tester.pumpAndSettle();
      expect(find.text('Chưa vào ca'), findsNWidgets(2));
      expect(find.text('Điểm danh'), findsNWidgets(2));
      expect(find.text('Chấp nhận'), findsNWidgets(2));
      final buttons = find.textContaining('Xem thông tin');
      expect(buttons, findsWidgets);
      await tester.ensureVisible(buttons.first);
      await tester.pumpAndSettle();
      await tester.tap(buttons.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shift-day-dialog')), findsOneWidget);
      final dialog = find.byKey(const Key('shift-day-dialog'));
      expect(
        find.descendant(of: dialog, matching: find.text('Ca 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Ca 2')),
        findsOneWidget,
      );
      // Cùng bộ nhãn trạng thái với bảng lịch (Chưa vào ca), không còn nhãn chữ hoa riêng.
      expect(
        find.descendant(of: dialog, matching: find.text('Chưa vào ca')),
        findsNWidgets(2),
      );
      expect(find.text('Giờ vào: Chưa có'), findsNWidgets(2));
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Ghi chú: Chuẩn bị bàn'),
        ),
        findsOneWidget,
      );
      expect(find.text('Phản hồi: Chờ xác nhận'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    },
  );
}
