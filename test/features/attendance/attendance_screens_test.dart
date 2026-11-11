import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/features/attendance/data/attendance_models.dart';
import 'package:quanlinhansunhahang/features/attendance/data/evidence_collector.dart';
import 'package:quanlinhansunhahang/features/attendance/presentation/attendance_history_screen.dart';
import 'package:quanlinhansunhahang/features/attendance/presentation/attendance_home_screen.dart';
import 'package:quanlinhansunhahang/features/attendance/presentation/attendance_success_screens.dart';
import 'package:quanlinhansunhahang/features/attendance/presentation/attendance_ui.dart';

import 'attendance_fixtures.dart';

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> pumpHome(
  WidgetTester tester,
  FakeApi api, {
  FakeCollector? collector,
  DateTime? now,
}) async {
  tall(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: AttendanceHomeScreen(
        client: api.client(),
        collector: collector ?? FakeCollector(),
        clock: now == null ? null : () => now,
        enableTicker: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FakeApi apiFor(
  Map<String, Object?> today, {
  Map<String, ApiRoute> extra = const {},
}) => FakeApi({'GET /api/attendance/me/today': (_) => (200, today), ...extra});

void main() {
  group('home states', () {
    testWidgets('NOT_CHECKED_IN shows only the check-in action', (
      tester,
    ) async {
      await pumpHome(tester, apiFor(todayJson(canCheckIn: true)));
      expect(find.text('Nguyễn Văn An'), findsOneWidget);
      expect(find.text('Mã NV: NV007'), findsOneWidget);
      expect(find.text('NA'), findsOneWidget);
      expect(find.byKey(const Key('checkInButton')), findsOneWidget);
      expect(find.byKey(const Key('checkOutButton')), findsNothing);
      expect(find.text('Chưa chấm công vào'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu xác minh'), findsOneWidget);
    });

    testWidgets('WORKING shows check-out and a UI-only elapsed counter', (
      tester,
    ) async {
      final checkIn = DateTime.utc(2026, 10, 29, 1);
      await pumpHome(
        tester,
        apiFor(
          todayJson(
            state: 'WORKING',
            canCheckOut: true,
            attendance: attendanceJson(checkIn: '2026-10-29T01:00:00Z'),
            verification: verificationJson(distance: 18),
          ),
        ),
        now: checkIn.add(const Duration(hours: 1, minutes: 30)),
      );
      expect(find.byKey(const Key('checkOutButton')), findsOneWidget);
      expect(find.byKey(const Key('checkInButton')), findsNothing);
      expect(find.byKey(const Key('elapsed')), findsOneWidget);
      expect(find.text('01:30:00'), findsOneWidget);
      expect(find.text('Đang làm việc'), findsOneWidget);
      expect(find.text('18 m (cho phép 100 m)'), findsOneWidget);
    });

    testWidgets('COMPLETED shows the summary and no actions', (tester) async {
      await pumpHome(
        tester,
        apiFor(
          todayJson(
            state: 'COMPLETED',
            attendance: attendanceJson(
              checkIn: '2026-10-29T01:00:00Z',
              checkOut: '2026-10-29T09:00:00Z',
              status: 'SUCCESS',
              worked: 455,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('checkInButton')), findsNothing);
      expect(find.byKey(const Key('checkOutButton')), findsNothing);
      expect(find.text('Đã hoàn thành ca'), findsOneWidget);
      expect(find.textContaining('7 giờ 35 phút'), findsOneWidget);
    });

    testWidgets('ATTENDANCE_EXCEPTION lists the exception', (tester) async {
      await pumpHome(
        tester,
        apiFor(
          todayJson(
            state: 'ATTENDANCE_EXCEPTION',
            exceptions: [
              {'eventType': 'CHECK_IN', 'message': 'Ngoài vùng cho phép 250 m'},
            ],
          ),
        ),
      );
      expect(find.text('Có ngoại lệ cần quản lý xử lý'), findsOneWidget);
      expect(find.textContaining('Ngoài vùng cho phép 250 m'), findsOneWidget);
    });

    testWidgets('NO_SHIFT explains and offers no action', (tester) async {
      await pumpHome(
        tester,
        apiFor(todayJson(state: 'NO_SHIFT', shift: false)),
      );
      expect(find.textContaining('chưa được phân ca hôm nay'), findsOneWidget);
      expect(find.byKey(const Key('checkInButton')), findsNothing);
      expect(find.byKey(const Key('checkOutButton')), findsNothing);
    });

    testWidgets('load failure shows an error with retry that recovers', (
      tester,
    ) async {
      var fail = true;
      final api = FakeApi({
        'GET /api/attendance/me/today': (_) => fail
            ? (500, errorBody('INTERNAL_ERROR', 'x'))
            : (200, todayJson(canCheckIn: true)),
      });
      await pumpHome(tester, api);
      expect(find.text('Máy chủ gặp lỗi. Hãy thử lại sau.'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('checkInButton')), findsOneWidget);
    });
  });

  group('check-in', () {
    testWidgets('success screen shows only data from the response', (
      tester,
    ) async {
      final api = apiFor(
        todayJson(canCheckIn: true),
        extra: {
          'POST /api/attendance/check-in': (_) => (
            201,
            actionJson(distance: 37, serverTime: '2026-10-29T01:02:03Z'),
          ),
        },
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pumpAndSettle();
      expect(find.text('Chấm công vào thành công'), findsOneWidget);
      expect(find.text('37 m (cho phép 100 m)'), findsOneWidget);
      expect(
        find.text(fmtDateTime(DateTime.utc(2026, 10, 29, 1, 2, 3))),
        findsOneWidget,
      );
      expect(find.text('Chi nhánh Quận 1'), findsOneWidget);
      expect(find.text('Đang làm việc'), findsOneWidget);
      expect(find.text('Xem lịch sử chấm công'), findsOneWidget);
      expect(find.text('Quay lại trang chủ'), findsOneWidget);
      // The request carries what the collector produced and the shift id.
      expect(api.count('POST /api/attendance/check-in'), 1);
      expect(
        api.calls.firstWhere((r) => r.method == 'POST').body,
        contains('"assignmentId":55'),
      );
    });

    testWidgets(
      'a different server distance is displayed, nothing is hardcoded',
      (tester) async {
        tall(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: CheckInSuccessScreen(
              response: AttendanceActionResponse.fromJson(
                actionJson(distance: 81),
              ),
            ),
          ),
        );
        expect(find.text('81 m (cho phép 100 m)'), findsOneWidget);
        expect(find.textContaining('23'), findsNothing);
      },
    );

    testWidgets('returning home refreshes today from the server', (
      tester,
    ) async {
      final api = apiFor(
        todayJson(canCheckIn: true),
        extra: {'POST /api/attendance/check-in': (_) => (201, actionJson())},
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quay lại trang chủ'));
      await tester.pumpAndSettle();
      expect(find.text('Chấm công'), findsWidgets);
      expect(
        api.count('GET /api/attendance/me/today'),
        greaterThanOrEqualTo(2),
      );
    });

    testWidgets('PENDING_REVIEW shows the explicit awaiting-manager variant', (
      tester,
    ) async {
      final api = apiFor(
        todayJson(canCheckIn: true),
        extra: {
          'POST /api/attendance/check-in': (_) => (
            201,
            actionJson(
              result: 'PENDING_REVIEW',
              status: 'ATTENDANCE_EXCEPTION',
              distance: 250,
              warnings: ['Ngoài vùng cho phép'],
            ),
          ),
        },
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pumpAndSettle();
      expect(find.text('Đã gửi, chờ quản lý xác nhận'), findsOneWidget);
      expect(find.text('Chấm công vào thành công'), findsNothing);
      expect(find.text('Ngoài vùng cho phép'), findsOneWidget);
      expect(find.text('250 m (cho phép 100 m)'), findsOneWidget);
    });

    testWidgets('double tap sends exactly one request', (tester) async {
      final gate = Completer<void>();
      final collector = FakeCollector()..gate = gate.future;
      final api = apiFor(
        todayJson(canCheckIn: true),
        extra: {'POST /api/attendance/check-in': (_) => (201, actionJson())},
      );
      await pumpHome(tester, api, collector: collector);
      final button = find.byKey(const Key('checkInButton'));
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(collector.collectCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.count('POST /api/attendance/check-in'), 1);
    });

    testWidgets('API failure shows the reason and keeps the check-in state', (
      tester,
    ) async {
      final api = apiFor(
        todayJson(canCheckIn: true),
        extra: {
          'POST /api/attendance/check-in': (_) =>
              (400, errorBody('NO_SHIFT', 'x')),
        },
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pumpAndSettle();
      expect(
        find.text('Hôm nay bạn chưa được phân ca làm việc.'),
        findsOneWidget,
      );
      expect(find.text('Chấm công vào thành công'), findsNothing);
      expect(find.byKey(const Key('checkInButton')), findsOneWidget);
      expect(find.text('Chưa chấm công vào'), findsOneWidget);
    });

    testWidgets('network failure keeps the state and re-enables the button', (
      tester,
    ) async {
      final api = apiFor(
        todayJson(canCheckIn: true),
        extra: {
          'POST /api/attendance/check-in': (_) =>
              (503, errorBody('SERVICE_UNAVAILABLE', 'x')),
        },
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pumpAndSettle();
      expect(find.text('Máy chủ gặp lỗi. Hãy thử lại sau.'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('checkInButton')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      'unregistered device offers registration and posts /api/devices',
      (tester) async {
        final api = apiFor(
          todayJson(canCheckIn: true),
          extra: {
            'POST /api/attendance/check-in': (_) =>
                (403, errorBody('DEVICE_NOT_REGISTERED', 'x')),
            'POST /api/devices': (_) => (201, null),
          },
        );
        await pumpHome(tester, api);
        await tester.tap(find.byKey(const Key('checkInButton')));
        await tester.pumpAndSettle();
        expect(find.text('Thiết bị chưa đăng ký'), findsOneWidget);
        await tester.tap(find.text('Đăng ký thiết bị'));
        await tester.pumpAndSettle();
        expect(api.count('POST /api/devices'), 1);
        expect(api.calls.last.body, contains('install-uuid-1'));
        expect(
          find.textContaining('Quản lý cần duyệt thiết bị'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('checkInButton')), findsOneWidget);
      },
    );

    testWidgets(
      'permanently denied location offers app settings, no request is sent',
      (tester) async {
        final collector = FakeCollector(
          problem: const LocationProblem(
            LocationProblemKind.permanentlyDenied,
            'Quyền vị trí đã bị từ chối vĩnh viễn.',
          ),
        );
        final api = apiFor(todayJson(canCheckIn: true));
        await pumpHome(tester, api, collector: collector);
        await tester.tap(find.byKey(const Key('checkInButton')));
        await tester.pumpAndSettle();
        expect(find.text('Cần quyền vị trí'), findsOneWidget);
        await tester.tap(find.text('Mở cài đặt'));
        await tester.pumpAndSettle();
        expect(collector.settingsOpened, isTrue);
        expect(api.count('POST /api/attendance/check-in'), 0);
      },
    );

    testWidgets('GPS disabled is reported and nothing is sent', (tester) async {
      final collector = FakeCollector(
        problem: const LocationProblem(
          LocationProblemKind.serviceDisabled,
          'Hãy bật dịch vụ vị trí (GPS) trên điện thoại rồi thử lại.',
        ),
      );
      final api = apiFor(todayJson(canCheckIn: true));
      await pumpHome(tester, api, collector: collector);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bật dịch vụ vị trí'), findsOneWidget);
      expect(api.count('POST /api/attendance/check-in'), 0);
    });
  });

  group('check-out', () {
    FakeApi workingApi({ApiRoute? checkOut}) => apiFor(
      todayJson(
        state: 'WORKING',
        canCheckOut: true,
        attendance: attendanceJson(checkIn: '2026-10-29T01:00:00Z'),
      ),
      extra: {'POST /api/attendance/check-out': ?checkOut},
    );

    testWidgets('success screen shows server times and payable hours', (
      tester,
    ) async {
      final api = workingApi(
        checkOut: (_) => (
          201,
          actionJson(
            type: 'CHECK_OUT',
            status: 'COMPLETED',
            serverTime: '2026-10-29T09:10:00Z',
            attendance: attendanceJson(
              checkIn: '2026-10-29T01:00:00Z',
              checkOut: '2026-10-29T09:10:00Z',
              status: 'SUCCESS',
              worked: 455,
              breakMinutes: 35,
            ),
          ),
        ),
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkOutButton')));
      await tester.pumpAndSettle();
      expect(find.text('Chấm công ra thành công'), findsOneWidget);
      expect(
        find.text(fmtDateTime(DateTime.utc(2026, 10, 29, 1))),
        findsOneWidget,
      );
      expect(
        find.text(fmtDateTime(DateTime.utc(2026, 10, 29, 9, 10))),
        findsOneWidget,
      );
      expect(
        find.text('8 giờ 10 phút'),
        findsOneWidget,
      ); // elapsed, not payable
      expect(find.text('7 giờ 35 phút'), findsOneWidget); // payable
      expect(find.text('Giờ công tính lương'), findsOneWidget);
      expect(find.text('35 phút'), findsOneWidget); // break
      expect(find.text('Xem chi tiết chấm công'), findsOneWidget);
    });

    testWidgets('failure keeps the working state and check-out button', (
      tester,
    ) async {
      final api = workingApi(
        checkOut: (_) => (500, errorBody('INTERNAL_ERROR', 'boom')),
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkOutButton')));
      await tester.pumpAndSettle();
      expect(find.text('Chấm công ra thành công'), findsNothing);
      expect(find.byKey(const Key('checkOutButton')), findsOneWidget);
      expect(find.text('Đang làm việc'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('duplicate check-out reloads the real state', (tester) async {
      final api = workingApi(
        checkOut: (_) => (409, errorBody('DUPLICATE_ATTENDANCE', 'x')),
      );
      await pumpHome(tester, api);
      await tester.tap(find.byKey(const Key('checkOutButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('đã chấm công lần này'), findsOneWidget);
      expect(api.count('GET /api/attendance/me/today'), 2);
    });
  });

  group('history and detail', () {
    Map<String, Object?> item(int id, String status, {bool late = false}) => {
      'attendanceId': id,
      'date': '2026-10-29',
      'shift': shiftJson(assignmentId: id),
      'checkInAt': '2026-10-29T01:00:00Z',
      'checkOutAt': '2026-10-29T09:00:00Z',
      'status': status,
      'late': late,
      'lateMinutes': late ? 9 : 0,
      'workedMinutes': 480,
    };

    testWidgets('lists items with status, late flag and loads more', (
      tester,
    ) async {
      final api = FakeApi({
        'GET /api/attendance/me/history': (r) {
          final page = int.parse(r.url.queryParameters['page'] ?? '0');
          return (
            200,
            {
              'items': page == 0
                  ? [item(1, 'SUCCESS', late: true)]
                  : [item(2, 'PENDING_REVIEW')],
              'page': page,
              'size': 1,
              'totalItems': 2,
              'totalPages': 2,
            },
          );
        },
      });
      tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceHistoryScreen(client: api.client(), pageSize: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thành công'), findsOneWidget);
      expect(find.text('Đi muộn 9 phút'), findsOneWidget);
      await tester.tap(find.text('Tải thêm'));
      await tester.pumpAndSettle();
      expect(find.text('Chờ duyệt'), findsOneWidget);
      expect(find.text('Tải thêm'), findsNothing);
    });

    testWidgets('empty month and errors have their own states', (tester) async {
      var fail = false;
      final api = FakeApi({
        'GET /api/attendance/me/history': (_) => fail
            ? (500, errorBody('INTERNAL_ERROR', 'x'))
            : (
                200,
                {
                  'items': [],
                  'page': 0,
                  'size': 20,
                  'totalItems': 0,
                  'totalPages': 0,
                },
              ),
      });
      await tester.pumpWidget(
        MaterialApp(home: AttendanceHistoryScreen(client: api.client())),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Không có dữ liệu chấm công trong khoảng này.'),
        findsOneWidget,
      );
      fail = true;
      await tester.tap(find.byTooltip('Tháng trước'));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại'), findsOneWidget);
    });

    testWidgets('detail shows per-event verification and exceptions', (
      tester,
    ) async {
      final api = FakeApi({
        'GET /api/attendance/me/55': (_) => (
          200,
          {
            'item': item(55, 'PENDING_REVIEW'),
            'verification': null,
            'events': [
              {
                'eventId': 1,
                'type': 'CHECK_IN',
                'occurredAt': '2026-10-29T01:00:00Z',
                'result': 'PENDING_REVIEW',
                'accuracyMeters': 12,
                'verification': {
                  ...verificationJson(distance: 250),
                  'gps': 'FAILED',
                },
                'rejectionReason': null,
              },
            ],
            'exceptions': ['Ngoài vùng cho phép'],
          },
        ),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceDetailScreen(attendanceId: 55, client: api.client()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ngoài vùng cho phép'), findsOneWidget);
      expect(find.text('Không đạt'), findsOneWidget);
      expect(find.text('250 m (cho phép 100 m)'), findsOneWidget);
      expect(find.text('Chờ quản lý xác nhận'), findsOneWidget);
      expect(find.text('Độ chính xác GPS: ±12 m'), findsOneWidget);
    });
  });
}
