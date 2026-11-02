import '../../../core/network/api_client.dart';
import 'attendance_models.dart';

String apiDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Attendance endpoints for reviewers. `/api/manager/attendance` is branch-scoped,
/// `/api/admin/attendance` covers every branch.
class ManagerAttendanceRepository {
  ManagerAttendanceRepository(this._client, {this.admin = false});
  final ApiClient _client;
  final bool admin;

  String get _base => admin ? '/api/admin/attendance' : '/api/manager/attendance';

  Future<AttendanceSummary> summary({
    required DateTime date,
    int? branchId,
  }) async => AttendanceSummary.fromJson(
    await _client.getMap(
      '$_base/summary',
      query: {'date': apiDate(date), 'branchId': branchId},
    ),
  );

  Future<PageResult<AttendanceRow>> list({
    required DateTime date,
    int? branchId,
    int? shiftId,
    String? status,
    String? q,
    int page = 0,
    int size = 20,
  }) async => PageResult.fromJson(
    await _client.getMap(
      _base,
      query: {
        'date': apiDate(date),
        'branchId': branchId,
        'shiftId': shiftId,
        'status': status,
        'q': q?.trim(),
        'page': page,
        'size': size,
      },
    ),
    AttendanceRow.fromJson,
  );

  Future<PageResult<AttendanceRow>> exceptions({
    required DateTime date,
    int? branchId,
    int page = 0,
    int size = 20,
  }) async => PageResult.fromJson(
    await _client.getMap(
      '$_base/exceptions',
      query: {
        'date': apiDate(date),
        'branchId': branchId,
        'page': page,
        'size': size,
      },
    ),
    AttendanceRow.fromJson,
  );

  Future<AttendanceDetail> detail(int attendanceId) async =>
      AttendanceDetail.fromJson(
        attendanceId,
        await _client.getMap('$_base/$attendanceId'),
      );

  // ---- Existing review endpoints (backend/docs/api-attendance.md) ----

  /// Approve or reject one exceptional check-in/out (event id from [AttendanceEvent]).
  Future<void> reviewException(
    int eventId, {
    required bool approve,
    String note = '',
  }) => _client.post(
    '/api/attendance/submissions/$eventId/review',
    body: {'approve': approve, 'note': note.trim()},
  );

  /// Direct edit; a missing time keeps the current one. [reason] is mandatory.
  Future<void> editTimes(
    int assignmentId, {
    DateTime? checkIn,
    DateTime? checkOut,
    required String reason,
  }) => _client.post(
    '/api/attendance/assignments/$assignmentId/admin-edit',
    body: {
      'checkIn': checkIn?.toUtc().toIso8601String(),
      'checkOut': checkOut?.toUtc().toIso8601String(),
      'reason': reason.trim(),
    },
  );

  Future<void> voidAttendance(int assignmentId, {required String reason}) =>
      _client.post(
        '/api/attendance/assignments/$assignmentId/void',
        body: {'reason': reason.trim()},
      );
}
