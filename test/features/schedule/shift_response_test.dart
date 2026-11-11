import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quanlinhansunhahang/core/network/api_client.dart';
import 'package:quanlinhansunhahang/core/network/token_store.dart';
import 'package:quanlinhansunhahang/features/attendance/presentation/upcoming_shifts_screen.dart';
import 'package:quanlinhansunhahang/features/schedule/data/schedule_repository.dart';
import 'package:quanlinhansunhahang/features/schedule/presentation/employee_shift_table_screen.dart';
import 'package:quanlinhansunhahang/features/schedule/presentation/schedule_management_screen.dart';

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Recorder {
  Recorder(this.handler) {
    client = ApiClient(
      client: MockClient((r) async {
        calls.add(
          '${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}',
        );
        bodies.add(r.body);
        return handler(r);
      }),
      baseUrl: 'http://test',
      tokens: MemoryTokenStore(),
    );
  }
  final Future<http.Response> Function(http.Request) handler;
  final calls = <String>[];
  final bodies = <String>[];
  late final ApiClient client;
}

Map<String, dynamic> shift(
  int id,
  String response, {
  Duration from = const Duration(days: 2),
}) {
  final start = DateTime.now().toUtc().add(from);
  return {
    'assignmentId': id,
    'shiftId': id + 100,
    'startsAt': start.toIso8601String(),
    'endsAt': start.add(const Duration(hours: 8)).toIso8601String(),
    'branchId': 1,
    'branchName': 'Chi nhánh 1',
    'status': 'NOT_STARTED',
    'responseStatus': response,
    'responseNote': null,
  };
}

void main() {
  test(
    'Repository builds respond / employees / employee shifts requests',
    () async {
      final r = Recorder((req) async {
        if (req.url.path.endsWith('/employees'))
          return json([
            {'id': 5, 'full_name': 'An'},
          ]);
        if (req.url.path.endsWith('/shifts')) {
          return json({
            'rows': [],
            'summary': {'total': 0, 'pending': 0, 'accepted': 0, 'rejected': 0},
          });
        }
        return http.Response('', 204);
      });
      final repo = ScheduleRepository(r.client);
      await repo.respond(9, true);
      await repo.respond(9, false, note: 'Bận');
      expect((await repo.employees()).single['id'], 5);
      await repo.employeeShifts(
        5,
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 30),
      );
      expect(r.calls, [
        'POST /api/schedule/assignments/9/respond',
        'POST /api/schedule/assignments/9/respond',
        'GET /api/schedule/employees',
        'GET /api/schedule/employees/5/shifts?from=2026-11-01&to=2026-11-30',
      ]);
      expect(jsonDecode(r.bodies[0]), {'accept': true});
      expect(jsonDecode(r.bodies[1]), {'accept': false, 'note': 'Bận'});
    },
  );

  testWidgets('Pending future shift shows buttons; accepted shows none', (
    tester,
  ) async {
    final r = Recorder(
      (_) async => json([shift(1, 'pending'), shift(2, 'accepted')]),
    );
    await tester.pumpWidget(
      MaterialApp(home: UpcomingShiftsScreen(client: r.client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chờ bạn xác nhận'), findsOneWidget);
    expect(find.text('Đã chấp nhận'), findsOneWidget);
    expect(find.byKey(const Key('accept-1')), findsOneWidget);
    expect(find.byKey(const Key('reject-1')), findsOneWidget);
    expect(find.byKey(const Key('accept-2')), findsNothing);
    expect(find.byKey(const Key('reject-2')), findsNothing);
  });

  testWidgets('Reject needs a reason and posts {accept:false,note}', (
    tester,
  ) async {
    final r = Recorder((req) async {
      if (req.method == 'POST') return http.Response('', 204);
      return json([shift(1, 'pending')]);
    });
    await tester.pumpWidget(
      MaterialApp(home: UpcomingShiftsScreen(client: r.client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(r.calls.where((c) => c.startsWith('POST')), isEmpty);
    expect(find.byKey(const Key('reject-reason')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('reject-reason')),
      'Bận việc nhà',
    );
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    final i = r.calls.indexOf('POST /api/schedule/assignments/1/respond');
    expect(i, isNonNegative);
    expect(jsonDecode(r.bodies[i]), {'accept': false, 'note': 'Bận việc nhà'});
    // list is reloaded after a successful answer
    expect(
      r.calls.where((c) => c.startsWith('GET /api/employees/me/shifts')).length,
      2,
    );
  });

  testWidgets('Accept posts {accept:true} and server errors are shown', (
    tester,
  ) async {
    var fail = false;
    final r = Recorder((req) async {
      if (req.method == 'POST') {
        return fail
            ? json({
                'code': 'BUSINESS_RULE',
                'message': 'Ca đã được phản hồi hoặc không còn hiệu lực.',
              }, 400)
            : http.Response('', 204);
      }
      return json([shift(1, 'pending')]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UpcomingShiftsScreen(client: r.client)),
      ),
    );
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.byKey(const Key('accept-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Ca đã được phản hồi hoặc không còn hiệu lực.'),
      findsOneWidget,
    );
    expect(
      jsonDecode(
        r.bodies[r.calls.indexOf('POST /api/schedule/assignments/1/respond')],
      ),
      {'accept': true},
    );
  });

  Map<String, dynamic> row(int id, String response, {String? note}) => {
    'assignment_id': id,
    'shift_id': id,
    'starts_at': '2026-11-03T01:00:00Z',
    'ends_at': '2026-11-03T09:00:00Z',
    'branch_name': 'Chi nhánh 1',
    'response_status': response,
    'response_note': note,
    'assigned_by_name': 'Quản lý A',
    'check_in_at': null,
    'check_out_at': null,
  };

  testWidgets('Shift table shows summary and the rejection reason', (
    tester,
  ) async {
    final r = Recorder((req) async {
      if (req.url.path.endsWith('/employees')) {
        return json([
          {
            'id': 5,
            'full_name': 'An',
            'employee_code': 'E5',
            'branch_name': 'Chi nhánh 1',
          },
        ]);
      }
      return json({
        'employee': {'id': 5},
        'summary': {'total': 2, 'pending': 0, 'accepted': 1, 'rejected': 1},
        'rows': [row(1, 'accepted'), row(2, 'rejected', note: 'Bận học')],
      });
    });
    await tester.pumpWidget(
      MaterialApp(home: EmployeeShiftTableScreen(client: r.client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lý do: Bận học'), findsOneWidget);
    expect(find.text('Đã từ chối'), findsWidgets);
    expect(find.text('Phân bởi Quản lý A'), findsOneWidget);
    expect(
      r.calls.last,
      startsWith('GET /api/schedule/employees/5/shifts?from='),
    );
    await tester.tap(find.byKey(const Key('table-next-month')));
    await tester.pumpAndSettle();
    expect(r.calls.where((c) => c.contains('/employees/5/shifts')).length, 2);
  });

  testWidgets(
    'Shift table lets the manager approve or reject pending check-in/out',
    (tester) async {
      var loads = 0;
      final r = Recorder((req) async {
        if (req.url.path.endsWith('/employees')) {
          return json([
            {
              'id': 5,
              'full_name': 'An',
              'employee_code': 'E5',
              'branch_name': 'Chi nhánh 1',
            },
          ]);
        }
        if (req.url.path.contains('/submissions/')) return json({});
        loads++;
        return json({
          'employee': {'id': 5},
          'summary': {'total': 1, 'pending': 0, 'accepted': 1, 'rejected': 0},
          'rows': [
            {
              ...row(1, 'accepted'),
              'pending_check_in_id': 11,
              'pending_check_in_at': '2026-11-03T01:02:00Z',
              'pending_check_out_id': 12,
              'pending_check_out_at': '2026-11-03T09:01:00Z',
              'sheet_status': 'PENDING_REVIEW',
            },
          ],
        });
      });
      await tester.binding.setSurfaceSize(
        const Size(400, 900),
      ); // phone width: no horizontal scrolling needed
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: EmployeeShiftTableScreen(client: r.client)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(chờ duyệt)'), findsNWidgets(2));
      // Check-out cannot be approved before the check-in is.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('approve-12')))
            .onPressed,
        isNull,
      );

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('approve-11')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const Key('approve-11')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-11')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-confirm')));
      await tester.pumpAndSettle();
      final approve = r.calls.indexOf(
        'POST /api/attendance/submissions/11/review',
      );
      expect(approve, isNonNegative);
      expect(jsonDecode(r.bodies[approve]), {'approve': true, 'note': ''});
      expect(loads, 2); // table reloaded after the decision

      // Rejecting needs a reason: an empty note keeps the dialog open.
      await tester.ensureVisible(find.byKey(const Key('reject-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reject-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-note')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('review-note')), 'Sai giờ');
      await tester.tap(find.byKey(const Key('review-confirm')));
      await tester.pumpAndSettle();
      final reject = r.calls.indexOf(
        'POST /api/attendance/submissions/12/review',
      );
      expect(jsonDecode(r.bodies[reject]), {
        'approve': false,
        'note': 'Sai giờ',
      });
    },
  );

  testWidgets('Shift table shows a clear message on 403', (tester) async {
    final r = Recorder(
      (_) async => json({
        'code': 'FORBIDDEN',
        'message': 'Tài khoản không có quyền thực hiện thao tác này.',
      }, 403),
    );
    await tester.pumpWidget(
      MaterialApp(home: EmployeeShiftTableScreen(client: r.client)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Không có quyền xem bảng ca'), findsOneWidget);
  });

  testWidgets('Phân ca screen exposes the shift table action', (tester) async {
    final r = Recorder((req) async {
      final p = req.url.path;
      if (p.endsWith('/branches'))
        return json([
          {'id': 1, 'name': 'Chi nhánh 1'},
        ]);
      if (p.endsWith('/shifts/overview')) return json([]);
      if (p.endsWith('/employees')) return json([]);
      return http.Response('', 404);
    });
    await tester.pumpWidget(
      MaterialApp(home: ScheduleManagementScreen(client: r.client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-shift-table')));
    await tester.pumpAndSettle();
    expect(find.text('Bảng ca theo nhân viên'), findsOneWidget);
    expect(find.text('Chưa có nhân viên đang làm việc.'), findsOneWidget);
  });
}
