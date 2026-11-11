import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/shift_timeline.dart';

String sql(DateTime local) {
  final u = local.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:00';
}

RowData shift(
  int id,
  DateTime start, {
  DateTime? end,
  DateTime? checkIn,
  DateTime? checkOut,
  int pending = 0,
  String? state,
  String? note,
  DateTime? assignedAt,
  String response = 'accepted',
}) => {
  'assignment_id': id,
  'shift_id': id + 100,
  'starts_at': sql(start),
  'ends_at': sql(end ?? start.add(const Duration(hours: 4))),
  'branch_name': 'ANH EM QUÁN',
  'shift_status': 'scheduled',
  'assignment_status': 'assigned',
  'response_status': response,
  'assigned_at': assignedAt == null ? null : sql(assignedAt),
  'shift_note': note,
  'check_in_at': checkIn == null ? null : sql(checkIn),
  'check_out_at': checkOut == null ? null : sql(checkOut),
  'attendance_state': state,
  'pending_events': pending,
};

RowData leave(
  int id,
  DateTime start,
  DateTime end, {
  String status = 'approved',
}) => {
  'id': id,
  'status': status,
  'starts_at': sql(start),
  'ends_at': sql(end),
  'reason': 'Việc nhà',
  'leave_type_name': 'Phép năm',
};

void main() {
  // Thứ Tư 11/11/2026, 10:00 giờ địa phương.
  final now = DateTime(2026, 11, 11, 10);
  final nowUtc = now.toUtc();
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 11, day, hour, minute);

  group('shiftPhase', () {
    test('checked in and out => completed', () {
      expect(
        shiftPhase(
          shift(1, at(10, 8), checkIn: at(10, 8, 2), checkOut: at(10, 12)),
          nowUtc,
        ),
        ShiftPhase.completed,
      );
    });
    test('checked in, shift still running => working; after it ended => missing check-out', () {
      expect(
        shiftPhase(shift(1, at(11, 8), checkIn: at(11, 8, 5)), nowUtc),
        ShiftPhase.working,
      );
      expect(
        shiftPhase(shift(1, at(10, 8), checkIn: at(10, 8, 5)), nowUtc),
        ShiftPhase.missingCheckOut,
      );
    });
    test('pending review wins over missing times', () {
      expect(
        shiftPhase(shift(1, at(10, 8), pending: 1), nowUtc),
        ShiftPhase.pendingReview,
      );
      expect(
        shiftPhase(shift(1, at(11, 9), checkIn: at(11, 9), pending: 1), nowUtc),
        ShiftPhase.pendingReview,
      );
    });
    test(
      'no punch: future or running => not yet; ended => absent ("Nghỉ")',
      () {
        expect(shiftPhase(shift(1, at(13, 8)), nowUtc), ShiftPhase.notYet);
        expect(shiftPhase(shift(1, at(11, 9)), nowUtc), ShiftPhase.notYet);
        expect(shiftPhase(shift(1, at(9, 8)), nowUtc), ShiftPhase.absent);
      },
    );
    test('voided record is shown as voided even when times exist', () {
      expect(
        shiftPhase(
          shift(
            1,
            at(10, 8),
            checkIn: at(10, 8),
            checkOut: at(10, 12),
            state: 'VOIDED',
          ),
          nowUtc,
        ),
        ShiftPhase.voided,
      );
    });
    test('labels are the Vietnamese texts the product asked for', () {
      expect(phaseStyle(ShiftPhase.completed).label, 'Ca đã hoàn thành');
      expect(phaseStyle(ShiftPhase.absent).label, 'Nghỉ');
      expect(phaseStyle(ShiftPhase.notYet).label, 'Chưa vào ca');
    });
  });

  group('new / old shifts', () {
    test('assigned within 48h or still waiting for the answer is new; ended shifts never are', () {
      expect(
        shiftIsNew(shift(1, at(13, 8), assignedAt: at(11, 8)), nowUtc),
        isTrue,
      );
      expect(
        shiftIsNew(shift(1, at(13, 8), assignedAt: at(8, 8)), nowUtc),
        isFalse,
      );
      expect(
        shiftIsNew(
          shift(1, at(13, 8), assignedAt: at(1, 8), response: 'pending'),
          nowUtc,
        ),
        isTrue,
      );
      expect(
        shiftIsNew(shift(1, at(10, 8), assignedAt: at(11, 8)), nowUtc),
        isFalse,
      );
      expect(
        shiftIsNew(shift(1, at(13, 8)), nowUtc),
        isFalse,
      ); // không rõ ngày phân
    });
    test('old = ended before now', () {
      expect(shiftIsOld(shift(1, at(9, 8)), nowUtc), isTrue);
      expect(shiftIsOld(shift(1, at(11, 9)), nowUtc), isFalse);
      expect(shiftIsOld(shift(1, at(13, 9)), nowUtc), isFalse);
    });
  });

  group('buildTimeline', () {
    final from = DateTime(2026, 11, 9), to = DateTime(2026, 11, 15);
    test('keeps only the shifts of the week and sorts by day then time', () {
      final list = buildTimeline(
        shifts: [
          shift(3, at(12, 15)),
          shift(1, at(2, 8)), // tuần trước
          shift(2, at(12, 8)),
          shift(4, at(16, 8)), // tuần sau
        ],
        leaves: const [],
        from: from,
        to: to,
      );
      expect(list.map((e) => e.shift!['assignment_id']), [2, 3]);
    });

    test('approved multi-day leave is split per day; pending/rejected leave is ignored', () {
      final list = buildTimeline(
        shifts: const [],
        leaves: [
          leave(1, at(13, 8), at(15, 17)),
          leave(2, at(10, 8), at(10, 17), status: 'pending'),
          leave(3, at(11, 8), at(11, 17), status: 'rejected'),
        ],
        from: from,
        to: to,
      );
      expect(list.map((e) => e.day.day), [13, 14, 15]);
      expect(list.every((e) => e.leave!['id'] == 1), isTrue);
    });

    test(
      'leave ending exactly at midnight does not spill into the next day',
      () {
        final list = buildTimeline(
          shifts: const [],
          leaves: [leave(1, at(13, 0), at(14, 0))],
          from: from,
          to: to,
        );
        expect(list.map((e) => e.day.day), [13]);
      },
    );

    test('leave that starts before the week is clipped to it', () {
      final list = buildTimeline(
        shifts: const [],
        leaves: [leave(1, at(7, 8), at(10, 17))],
        from: from,
        to: to,
      );
      expect(list.map((e) => e.day.day), [9, 10]);
    });
  });

  group('ShiftTimeline widget', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<TimelineEntry> entries,
      DateTime? selectedDay,
      DateTime? weekStart,
      VoidCallback? onPrev,
      VoidCallback? onNext,
      ValueChanged<DateTime?>? onSelect,
    }) async {
      await tester.binding.setSurfaceSize(const Size(360, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShiftTimeline(
                entries: entries,
                weekStart: weekStart ?? DateTime(2026, 11, 9),
                selectedDay: selectedDay,
                now: now,
                onPrevWeek: onPrev ?? () {},
                onNextWeek: onNext ?? () {},
                onThisWeek: () {},
                onSelectDay: onSelect ?? (_) {},
                cardActions: (s, phase) => [
                  Text('actions-${s['assignment_id']}'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final entries = buildTimeline(
      shifts: [
        shift(
          1,
          at(9, 8),
          checkIn: at(9, 8, 3),
          checkOut: at(9, 12),
          note: 'Chuẩn bị bàn',
        ),
        shift(2, at(10, 8)), // đã qua, không điểm danh
        shift(3, at(12, 8)), // chưa tới
        shift(4, at(12, 13)),
      ],
      leaves: [leave(7, at(13, 8), at(13, 17))],
      from: DateTime(2026, 11, 9),
      to: DateTime(2026, 11, 15),
    );

    testWidgets(
      'shows the three statuses, the leave day, times and per-card actions',
      (tester) async {
        await pump(tester, entries: entries);
        expect(find.byKey(const Key('timeline-week-label')), findsOneWidget);
        expect(find.text('Tuần 09/11 – 15/11/2026'), findsOneWidget);
        // Ca đã hoàn thành (xanh), Nghỉ (nâu) cho ca vắng + ngày nghỉ phép, Chưa vào ca (xám).
        expect(find.text('Ca đã hoàn thành'), findsOneWidget);
        expect(find.text('Nghỉ'), findsNWidgets(2));
        expect(find.text('Chưa vào ca'), findsNWidgets(2));
        expect(find.byKey(const Key('timeline-leave-7')), findsOneWidget);
        expect(find.text('Giờ vào: 08:03   Giờ ra: 12:00'), findsOneWidget);
        expect(
          find.text('Giờ vào: Chưa có   Giờ ra: Chưa có'),
          findsNWidgets(3),
        );
        expect(find.text('Ghi chú: Chuẩn bị bàn'), findsOneWidget);
        expect(
          find.text('Ca 1'),
          findsNWidgets(3),
        ); // mỗi ngày đánh số Ca 1, Ca 2
        expect(find.text('Ca 2'), findsOneWidget);
        expect(find.text('actions-1'), findsOneWidget);
        expect(find.text('actions-3'), findsOneWidget);
        // Ngày có ca được nhóm theo ngày với nhãn thứ.
        expect(find.text('09/11'), findsOneWidget);
        expect(find.text('Thứ 2'), findsOneWidget);
      },
    );

    testWidgets('status chips are highlighted with their own color', (
      tester,
    ) async {
      await pump(tester, entries: entries);
      Color colorOf(String key) =>
          ((tester.widget<Container>(find.byKey(Key(key))).decoration)
                  as BoxDecoration)
              .color!;
      expect(
        colorOf('timeline-status-1'),
        phaseStyle(ShiftPhase.completed).color,
      );
      expect(colorOf('timeline-status-2'), phaseStyle(ShiftPhase.absent).color);
      expect(colorOf('timeline-status-3'), phaseStyle(ShiftPhase.notYet).color);
      expect(colorOf('timeline-leave-status-7'), leavePhaseStyle.color);
    });

    testWidgets(
      'week arrows and day taps call back; selected day filters the list',
      (tester) async {
        var prev = 0, next = 0;
        DateTime? picked;
        await pump(
          tester,
          entries: entries,
          onPrev: () => prev++,
          onNext: () => next++,
          onSelect: (d) => picked = d,
        );
        await tester.tap(find.byKey(const Key('timeline-prev')));
        await tester.tap(find.byKey(const Key('timeline-next')));
        expect((prev, next), (1, 1));
        await tester.tap(find.byKey(const Key('timeline-day-2026-11-12')));
        expect(picked, DateTime(2026, 11, 12));

        await pump(
          tester,
          entries: entries,
          selectedDay: DateTime(2026, 11, 12),
        );
        expect(find.text('actions-3'), findsOneWidget);
        expect(find.text('actions-4'), findsOneWidget);
        expect(find.text('actions-1'), findsNothing);
        expect(find.byKey(const Key('timeline-leave-7')), findsNothing);
      },
    );

    testWidgets(
      'new shifts get a MỚI badge and blue border, old shifts a Ca cũ badge',
      (tester) async {
        final list = buildTimeline(
          shifts: [
            shift(
              1,
              at(9, 8),
              checkIn: at(9, 8),
              checkOut: at(9, 12),
              assignedAt: at(1, 8),
            ), // cũ
            shift(2, at(12, 8), assignedAt: at(11, 8)), // mới (vừa phân)
            shift(
              3,
              at(13, 8),
              assignedAt: at(2, 8),
            ), // đã phân từ lâu, chưa tới
          ],
          leaves: const [],
          from: DateTime(2026, 11, 9),
          to: DateTime(2026, 11, 15),
        );
        await pump(tester, entries: list);
        expect(find.byKey(const Key('timeline-new-2')), findsOneWidget);
        expect(find.text('MỚI'), findsOneWidget);
        expect(find.byKey(const Key('timeline-new-1')), findsNothing);
        expect(find.byKey(const Key('timeline-new-3')), findsNothing);
        expect(find.byKey(const Key('timeline-old-1')), findsOneWidget);
        expect(find.text('Ca cũ'), findsOneWidget);
        BoxDecoration deco(int id) =>
            tester
                    .widget<Container>(find.byKey(Key('timeline-shift-$id')))
                    .decoration
                as BoxDecoration;
        expect((deco(2).border as Border).top.color, newShiftColor);
        expect((deco(2).border as Border).top.width, greaterThan(2));
        expect((deco(3).border as Border).top.color, isNot(newShiftColor));
      },
    );

    testWidgets('empty week and empty selected day show a message', (
      tester,
    ) async {
      await pump(tester, entries: const []);
      expect(find.text('Tuần này bạn không có ca làm.'), findsOneWidget);
      await pump(tester, entries: entries, selectedDay: DateTime(2026, 11, 14));
      expect(find.text('Bạn không có ca làm vào ngày này.'), findsOneWidget);
    });

    testWidgets('"Về tuần này" only appears away from the current week', (
      tester,
    ) async {
      await pump(tester, entries: entries);
      expect(find.byKey(const Key('timeline-today')), findsNothing);
      await pump(tester, entries: const [], weekStart: DateTime(2026, 11, 16));
      expect(find.byKey(const Key('timeline-today')), findsOneWidget);
    });
  });
}
