import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quanlinhansunhahang/app/backend_shell.dart';
import 'package:quanlinhansunhahang/core/errors/api_exception.dart';
import 'package:quanlinhansunhahang/core/network/api_client.dart';
import 'package:quanlinhansunhahang/core/network/token_store.dart';
import 'package:quanlinhansunhahang/features/schedule/data/schedule_repository.dart';
import 'package:quanlinhansunhahang/features/schedule/presentation/schedule_management_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Recorder {
  Recorder(this.handler) {
    client = ApiClient(
      client: MockClient((r) async {
        calls.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
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

UserSession session(Set<String> permissions, String role) => UserSession(
  userId: 1,
  username: 'u',
  role: role,
  permissions: permissions,
  profile: const {},
);

void main() {
  test('Repository builds the schedule requests and parses ids', () async {
    final r = Recorder((req) async {
      final p = req.url.path;
      if (p.endsWith('/branches')) return json([{'id': 1, 'name': 'A'}]);
      if (p.endsWith('/shifts/overview')) return json([]);
      if (req.method == 'POST' && p.endsWith('/shifts')) return json({'id': 42}, 201);
      if (p.endsWith('/eligible-employees')) return json([]);
      return http.Response('', 204);
    });
    final repo = ScheduleRepository(r.client);
    expect((await repo.branches()).single['name'], 'A');
    await repo.overview(branchId: 3);
    await repo.overview();
    final id = await repo.createShift(
      branchId: 1,
      start: DateTime.utc(2026, 11, 2, 1),
      end: DateTime.utc(2026, 11, 2, 9),
      requiredStaff: 2,
      note: 'x',
    );
    expect(id, 42);
    await repo.eligibleEmployees(42);
    await repo.assign(42, 7);
    await repo.unassign(42, 7);
    await repo.cancelShift(42);
    expect(r.calls, [
      'GET /api/schedule/branches',
      'GET /api/schedule/shifts/overview?branchId=3',
      'GET /api/schedule/shifts/overview',
      'POST /api/schedule/shifts',
      'GET /api/schedule/shifts/42/eligible-employees',
      'POST /api/schedule/shifts/42/assignments',
      'DELETE /api/schedule/shifts/42/assignments/7',
      'POST /api/schedule/shifts/42/cancel',
    ]);
    final created = jsonDecode(r.bodies[3]) as Map<String, dynamic>;
    expect(created['start'], '2026-11-02T01:00:00.000Z');
    expect(created['requiredStaff'], 2);
    expect(jsonDecode(r.bodies[5]), {'employeeId': 7});
  });

  test('Repository surfaces backend errors', () async {
    final r = Recorder((_) async => json({'code': 'FORBIDDEN', 'message': 'Không có quyền'}, 403));
    await expectLater(
      ScheduleRepository(r.client).assign(1, 2),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });

  Map<String, dynamic> employee(int id, String name, {bool ok = true, bool assigned = false, String? why}) => {
    'id': id,
    'full_name': name,
    'employee_code': 'E$id',
    'is_available': ok,
    'is_already_assigned': assigned,
    'conflict_reason': why,
  };

  testWidgets('Create shift then assign staff, showing conflicts', (tester) async {
    final assigned = <int>{};
    final r = Recorder((req) async {
      final p = req.url.path;
      if (p.endsWith('/branches')) return json([{'id': 1, 'name': 'Chi nhánh 1'}]);
      if (p.endsWith('/shifts/overview')) return json([]);
      if (req.method == 'POST' && p.endsWith('/shifts')) return json({'id': 7}, 201);
      if (p.endsWith('/shifts/7/eligible-employees')) {
        return json([
          employee(1, 'An', assigned: assigned.contains(1), ok: !assigned.contains(1)),
          employee(2, 'Bình', ok: false, why: 'Nhân viên bị trùng giờ ca.'),
        ]);
      }
      if (p.endsWith('/shifts/7/assignments')) {
        assigned.add((jsonDecode(req.body) as Map)['employeeId'] as int);
        return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    await tester.pumpWidget(MaterialApp(home: ScheduleManagementScreen(client: r.client)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có ca nào'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-shift-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('required-staff')), '0');
    await tester.tap(find.byKey(const Key('submit-shift')));
    await tester.pumpAndSettle();
    expect(find.text('Số nhân viên phải lớn hơn 0.'), findsOneWidget);
    expect(r.calls.where((c) => c == 'POST /api/schedule/shifts'), isEmpty);

    await tester.enterText(find.byKey(const Key('required-staff')), '2');
    await tester.tap(find.byKey(const Key('submit-shift')));
    await tester.pumpAndSettle();
    final body = jsonDecode(r.bodies[r.calls.indexOf('POST /api/schedule/shifts')]) as Map<String, dynamic>;
    expect(body['branchId'], 1);
    expect(body['requiredStaff'], 2);
    // 08:00 and 16:00 Vietnam time are 01:00 and 09:00 UTC.
    expect(DateTime.parse(body['start'] as String).hour, 1);
    expect(DateTime.parse(body['end'] as String).hour, 9);

    // The assign sheet opens straight away for the new shift.
    expect(find.textContaining('Phân nhân viên'), findsOneWidget);
    expect(find.text('Nhân viên bị trùng giờ ca.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('assign-2'))).onPressed,
      isNull,
      reason: 'conflicting employee cannot be assigned',
    );
    await tester.tap(find.byKey(const Key('assign-1')));
    await tester.pumpAndSettle();
    expect(r.calls, contains('POST /api/schedule/shifts/7/assignments'));
    expect(find.byKey(const Key('unassign-1')), findsOneWidget);
    expect(find.text('Đã phân vào ca này'), findsOneWidget);
  });

  testWidgets('Empty branch shows an explicit message; errors are retryable', (tester) async {
    var fail = true;
    final r = Recorder((req) async {
      final p = req.url.path;
      if (p.endsWith('/branches')) return json([{'id': 1, 'name': 'A'}]);
      if (p.endsWith('/shifts/overview')) {
        final now = DateTime.now().toUtc();
        return json([
          {
            'id': 7,
            'branch_name': 'A',
            'starts_at': DateTime.utc(now.year, now.month, now.day, 1).toIso8601String(),
            'ends_at': DateTime.utc(now.year, now.month, now.day, 9).toIso8601String(),
            'required_staff': 1,
            'assigned_count': 0,
            'assigned_staff_names': '',
            'status': 'scheduled',
          },
        ]);
      }
      if (p.endsWith('/eligible-employees')) {
        if (fail) return json({'code': 'FORBIDDEN', 'message': 'x'}, 403);
        return json([]);
      }
      return http.Response('', 404);
    });
    await tester.pumpWidget(MaterialApp(home: ScheduleManagementScreen(client: r.client)));
    await tester.pumpAndSettle();
    expect(find.text('Tạo ca'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shift-7')));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền phân ca.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Không có quyền phân ca.'));
    await tester.pumpAndSettle();
    expect(find.text('Chi nhánh này chưa có nhân viên đang làm việc.'), findsOneWidget);
  });

  testWidgets('Shell tabs follow permissions', (tester) async {
    Future<void> open(UserSession s) async {
      await tester.pumpWidget(MaterialApp(home: BackendShell(session: s)));
      await tester.pump();
    }

    await open(session({'attendance.self', 'profile.self'}, 'Nhân viên'));
    expect(find.text('Lịch ca'), findsOneWidget);
    expect(find.text('Phân ca'), findsNothing);

    await open(session({'attendance.review', 'shifts.manage', 'profile.self'}, 'Quản lý'));
    expect(find.text('Phân ca'), findsOneWidget);
    expect(find.text('Lịch ca'), findsNothing);
    expect(find.text('Thông báo'), findsOneWidget);
    expect(find.text('Tài khoản'), findsOneWidget);

    await tester.tap(find.text('Tài khoản'));
    await tester.pump();
    expect(find.text('Đăng xuất'), findsOneWidget);
  });
}
