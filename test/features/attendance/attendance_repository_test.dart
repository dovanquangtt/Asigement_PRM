import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/core/errors/api_exception.dart';
import 'package:quanlinhansunhahang/features/attendance/data/attendance_models.dart';
import 'package:quanlinhansunhahang/features/attendance/data/attendance_repository.dart';

import 'attendance_fixtures.dart';

void main() {
  test('today() parses state, shift, attendance and verification', () async {
    final api = FakeApi({
      'GET /api/attendance/me/today': (_) => (
        200,
        todayJson(
          state: 'WORKING',
          canCheckOut: true,
          attendance: attendanceJson(checkIn: '2026-10-29T01:00:00Z'),
          verification: verificationJson(distance: 12.4),
        ),
      ),
    });
    final today = await AttendanceRepository(api.client()).today();
    expect(today.state, AttendanceState.working);
    expect(today.canCheckOut, isTrue);
    expect(today.employee.fullName, 'Nguyễn Văn An');
    expect(today.employee.initials, 'NA');
    expect(today.shift!.assignmentId, 55);
    expect(today.attendance!.checkInAt, DateTime.utc(2026, 10, 29, 1));
    expect(today.verification!.gps, 'VERIFIED');
    expect(today.verification!.distanceMeters, 12.4);
  });

  test('missing optional parts stay null instead of being invented', () async {
    final api = FakeApi({
      'GET /api/attendance/me/today': (_) =>
          (200, todayJson(state: 'NO_SHIFT', shift: false)),
    });
    final today = await AttendanceRepository(api.client()).today();
    expect(today.state, AttendanceState.noShift);
    expect(today.shift, isNull);
    expect(today.attendance, isNull);
    expect(today.verification, isNull);
  });

  test('checkIn posts the contract body and parses the response', () async {
    final api = FakeApi({
      'POST /api/attendance/check-in': (_) => (201, actionJson(distance: 41)),
    });
    final repo = AttendanceRepository(api.client());
    final response = await repo.checkIn(
      AttendanceActionRequest(
        assignmentId: 55,
        deviceIdentifier: 'dev-1',
        deviceModel: 'Pixel',
        latitude: 10.5,
        longitude: 106.5,
        accuracyMeters: 9,
        locationCollectedAt: DateTime.utc(2026, 10, 29, 1),
        wifiSsid: 'Quan',
        wifiBssid: 'aa:bb',
      ),
    );
    final body = jsonDecode(api.calls.single.body) as Map<String, dynamic>;
    expect(body['assignmentId'], 55);
    expect(body['deviceIdentifier'], 'dev-1');
    expect(body['devicePlatform'], 'android');
    expect(body['latitude'], 10.5);
    expect(body['accuracyMeters'], 9);
    expect(body['locationCollectedAt'], '2026-10-29T01:00:00.000Z');
    expect(body['mockLocation'], false);
    expect(
      api.calls.single.headers['Content-Type'],
      contains('application/json'),
    );
    expect(response.isCheckIn, isTrue);
    expect(response.pendingReview, isFalse);
    expect(response.serverTime, DateTime.utc(2026, 10, 29, 1, 2, 3));
    expect(response.branchName, 'Chi nhánh Quận 1');
    expect(response.verification!.distanceMeters, 41);
    expect(response.status, AttendanceState.working);
  });

  test('history sends yyyy-MM-dd range and paging, parses the page', () async {
    final api = FakeApi({
      'GET /api/attendance/me/history': (_) => (
        200,
        {
          'items': [
            {
              'attendanceId': 55,
              'date': '2026-10-29',
              'shift': shiftJson(),
              'checkInAt': '2026-10-29T01:00:00Z',
              'checkOutAt': null,
              'status': 'MISSING_CHECK_OUT',
              'late': true,
              'lateMinutes': 7,
              'workedMinutes': 0,
            },
          ],
          'page': 1,
          'size': 20,
          'totalItems': 41,
          'totalPages': 3,
        },
      ),
    });
    final page = await AttendanceRepository(
      api.client(),
    ).history(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31), page: 1);
    final q = api.calls.single.url.queryParameters;
    expect(q['from'], '2026-10-01');
    expect(q['to'], '2026-10-31');
    expect(q['page'], '1');
    expect(q['size'], '20');
    expect(page.items.single.late, isTrue);
    expect(page.items.single.lateMinutes, 7);
    expect(page.items.single.status, 'MISSING_CHECK_OUT');
    expect(page.hasMore, isTrue);
  });

  test('detail parses events with verification', () async {
    final api = FakeApi({
      'GET /api/attendance/me/55': (_) => (
        200,
        {
          'item': {
            'attendanceId': 55,
            'date': '2026-10-29',
            'status': 'SUCCESS',
          },
          'verification': verificationJson(),
          'events': [
            {
              'eventId': 1,
              'type': 'CHECK_IN',
              'occurredAt': '2026-10-29T01:00:00Z',
              'result': 'PENDING_REVIEW',
              'accuracyMeters': 12,
              'verification': verificationJson(distance: 250),
              'rejectionReason': null,
            },
          ],
          'exceptions': ['Ngoài vùng cho phép'],
        },
      ),
    });
    final detail = await AttendanceRepository(api.client()).detail(55);
    expect(detail.events.single.result, 'PENDING_REVIEW');
    expect(detail.events.single.verification!.distanceMeters, 250);
    expect(detail.exceptions, ['Ngoài vùng cho phép']);
  });

  group('error mapping', () {
    Future<ApiException> failure(int status, Object? body) async {
      final api = FakeApi({
        'GET /api/attendance/me/today': (_) => (status, body),
      });
      try {
        await AttendanceRepository(api.client()).today();
      } on ApiException catch (e) {
        return e;
      }
      throw TestFailure('expected ApiException');
    }

    test('backend {code,message} is preserved', () async {
      final e = await failure(409, errorBody('DUPLICATE_ATTENDANCE', 'trùng'));
      expect(e.code, 'DUPLICATE_ATTENDANCE');
      expect(e.status, 409);
      expect(attendanceErrorMessage(e), contains('đã chấm công'));
    });

    test('known codes become Vietnamese messages', () {
      String m(String code) =>
          attendanceErrorMessage(ApiException('x', code: code, status: 400));
      expect(m('DEVICE_NOT_REGISTERED'), contains('chưa được đăng ký'));
      expect(m('DEVICE_REVOKED'), contains('thu hồi'));
      expect(m('NO_SHIFT'), contains('chưa được phân ca'));
      expect(m('ATTENDANCE_VOIDED'), contains('hủy'));
      expect(m('ATTENDANCE_LOCKED'), contains('chốt'));
    });

    test('server errors never leak details', () async {
      final e = await failure(500, errorBody('INTERNAL_ERROR', 'secret trace'));
      expect(attendanceErrorMessage(e), isNot(contains('secret')));
    });

    test('401 and non-JSON bodies are handled', () async {
      final e = await failure(401, errorBody('UNAUTHORIZED', 'hết hạn'));
      expect(e.isUnauthorized, isTrue);
      final html = await failure(502, null);
      expect(html.status, 502);
    });
  });

  test('registerDevice posts to /api/devices', () async {
    final api = FakeApi({'POST /api/devices': (_) => (201, null)});
    await AttendanceRepository(api.client())
        .registerDevice(deviceIdentifier: 'abc');
    expect(jsonDecode(api.calls.single.body), {
      'deviceIdentifier': 'abc',
      'platform': 'android',
    });
  });
}
