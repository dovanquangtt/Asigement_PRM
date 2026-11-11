import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quanlinhansunhahang/core/errors/api_exception.dart';
import 'package:quanlinhansunhahang/core/network/api_client.dart';
import 'package:quanlinhansunhahang/core/network/token_store.dart';
import 'package:quanlinhansunhahang/features/admin/data/admin_repository.dart';
import 'package:quanlinhansunhahang/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:quanlinhansunhahang/features/admin/presentation/attendance_report_view.dart';
import 'package:quanlinhansunhahang/features/admin/presentation/device_management_view.dart';
import 'package:quanlinhansunhahang/features/manager/data/attendance_repository.dart';
import 'package:quanlinhansunhahang/features/manager/presentation/attendance_widgets.dart';
import 'package:quanlinhansunhahang/features/manager/presentation/manager_attendance_detail_screen.dart';
import 'package:quanlinhansunhahang/features/manager/presentation/manager_dashboard_screen.dart';

typedef Handler = Future<http.Response> Function(http.Request request);

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class Fake {
  Fake(this.handler) {
    client = ApiClient(
      client: MockClient((request) => handler(request)),
      baseUrl: 'http://test',
      tokens: MemoryTokenStore(),
    );
  }
  final Handler handler;
  late final ApiClient client;
}

Map<String, dynamic> employee([String name = 'Nguyễn Văn A']) => {
  'id': 7,
  'employeeCode': 'NV007',
  'fullName': name,
  'position': 'Phục vụ',
  'branchId': 1,
  'branchName': 'Chi nhánh 1',
  'avatarUrl': null,
};

Map<String, dynamic> shift() => {
  'assignmentId': 11,
  'shiftId': 5,
  'startsAt': '2026-10-29T01:00:00Z',
  'endsAt': '2026-10-29T09:00:00Z',
  'branchId': 1,
  'branchName': 'Chi nhánh 1',
};

Map<String, dynamic> row({String status = 'SUCCESS', bool late = false}) => {
  'attendanceId': 11,
  'employee': employee(),
  'shift': shift(),
  'checkInAt': '2026-10-29T01:05:00Z',
  'checkOutAt': '2026-10-29T09:00:00Z',
  'status': status,
  'late': late,
  'lateMinutes': late ? 5 : 0,
  'workedMinutes': 475,
  'verification': {'gps': 'VERIFIED', 'device': 'FAILED'},
};

Map<String, dynamic> page(List<Object> items, {int p = 0, int pages = 1}) => {
  'items': items,
  'page': p,
  'size': 20,
  'totalItems': items.length,
  'totalPages': pages,
};

Map<String, dynamic> summaryJson({bool admin = false}) => {
  'date': '2026-10-29',
  'totalEmployees': 12,
  'checkedIn': 9,
  'working': 4,
  'completed': 5,
  'late': 2,
  'notCheckedIn': 3,
  'exceptions': 1,
  if (admin) 'totalBranches': 2,
  if (admin) 'totalShifts': 14,
};

Map<String, dynamic> detailJson({
  String status = 'IN_PROGRESS',
  bool pending = true,
}) => {
  'item': {'attendanceId': 11},
  'employee': employee(),
  'shift': shift(),
  'attendance': {
    'checkInAt': status == 'VOIDED' ? null : '2026-10-29T01:05:00Z',
    'checkOutAt': null,
    'status': status,
    'arrivalStatus': 'LATE',
    'lateMinutes': 5,
    'workedMinutes': 0,
    'breakMinutes': 0,
    'overtimeMinutes': 0,
  },
  'verification': {
    'gps': 'VERIFIED',
    'device': 'VERIFIED',
    'wifi': 'UNKNOWN',
    'distanceMeters': 23.4,
    'radiusMeters': 100,
    'warnings': ['Sai số GPS lớn'],
  },
  'events': [
    {
      'eventId': 99,
      'type': 'CHECK_IN',
      'occurredAt': '2026-10-29T01:05:00Z',
      'result': pending ? 'PENDING_REVIEW' : 'ACCEPTED',
      'latitude': 10.77,
      'longitude': 106.69,
      'accuracyMeters': 8,
      'distanceMeters': 23.4,
      'verification': {
        'gps': 'VERIFIED',
        'device': 'VERIFIED',
        'wifi': 'UNKNOWN',
      },
    },
  ],
  'exceptions': ['Check-in chờ duyệt'],
  'auditLog': [
    {
      'action': 'attendance.submit',
      'actorName': 'Nguyễn Văn A',
      'at': '2026-10-29T01:05:00Z',
      'detail': null,
    },
  ],
};

void bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('repositories', () {
    test(
      'manager list builds the query, omits empty filters and parses the page',
      () async {
        late Uri seen;
        final fake = Fake((r) async {
          seen = r.url;
          return jsonResponse(page([row()], pages: 3));
        });
        final repo = ManagerAttendanceRepository(fake.client);
        final result = await repo.list(
          date: DateTime(2026, 10, 29),
          status: 'LATE',
          q: ' an ',
          shiftId: 5,
          page: 1,
        );
        expect(seen.path, '/api/manager/attendance');
        expect(seen.queryParameters, {
          'date': '2026-10-29',
          'shiftId': '5',
          'status': 'LATE',
          'q': 'an',
          'page': '1',
          'size': '20',
        });
        expect(result.items.single.employee.fullName, 'Nguyễn Văn A');
        expect(result.items.single.gps, 'VERIFIED');
        expect(result.hasNext, isTrue);
      },
    );

    test(
      'admin repositories use admin paths; summary exposes admin totals',
      () async {
        final paths = <String>[];
        final fake = Fake((r) async {
          paths.add('${r.method} ${r.url.path}');
          if (r.url.path.endsWith('/summary'))
            return jsonResponse(summaryJson(admin: true));
          return jsonResponse(page([]));
        });
        final repo = ManagerAttendanceRepository(fake.client, admin: true);
        final s = await repo.summary(date: DateTime(2026, 10, 29), branchId: 2);
        await repo.exceptions(date: DateTime(2026, 10, 29));
        expect(paths, [
          'GET /api/admin/attendance/summary',
          'GET /api/admin/attendance/exceptions',
        ]);
        expect(s.totalBranches, 2);
        expect(s.totalShifts, 14);
        expect(s.notCheckedIn, 3);
      },
    );

    test(
      'review, edit and void call the existing endpoints with a reason',
      () async {
        final calls = <String, Object?>{};
        final fake = Fake((r) async {
          calls['${r.method} ${r.url.path}'] = jsonDecode(r.body);
          return http.Response('', 204);
        });
        final repo = ManagerAttendanceRepository(fake.client);
        await repo.reviewException(99, approve: false, note: ' sai wifi ');
        await repo.editTimes(
          11,
          checkIn: DateTime.utc(2026, 10, 29, 1),
          reason: ' quên ',
        );
        await repo.voidAttendance(11, reason: 'nghỉ');
        expect(calls['POST /api/attendance/submissions/99/review'], {
          'approve': false,
          'note': 'sai wifi',
        });
        expect(calls['POST /api/attendance/assignments/11/admin-edit'], {
          'checkIn': '2026-10-29T01:00:00.000Z',
          'checkOut': null,
          'reason': 'quên',
        });
        expect(calls['POST /api/attendance/assignments/11/void'], {
          'reason': 'nghỉ',
        });
      },
    );

    test('admin devices, revoke and report requests', () async {
      final seen = <String>[];
      Object? revokeBody;
      final fake = Fake((r) async {
        seen.add('${r.method} ${r.url}');
        if (r.url.path.endsWith('/revoke')) revokeBody = jsonDecode(r.body);
        if (r.url.path == '/api/schedule/branches') {
          return jsonResponse([
            {'id': 1, 'name': 'Chi nhánh 1'},
          ]);
        }
        if (r.url.path == '/api/admin/reports/attendance') {
          return jsonResponse({
            'groupBy': 'branch',
            'from': '2026-10-01',
            'to': '2026-10-31',
            'rows': [
              {
                'key': '1',
                'label': 'Chi nhánh 1',
                'totalShifts': 10,
                'success': 8,
                'late': 1,
                'missing': 1,
                'exceptions': 0,
                'voided': 0,
                'workedMinutes': 3600,
              },
            ],
          });
        }
        if (r.url.path == '/api/admin/devices') {
          return jsonResponse(
            page([
              {
                'id': 5,
                'employeeId': 7,
                'employeeName': 'A',
                'employeeCode': 'NV007',
                'deviceIdentifierMasked': 'abcd…wxyz',
                'platform': 'android',
                'registeredAt': '2026-10-01T00:00:00Z',
                'status': 'APPROVED',
              },
            ]),
          );
        }
        return http.Response('', 204);
      });
      final repo = AdminRepository(fake.client);
      expect((await repo.branches()).single.name, 'Chi nhánh 1');
      final devices = await repo.devices(status: 'APPROVED', q: 'a');
      expect(devices.items.single.deviceIdentifierMasked, 'abcd…wxyz');
      await repo.revokeDevice(5, reason: ' mất máy ');
      final report = await repo.report(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        groupBy: 'branch',
        branchId: 1,
      );
      expect(report.rows.single.workedMinutes, 3600);
      expect(revokeBody, {'reason': 'mất máy'});
      expect(seen[1], contains('status=APPROVED'));
      expect(seen.last, contains('groupBy=branch'));
      expect(seen.last, contains('branchId=1'));
    });

    test('403 becomes a clear permission message', () {
      expect(
        errorText(const ApiException('x', code: 'FORBIDDEN', status: 403)),
        contains('Không có quyền'),
      );
      expect(errorText(Exception('boom')), isNot(contains('boom')));
    });
  });

  group('manager dashboard', () {
    testWidgets('shows a progress indicator, then summary cards and rows', (
      tester,
    ) async {
      bigScreen(tester);
      final gate = Completer<void>();
      final fake = Fake((r) async {
        await gate.future;
        if (r.url.path.endsWith('/summary')) return jsonResponse(summaryJson());
        return jsonResponse(page([row(late: true)]));
      });
      await tester.pumpWidget(
        MaterialApp(home: ManagerDashboardScreen(client: fake.client)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('summary-checkedIn'))).data,
        '9',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('summary-notCheckedIn'))).data,
        '3',
      );
      expect(find.text('Nguyễn Văn A (NV007)'), findsOneWidget);
      expect(find.text('Thành công'), findsWidgets);
      expect(find.text('Muộn 5p'), findsOneWidget);
    });

    testWidgets('empty list shows the empty message', (tester) async {
      bigScreen(tester);
      final fake = Fake(
        (r) async => r.url.path.endsWith('/summary')
            ? jsonResponse(summaryJson())
            : jsonResponse(page([])),
      );
      await tester.pumpWidget(
        MaterialApp(home: ManagerDashboardScreen(client: fake.client)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-list')), findsOneWidget);
    });

    testWidgets('403 shows a permission error with retry', (tester) async {
      bigScreen(tester);
      final fake = Fake(
        (r) async => jsonResponse({
          'code': 'FORBIDDEN',
          'message': 'Tài khoản không có quyền thực hiện thao tác này.',
        }, 403),
      );
      await tester.pumpWidget(
        MaterialApp(home: ManagerDashboardScreen(client: fake.client)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Không có quyền'), findsWidgets);
      expect(find.text('Thử lại'), findsWidgets);
    });

    testWidgets('exceptions tab calls /exceptions and the search sends q', (
      tester,
    ) async {
      bigScreen(tester);
      final seen = <Uri>[];
      final fake = Fake((r) async {
        seen.add(r.url);
        if (r.url.path.endsWith('/summary')) return jsonResponse(summaryJson());
        return jsonResponse(page([row(status: 'PENDING_REVIEW')]));
      });
      await tester.pumpWidget(
        MaterialApp(home: ManagerDashboardScreen(client: fake.client)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search-field')), 'an');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        seen.any(
          (u) =>
              u.path == '/api/manager/attendance' &&
              u.queryParameters['q'] == 'an',
        ),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('tab-exceptions')));
      await tester.pumpAndSettle();
      expect(
        seen.any((u) => u.path == '/api/manager/attendance/exceptions'),
        isTrue,
      );
    });

    testWidgets('load more appends the next page', (tester) async {
      bigScreen(tester);
      final fake = Fake((r) async {
        if (r.url.path.endsWith('/summary')) return jsonResponse(summaryJson());
        final p = int.parse(r.url.queryParameters['page']!);
        final item = row()..['attendanceId'] = 11 + p;
        item['employee'] = employee(p == 0 ? 'Người Một' : 'Người Hai');
        return jsonResponse(page([item], p: p, pages: 2));
      });
      await tester.pumpWidget(
        MaterialApp(home: ManagerDashboardScreen(client: fake.client)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Người Một'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('load-more')));
      await tester.tap(find.byKey(const Key('load-more')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Người Hai'), findsOneWidget);
      expect(find.byKey(const Key('load-more')), findsNothing);
    });
  });

  group('attendance detail actions', () {
    Future<void> open(
      WidgetTester tester,
      Fake fake, {
      bool canEdit = true,
    }) async {
      bigScreen(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: ManagerAttendanceDetailScreen(
            repository: ManagerAttendanceRepository(fake.client),
            attendanceId: 11,
            canEdit: canEdit,
          ),
        ),
      );
    }

    testWidgets(
      'no edit actions while loading, on error or in read-only mode',
      (tester) async {
        final gate = Completer<void>();
        final slow = Fake((r) async {
          await gate.future;
          return jsonResponse(detailJson());
        });
        await open(tester, slow);
        await tester.pump();
        expect(find.byKey(const Key('edit-times')), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('edit-times')), findsOneWidget);

        final failing = Fake(
          (r) async => jsonResponse({'code': 'FORBIDDEN', 'message': 'x'}, 403),
        );
        await open(tester, failing);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('edit-times')), findsNothing);
        expect(find.textContaining('Không có quyền'), findsOneWidget);

        await open(
          tester,
          Fake((r) async => jsonResponse(detailJson())),
          canEdit: false,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('edit-times')), findsNothing);
        expect(find.byKey(const Key('void-attendance')), findsNothing);
        expect(find.byKey(const Key('approve-99')), findsNothing);
      },
    );

    testWidgets(
      'detail shows verification, distance, events and audit; voided hides void button',
      (tester) async {
        await open(
          tester,
          Fake((r) async => jsonResponse(detailJson(status: 'VOIDED'))),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('23 m (cho phép 100 m)'), findsWidgets);
        expect(find.textContaining('Sai số GPS lớn'), findsOneWidget);
        expect(find.textContaining('attendance.submit'), findsOneWidget);
        expect(find.byKey(const Key('void-attendance')), findsNothing);
        expect(find.text('Khôi phục / nhập lại giờ'), findsOneWidget);
      },
    );

    testWidgets('void requires a reason before calling the API', (
      tester,
    ) async {
      final posts = <String>[];
      final fake = Fake((r) async {
        if (r.method == 'POST') {
          posts.add('${r.url.path} ${r.body}');
          return http.Response('', 204);
        }
        return jsonResponse(detailJson());
      });
      await open(tester, fake);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('void-attendance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reason-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do.'), findsOneWidget);
      expect(posts, isEmpty);
      await tester.enterText(
        find.byKey(const Key('reason-field')),
        'Nghỉ không báo',
      );
      await tester.tap(find.byKey(const Key('reason-confirm')));
      await tester.pumpAndSettle();
      expect(posts.single, contains('/api/attendance/assignments/11/void'));
      expect(posts.single, contains('Nghỉ không báo'));
    });

    testWidgets('pending exception can be rejected only with a note', (
      tester,
    ) async {
      final posts = <String>[];
      final fake = Fake((r) async {
        if (r.method == 'POST') {
          posts.add('${r.url.path} ${r.body}');
          return http.Response('', 204);
        }
        return jsonResponse(detailJson());
      });
      await open(tester, fake);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reject-99')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reason-confirm')));
      await tester.pump();
      expect(posts, isEmpty);
      await tester.enterText(
        find.byKey(const Key('reason-field')),
        'Sai Wi-Fi',
      );
      await tester.tap(find.byKey(const Key('reason-confirm')));
      await tester.pumpAndSettle();
      expect(posts.single, contains('/api/attendance/submissions/99/review'));
      expect(posts.single, contains('"approve":false'));
    });
  });

  group('report', reportTests);
  group('admin screens', () {
    testWidgets('admin dashboard shows admin totals and the branch filter', (
      tester,
    ) async {
      bigScreen(tester);
      final fake = Fake((r) async {
        if (r.url.path == '/api/schedule/branches') {
          return jsonResponse([
            {'id': 1, 'name': 'Chi nhánh 1'},
          ]);
        }
        if (r.url.path.endsWith('/summary'))
          return jsonResponse(summaryJson(admin: true));
        if (r.url.path.startsWith('/api/admin/attendance'))
          return jsonResponse(page([row()]));
        return jsonResponse(page([]));
      });
      await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(client: fake.client)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('summary-totalBranches')))
            .data,
        '2',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('summary-totalShifts'))).data,
        '14',
      );
      expect(find.byKey(const Key('branch-filter')), findsOneWidget);
    });

    testWidgets('device revoke asks for a reason and then calls the API', (
      tester,
    ) async {
      bigScreen(tester);
      final posts = <String>[];
      final fake = Fake((r) async {
        if (r.method == 'POST') {
          posts.add('${r.url.path} ${r.body}');
          return http.Response('', 204);
        }
        return jsonResponse(
          page([
            {
              'id': 5,
              'employeeId': 7,
              'employeeName': 'Nguyễn Văn A',
              'employeeCode': 'NV007',
              'deviceIdentifierMasked': 'abcd…wxyz',
              'platform': 'android',
              'registeredAt': '2026-10-01T00:00:00Z',
              'status': 'APPROVED',
            },
          ]),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceManagementView(
              repository: AdminRepository(fake.client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('abcd…wxyz'), findsOneWidget);
      // Approved device: highlighted result, no Duyệt/Thu hồi buttons; revoke lives in the menu.
      expect(find.byKey(const Key('status-5')), findsOneWidget);
      expect(find.text('ĐÃ DUYỆT'), findsOneWidget);
      expect(find.byKey(const Key('revoke-5')), findsNothing);
      expect(find.byKey(const Key('approve-5')), findsNothing);
      await tester.tap(find.byKey(const Key('more-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thu hồi thiết bị'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reason-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do.'), findsOneWidget);
      expect(posts, isEmpty);
      await tester.enterText(find.byKey(const Key('reason-field')), 'Mất máy');
      await tester.tap(find.byKey(const Key('reason-confirm')));
      await tester.pumpAndSettle();
      expect(posts.single, contains('/api/admin/devices/5/revoke'));
      expect(posts.single, contains('Mất máy'));
    });

    testWidgets('devices empty and error states', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceManagementView(
              repository: AdminRepository(
                Fake((r) async => jsonResponse(page([]))).client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-devices')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceManagementView(
              repository: AdminRepository(
                Fake(
                  (r) async =>
                      jsonResponse({'code': 'FORBIDDEN', 'message': 'x'}, 403),
                ).client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Không có quyền'), findsOneWidget);
    });
  });
}

void reportTests() {
  testWidgets('report view renders grouped rows and empty state', (
    tester,
  ) async {
    bigScreen(tester);
    final seen = <Uri>[];
    var empty = false;
    final fake = Fake((r) async {
      seen.add(r.url);
      return jsonResponse({
        'groupBy': r.url.queryParameters['groupBy'],
        'from': '2026-10-01',
        'to': '2026-10-31',
        'rows': empty
            ? []
            : [
                {
                  'key': '1',
                  'label': 'Chi nhánh 1',
                  'totalShifts': 10,
                  'success': 8,
                  'late': 1,
                  'missing': 1,
                  'exceptions': 0,
                  'voided': 0,
                  'workedMinutes': 3600,
                },
              ],
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceReportView(repository: AdminRepository(fake.client)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chi nhánh 1'), findsOneWidget);
    expect(find.text('60g00'), findsOneWidget);
    await tester.tap(find.text('Chi nhánh'));
    await tester.pump();
    empty = true;
    await tester.tap(find.byKey(const Key('report-run')));
    await tester.pumpAndSettle();
    expect(seen.last.queryParameters['groupBy'], 'branch');
    expect(find.byKey(const Key('empty-report')), findsOneWidget);
  });
}
