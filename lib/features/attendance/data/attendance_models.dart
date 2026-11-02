/// Typed models of backend/docs/api-app-contract.md (employee attendance part).
library;

T? _opt<T>(Object? v) => v is T ? v : null;
int _int(Object? v) => v is num ? v.toInt() : 0;
double? _double(Object? v) => v is num ? v.toDouble() : null;
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;
List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
    : const [];

/// States of the attendance home screen.
enum AttendanceState {
  noShift,
  notCheckedIn,
  working,
  completed,
  exception;

  static AttendanceState parse(Object? raw) => switch (raw) {
    'NOT_CHECKED_IN' => notCheckedIn,
    'WORKING' => working,
    'COMPLETED' => completed,
    'ATTENDANCE_EXCEPTION' => exception,
    _ => noShift,
  };
}

class EmployeeInfo {
  const EmployeeInfo({
    required this.id,
    required this.employeeCode,
    required this.fullName,
    this.position,
    this.branchId,
    this.branchName,
    this.avatarUrl,
  });
  final int id;
  final String employeeCode, fullName;
  final String? position, branchName, avatarUrl;
  final int? branchId;

  factory EmployeeInfo.fromJson(Map<String, dynamic> j) => EmployeeInfo(
    id: _int(j['id']),
    employeeCode: _opt<String>(j['employeeCode']) ?? '',
    fullName: _opt<String>(j['fullName']) ?? '',
    position: _opt<String>(j['position']),
    branchId: j['branchId'] is num ? _int(j['branchId']) : null,
    branchName: _opt<String>(j['branchName']),
    avatarUrl: _opt<String>(j['avatarUrl']),
  );

  /// Up to two initials for the avatar.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final list = parts.toList();
    final first = list.first.substring(0, 1);
    return list.length == 1
        ? first.toUpperCase()
        : (first + list.last.substring(0, 1)).toUpperCase();
  }
}

class ShiftRef {
  const ShiftRef({
    required this.assignmentId,
    required this.shiftId,
    required this.startsAt,
    required this.endsAt,
    this.branchId,
    this.branchName,
  });
  final int assignmentId, shiftId;
  final DateTime startsAt, endsAt;
  final int? branchId;
  final String? branchName;

  static ShiftRef? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final start = _time(j['startsAt']), end = _time(j['endsAt']);
    if (start == null || end == null) return null;
    return ShiftRef(
      assignmentId: _int(j['assignmentId']),
      shiftId: _int(j['shiftId']),
      startsAt: start,
      endsAt: end,
      branchId: j['branchId'] is num ? _int(j['branchId']) : null,
      branchName: _opt<String>(j['branchName']),
    );
  }
}

/// gps / device / wifi results are "VERIFIED", "FAILED" or "UNKNOWN".
class Verification {
  const Verification({
    this.gps = 'UNKNOWN',
    this.device = 'UNKNOWN',
    this.wifi = 'UNKNOWN',
    this.distanceMeters,
    this.radiusMeters,
    this.warnings = const [],
  });
  final String gps, device, wifi;
  final double? distanceMeters, radiusMeters;
  final List<String> warnings;

  static Verification? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    return Verification(
      gps: _opt<String>(j['gps']) ?? 'UNKNOWN',
      device: _opt<String>(j['device']) ?? 'UNKNOWN',
      wifi: _opt<String>(j['wifi']) ?? 'UNKNOWN',
      distanceMeters: _double(j['distanceMeters']),
      radiusMeters: _double(j['radiusMeters']),
      warnings: [
        if (j['warnings'] is List)
          for (final w in j['warnings'] as List) '$w',
      ],
    );
  }
}

class AttendanceInfo {
  const AttendanceInfo({
    this.checkInAt,
    this.checkOutAt,
    this.status = 'NOT_STARTED',
    this.arrivalStatus,
    this.lateMinutes = 0,
    this.workedMinutes = 0,
    this.breakMinutes = 0,
    this.overtimeMinutes = 0,
  });
  final DateTime? checkInAt, checkOutAt;
  final String status;
  final String? arrivalStatus;
  final int lateMinutes, workedMinutes, breakMinutes, overtimeMinutes;

  static AttendanceInfo? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    return AttendanceInfo(
      checkInAt: _time(j['checkInAt']),
      checkOutAt: _time(j['checkOutAt']),
      status: _opt<String>(j['status']) ?? 'NOT_STARTED',
      arrivalStatus: _opt<String>(j['arrivalStatus']),
      lateMinutes: _int(j['lateMinutes']),
      workedMinutes: _int(j['workedMinutes']),
      breakMinutes: _int(j['breakMinutes']),
      overtimeMinutes: _int(j['overtimeMinutes']),
    );
  }
}

class PendingException {
  const PendingException(this.eventType, this.message);
  final String eventType, message;
}

class TodayResponse {
  const TodayResponse({
    required this.date,
    required this.serverTime,
    required this.employee,
    required this.state,
    this.shift,
    this.shifts = const [],
    this.attendance,
    this.verification,
    this.pendingExceptions = const [],
    this.canCheckIn = false,
    this.canCheckOut = false,
  });
  final String date;
  final DateTime? serverTime;
  final EmployeeInfo employee;
  final AttendanceState state;
  final ShiftRef? shift;
  final List<ShiftRef> shifts;
  final AttendanceInfo? attendance;
  final Verification? verification;
  final List<PendingException> pendingExceptions;
  final bool canCheckIn, canCheckOut;

  factory TodayResponse.fromJson(Map<String, dynamic> j) => TodayResponse(
    date: _opt<String>(j['date']) ?? '',
    serverTime: _time(j['serverTime']),
    employee: EmployeeInfo.fromJson(_map(j['employee']) ?? const {}),
    state: AttendanceState.parse(j['state']),
    shift: ShiftRef.tryParse(j['shift']),
    shifts: [
      for (final s in (j['shifts'] is List ? j['shifts'] as List : const []))
        ?ShiftRef.tryParse(s),
    ],
    attendance: AttendanceInfo.tryParse(j['attendance']),
    verification: Verification.tryParse(j['verification']),
    pendingExceptions: [
      for (final e in _maps(j['pendingExceptions']))
        PendingException(
          _opt<String>(e['eventType']) ?? '',
          _opt<String>(e['message']) ?? '',
        ),
    ],
    canCheckIn: j['canCheckIn'] == true,
    canCheckOut: j['canCheckOut'] == true,
  );
}

/// Request body of POST /api/attendance/check-in and /check-out.
class AttendanceActionRequest {
  const AttendanceActionRequest({
    this.assignmentId,
    required this.deviceIdentifier,
    this.devicePlatform = 'android',
    this.deviceModel,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.locationCollectedAt,
    this.mockLocation = false,
    this.wifiSsid,
    this.wifiBssid,
  });
  final int? assignmentId;
  final String deviceIdentifier, devicePlatform;
  final String? deviceModel, wifiSsid, wifiBssid;
  final double latitude, longitude;
  final double? accuracyMeters;
  final DateTime locationCollectedAt;
  final bool mockLocation;

  Map<String, Object?> toJson() => {
    'assignmentId': assignmentId,
    'deviceIdentifier': deviceIdentifier,
    'devicePlatform': devicePlatform,
    'deviceModel': deviceModel,
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'locationCollectedAt': locationCollectedAt.toUtc().toIso8601String(),
    'mockLocation': mockLocation,
    'wifiSsid': wifiSsid,
    'wifiBssid': wifiBssid,
  };
}

class AttendanceActionResponse {
  const AttendanceActionResponse({
    required this.attendanceId,
    required this.type,
    required this.result,
    required this.serverTime,
    required this.employee,
    this.branchName,
    this.shift,
    this.verification,
    this.attendance,
    required this.status,
    this.message,
  });
  final int attendanceId;

  /// "CHECK_IN" or "CHECK_OUT".
  final String type;

  /// "ACCEPTED" or "PENDING_REVIEW".
  final String result;
  final DateTime? serverTime;
  final EmployeeInfo employee;
  final String? branchName, message;
  final ShiftRef? shift;
  final Verification? verification;
  final AttendanceInfo? attendance;
  final AttendanceState status;

  bool get isCheckIn => type == 'CHECK_IN';
  bool get pendingReview => result == 'PENDING_REVIEW';

  factory AttendanceActionResponse.fromJson(Map<String, dynamic> j) {
    final shift = ShiftRef.tryParse(j['shift']);
    return AttendanceActionResponse(
      attendanceId: _int(j['attendanceId']),
      type: _opt<String>(j['type']) ?? '',
      result: _opt<String>(j['result']) ?? '',
      serverTime: _time(j['serverTime']),
      employee: EmployeeInfo.fromJson(_map(j['employee']) ?? const {}),
      branchName:
          _opt<String>(_map(j['branch'])?['name']) ?? shift?.branchName,
      shift: shift,
      verification: Verification.tryParse(j['verification']),
      attendance: AttendanceInfo.tryParse(j['attendance']),
      status: AttendanceState.parse(j['status']),
      message: _opt<String>(j['message']),
    );
  }
}

class HistoryItem {
  const HistoryItem({
    required this.attendanceId,
    required this.date,
    this.shift,
    this.checkInAt,
    this.checkOutAt,
    required this.status,
    this.late = false,
    this.lateMinutes = 0,
    this.workedMinutes = 0,
  });
  final int attendanceId;
  final String date;
  final ShiftRef? shift;
  final DateTime? checkInAt, checkOutAt;

  /// A SheetStatus such as SUCCESS, PENDING_REVIEW, MISSING_CHECK_OUT.
  final String status;
  final bool late;
  final int lateMinutes, workedMinutes;

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    attendanceId: _int(j['attendanceId']),
    date: _opt<String>(j['date']) ?? '',
    shift: ShiftRef.tryParse(j['shift']),
    checkInAt: _time(j['checkInAt']),
    checkOutAt: _time(j['checkOutAt']),
    status: _opt<String>(j['status']) ?? 'NOT_STARTED',
    late: j['late'] == true,
    lateMinutes: _int(j['lateMinutes']),
    workedMinutes: _int(j['workedMinutes']),
  );
}

class HistoryPage {
  const HistoryPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
  });
  final List<HistoryItem> items;
  final int page, size, totalItems, totalPages;
  bool get hasMore => page + 1 < totalPages;

  factory HistoryPage.fromJson(Map<String, dynamic> j) => HistoryPage(
    items: [for (final e in _maps(j['items'])) HistoryItem.fromJson(e)],
    page: _int(j['page']),
    size: _int(j['size']),
    totalItems: _int(j['totalItems']),
    totalPages: _int(j['totalPages']),
  );
}

class AttendanceEvent {
  const AttendanceEvent({
    required this.eventId,
    required this.type,
    required this.occurredAt,
    required this.result,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.distanceMeters,
    this.verification,
    this.rejectionReason,
  });
  final int eventId;
  final String type, result;
  final DateTime? occurredAt;
  final double? latitude, longitude, accuracyMeters, distanceMeters;
  final Verification? verification;
  final String? rejectionReason;

  factory AttendanceEvent.fromJson(Map<String, dynamic> j) => AttendanceEvent(
    eventId: _int(j['eventId']),
    type: _opt<String>(j['type']) ?? '',
    occurredAt: _time(j['occurredAt']),
    result: _opt<String>(j['result']) ?? '',
    latitude: _double(j['latitude']),
    longitude: _double(j['longitude']),
    accuracyMeters: _double(j['accuracyMeters']),
    distanceMeters: _double(j['distanceMeters']),
    verification: Verification.tryParse(j['verification']),
    rejectionReason: _opt<String>(j['rejectionReason']),
  );
}

class AttendanceDetail {
  const AttendanceDetail({
    required this.item,
    this.employee,
    this.verification,
    this.events = const [],
    this.exceptions = const [],
  });
  final HistoryItem item;
  final EmployeeInfo? employee;
  final Verification? verification;
  final List<AttendanceEvent> events;
  final List<String> exceptions;

  factory AttendanceDetail.fromJson(Map<String, dynamic> j) => AttendanceDetail(
    item: HistoryItem.fromJson(_map(j['item']) ?? const {}),
    employee: _map(j['employee']) == null
        ? null
        : EmployeeInfo.fromJson(_map(j['employee'])!),
    verification: Verification.tryParse(j['verification']),
    events: [for (final e in _maps(j['events'])) AttendanceEvent.fromJson(e)],
    exceptions: [
      if (j['exceptions'] is List) for (final e in j['exceptions'] as List) '$e',
    ],
  );
}
