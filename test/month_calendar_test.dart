import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/month_calendar_screen.dart';
import 'package:quanlinhansunhahang/screens/schedule_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/attendance_outcome.dart';
import 'package:quanlinhansunhahang/widgets/month_calendar.dart';

import 'database_fixture.dart';

String sql(DateTime local) {
  final u = local.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:00';
}

RowData shift(
  int id,
  DateTime start, {
  DateTime? checkIn,
  DateTime? checkOut,
  int pending = 0,
}) => {
  'assignment_id': id,
  'shift_id': id + 100,
  'starts_at': sql(start),
  'ends_at': sql(start.add(const Duration(hours: 4))),
  'branch_name': 'ANH EM QUÁN',
  'shift_status': 'scheduled',
  'assignment_status': 'assigned',
  'response_status': 'accepted',
  'check_in_at': checkIn == null ? null : sql(checkIn),
  'check_out_at': checkOut == null ? null : sql(checkOut),
  'pending_events': pending,
};

RowData leave(int id, DateTime start, DateTime end) => {
  'id': id,
  'status': 'approved',
  'starts_at': sql(start),
  'ends_at': sql(end),
  'reason': 'Việc nhà',
  'leave_type_name': 'Phép năm',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Tháng 11/2026 như ảnh mẫu: ngày 1 là Chủ nhật; "hôm nay" là 11/11 (giữa trưa).
  final now = DateTime(2026, 11, 11, 12);
  final month = DateTime(2026, 11);
  DateTime at(int day, int hour) => DateTime(2026, 11, day, hour);

  // 02/11: ✓, ✗, chờ duyệt (3 chấm) · 04/11: ✓, ✗ · 11/11: ✓ + ✗ · 28/11: sắp tới · 13-14/11: nghỉ phép.
  final shifts = [
    shift(1, at(2, 8), checkIn: at(2, 8), checkOut: at(2, 12)),
    shift(2, at(2, 13)),
    shift(3, at(2, 18), pending: 1),
    shift(4, at(4, 8), checkIn: at(4, 8), checkOut: at(4, 12)),
    shift(5, at(4, 13)),
    shift(6, at(11, 6), checkIn: at(11, 6), checkOut: at(11, 10)),
    shift(7, at(11, 7)),
    shift(8, at(28, 8)),
    shift(
      9,
      DateTime(2026, 10, 30, 8),
      checkIn: DateTime(2026, 10, 30, 8),
      checkOut: DateTime(2026, 10, 30, 12),
    ),
  ];
  final leaves = [leave(5, at(13, 8), at(14, 17))];

  group('calendarMarks', () {
    final marks = calendarMarks(
      shifts: shifts,
      leaves: leaves,
      month: month,
      now: now,
    );
    List<Color> of(int d) => marks[DateTime(2026, 11, d)] ?? const [];

    test(
      'one dot per shift in time order, coloured by the attendance result',
      () {
        expect(of(2), [markPresent, markAbsent, markPending]);
        expect(of(4), [markPresent, markAbsent]);
        expect(of(11), [markPresent, markAbsent]);
        expect(of(28), [markFuture]);
      },
    );
    test('approved leave adds a brown dot on each leave day', () {
      expect(of(13), [markLeave]);
      expect(of(14), [markLeave]);
      expect(of(15), isEmpty);
    });
    test('days without shifts have no dots and other months are ignored', () {
      expect(of(1), isEmpty);
      expect(of(30), isEmpty);
      expect(marks.keys.every((d) => d.month == 11), isTrue);
      expect(marks.containsKey(DateTime(2026, 10, 30)), isFalse);
    });
  });

  group('MonthCalendarGrid', () {
    Future<void> pumpGrid(
      WidgetTester tester, {
      ValueChanged<DateTime>? onTap,
    }) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthCalendarGrid(
              month: month,
              marks: calendarMarks(
                shifts: shifts,
                leaves: leaves,
                month: month,
                now: now,
              ),
              today: now,
              onDayTap: onTap ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('shows every day of the month with Sunday first', (
      tester,
    ) async {
      await pumpGrid(tester);
      for (final w in ['CN', 'Th2', 'Th3', 'Th4', 'Th5', 'Th6', 'Th7']) {
        expect(find.text(w), findsOneWidget);
      }
      for (var d = 1; d <= 30; d++) {
        expect(
          find.byKey(Key('calendar-day-2026-11-$d')),
          findsOneWidget,
          reason: '$d',
        );
      }
      expect(find.byKey(const Key('calendar-day-2026-11-31')), findsNothing);
      double x(int d) =>
          tester.getTopLeft(find.byKey(Key('calendar-day-2026-11-$d'))).dx;
      // 1/11/2026 là Chủ nhật: cột đầu tiên; 2/11 (Th2) ngay sau; 8/11 cùng cột với 1/11.
      expect(x(1) < x(2), isTrue);
      expect(x(1), x(8));
      expect(x(2), x(9));
      double y(int d) =>
          tester.getTopLeft(find.byKey(Key('calendar-day-2026-11-$d'))).dy;
      expect(y(1) < y(8), isTrue);
      expect(y(2), y(3));
    });

    testWidgets('dots follow the marks and today is highlighted', (
      tester,
    ) async {
      await pumpGrid(tester);
      int dots(int d) => find
          .descendant(
            of: find.byKey(Key('calendar-dots-2026-11-$d')),
            matching: find.byType(Container),
          )
          .evaluate()
          .length;
      expect(dots(2), 3);
      expect(dots(4), 2);
      expect(dots(28), 1);
      expect(dots(1), 0);
      Color numberColor(int d) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key('calendar-day-2026-11-$d')),
              matching: find.text('$d'),
            ),
          )
          .style!
          .color!;
      expect(numberColor(11), const Color(0xFFF59E0B));
      expect(numberColor(12), isNot(const Color(0xFFF59E0B)));
    });

    testWidgets('tapping a day reports that day, with or without shifts', (
      tester,
    ) async {
      final tapped = <DateTime>[];
      await pumpGrid(tester, onTap: tapped.add);
      await tester.tap(find.byKey(const Key('calendar-day-2026-11-11')));
      await tester.tap(find.byKey(const Key('calendar-day-2026-11-20')));
      expect(tapped, [DateTime(2026, 11, 11), DateTime(2026, 11, 20)]);
    });
  });

  group('MonthCalendarScreen', () {
    testWidgets('month arrows and the month picker change the month', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MonthCalendarScreen(
            shifts: shifts,
            leaves: leaves,
            now: now,
            onDayTap: (_) {},
          ),
        ),
      );
      expect(find.text('Tháng 11/2026'), findsOneWidget);
      expect(find.text('Đã điểm danh'), findsOneWidget); // chú thích màu
      await tester.tap(find.byKey(const Key('calendar-next')));
      await tester.pump();
      expect(find.text('Tháng 12/2026'), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2026-12-31')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-prev')));
      await tester.tap(find.byKey(const Key('calendar-prev')));
      await tester.pump();
      expect(find.text('Tháng 10/2026'), findsOneWidget);
      // Bấm vào tiêu đề để chọn nhanh tháng/năm.
      await tester.tap(find.byKey(const Key('calendar-title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar-year-next')));
      await tester.pump();
      expect(find.text('2027'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-month-2')));
      await tester.pumpAndSettle();
      expect(find.text('Tháng 2/2027'), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2027-2-28')), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2027-2-29')), findsNothing);
    });
  });

  group('Schedule screen', () {
    late DatabaseFixture f;
    late WorkforceRepository employee, manager;

    Future<WorkforceRepository> repo(String n, String p) async =>
        WorkforceRepository(
          await f.auth.signIn(n, p),
          openDatabase: () async => f.db,
        );

    setUp(() async {
      f = await DatabaseFixture.open(keepSampleUsers: true);
      employee = await repo('employee', 'Employee@12345');
      manager = await repo('manager', 'Manager@12345');
    });
    tearDown(() => f.dispose());

    testWidgets(
      'calendar button opens the month; tapping a day shows that day\'s shift details',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        // Thứ Hai tuần sau, 08:00 giờ địa phương: luôn ở tương lai, không phụ thuộc giờ chạy test.
        final today = DateTime.now();
        final target = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) + 7,
          8,
        );
        await tester.runAsync(() async {
          final id = await manager.createShift(
            branchId: employee.session.profile['branch_id'] as int,
            start: target.toUtc(),
            end: target.add(const Duration(hours: 4)).toUtc(),
            note: 'Chuẩn bị bàn',
          );
          await manager.assignShift(id, employee.session.profile['id'] as int);
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ScheduleScreen(repository: employee)),
          ),
        );
        for (
          var i = 0;
          i < 40 &&
              find.byKey(const Key('open-month-calendar')).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.ensureVisible(
          find.byKey(const Key('open-month-calendar')),
        );
        await tester.tap(find.byKey(const Key('open-month-calendar')));
        await tester.pumpAndSettle();
        expect(find.text('Lịch tháng'), findsOneWidget);
        // Màn hình mở ở tháng của tuần đang xem; sang tháng sau nếu ca nằm ở tháng đó.
        if (target.month != today.month) {
          await tester.tap(find.byKey(const Key('calendar-next')));
          await tester.pump();
        }
        expect(
          find.text('Tháng ${target.month}/${target.year}'),
          findsOneWidget,
        );
        final key = 'calendar-day-${target.year}-${target.month}-${target.day}';
        // Ngày có ca có đúng 1 chấm xám (sắp tới).
        expect(
          find.descendant(
            of: find.byKey(
              Key(key.replaceFirst('calendar-day', 'calendar-dots')),
            ),
            matching: find.byType(Container),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();

        final dialog = find.byKey(const Key('shift-day-dialog'));
        expect(dialog, findsOneWidget);
        final d = target.day.toString().padLeft(2, '0');
        final m = target.month.toString().padLeft(2, '0');
        expect(find.text('$d/$m/${target.year}'), findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.text('Ca 1')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Chưa vào ca')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.text('Ghi chú: Chuẩn bị bàn'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Xem chi tiết')),
          findsOneWidget,
        );
        // Đóng hộp thoại thì quay lại lịch tháng.
        await tester.tap(find.byKey(const Key('shift-day-close')));
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(find.text('Lịch tháng'), findsOneWidget);
        // Bấm ngày không có ca: vẫn mở hộp thoại với thông báo trống.
        final empty = target.day == 15 ? 16 : 15;
        await tester.tap(
          find.byKey(Key('calendar-day-${target.year}-${target.month}-$empty')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Không có ca nào trong ngày này.'), findsOneWidget);
      },
    );
  });
}
