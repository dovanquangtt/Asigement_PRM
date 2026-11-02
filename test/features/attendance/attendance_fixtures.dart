import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quanlinhansunhahang/core/network/api_client.dart';
import 'package:quanlinhansunhahang/core/network/token_store.dart';
import 'package:quanlinhansunhahang/features/attendance/data/attendance_models.dart';
import 'package:quanlinhansunhahang/features/attendance/data/evidence_collector.dart';

/// A route handler: returns (status, body json) for one request.
typedef ApiRoute = (int, Object?) Function(http.Request request);

class FakeApi {
  FakeApi(this.routes);
  final Map<String, ApiRoute> routes; // key: "METHOD /path"
  final List<http.Request> calls = [];

  int count(String key) => calls
      .where((r) => '${r.method} ${r.url.path}' == key)
      .length;

  ApiClient client() => ApiClient(
    client: MockClient((request) async {
      calls.add(request);
      final route = routes['${request.method} ${request.url.path}'];
      if (route == null) {
        return http.Response(
          jsonEncode({'code': 'NOT_FOUND', 'message': 'Không tìm thấy dữ liệu.'}),
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      final (status, body) = route(request);
      return http.Response.bytes(
        utf8.encode(body == null ? '' : jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    baseUrl: 'http://test.local',
    tokens: MemoryTokenStore(),
  );
}

Map<String, Object?> errorBody(String code, String message) => {
  'code': code,
  'message': message,
};

Map<String, Object?> employeeJson() => {
  'id': 7,
  'employeeCode': 'NV007',
  'fullName': 'Nguyễn Văn An',
  'position': 'Phục vụ',
  'branchId': 1,
  'branchName': 'Chi nhánh Quận 1',
  'avatarUrl': null,
};

Map<String, Object?> shiftJson({int assignmentId = 55}) => {
  'assignmentId': assignmentId,
  'shiftId': 9,
  'startsAt': '2026-10-29T01:00:00Z',
  'endsAt': '2026-10-29T09:00:00Z',
  'branchId': 1,
  'branchName': 'Chi nhánh Quận 1',
};

Map<String, Object?> verificationJson({double distance = 37}) => {
  'gps': 'VERIFIED',
  'device': 'VERIFIED',
  'wifi': 'UNKNOWN',
  'distanceMeters': distance,
  'radiusMeters': 100,
  'warnings': <String>[],
};

Map<String, Object?> todayJson({
  String state = 'NOT_CHECKED_IN',
  bool canCheckIn = false,
  bool canCheckOut = false,
  Map<String, Object?>? attendance,
  Map<String, Object?>? verification,
  bool shift = true,
  List<Map<String, Object?>> exceptions = const [],
}) => {
  'date': '2026-10-29',
  'serverTime': '2026-10-29T01:05:00Z',
  'employee': employeeJson(),
  'state': state,
  'shift': shift ? shiftJson() : null,
  'shifts': shift ? [shiftJson()] : <Object?>[],
  'attendance': attendance,
  'verification': verification,
  'pendingExceptions': exceptions,
  'canCheckIn': canCheckIn,
  'canCheckOut': canCheckOut,
};

Map<String, Object?> attendanceJson({
  String? checkIn,
  String? checkOut,
  String status = 'IN_PROGRESS',
  int worked = 0,
  int breakMinutes = 0,
  int late = 0,
}) => {
  'checkInAt': checkIn,
  'checkOutAt': checkOut,
  'status': status,
  'arrivalStatus': late > 0 ? 'LATE' : 'ON_TIME',
  'lateMinutes': late,
  'workedMinutes': worked,
  'breakMinutes': breakMinutes,
  'overtimeMinutes': 0,
};

Map<String, Object?> actionJson({
  String type = 'CHECK_IN',
  String result = 'ACCEPTED',
  String serverTime = '2026-10-29T01:02:03Z',
  double distance = 37,
  String status = 'WORKING',
  Map<String, Object?>? attendance,
  List<String> warnings = const [],
}) => {
  'attendanceId': 55,
  'eventId': 301,
  'type': type,
  'result': result,
  'serverTime': serverTime,
  'employee': employeeJson(),
  'branch': {'id': 1, 'name': 'Chi nhánh Quận 1'},
  'shift': shiftJson(),
  'verification': {...verificationJson(distance: distance), 'warnings': warnings},
  'attendance':
      attendance ?? attendanceJson(checkIn: '2026-10-29T01:02:03Z'),
  'status': status,
  'message': 'Đã ghi nhận.',
};

/// Evidence source without sensors; can be held back to test double taps.
class FakeCollector implements EvidenceCollector {
  FakeCollector({this.problem});
  LocationProblem? problem;
  int collectCalls = 0;
  bool settingsOpened = false;
  Future<void>? gate;

  @override
  Future<DeviceIdentity> deviceIdentity() async =>
      const DeviceIdentity('install-uuid-1', 'android', 'Pixel 8');

  @override
  Future<AttendanceActionRequest> collect({int? assignmentId}) async {
    collectCalls++;
    if (gate != null) await gate;
    if (problem != null) throw problem!;
    return AttendanceActionRequest(
      assignmentId: assignmentId,
      deviceIdentifier: 'install-uuid-1',
      deviceModel: 'Pixel 8',
      latitude: 10.77,
      longitude: 106.69,
      accuracyMeters: 8,
      locationCollectedAt: DateTime.utc(2026, 10, 29, 1, 2),
    );
  }

  @override
  Future<void> openAppSettings() async => settingsOpened = true;
}
