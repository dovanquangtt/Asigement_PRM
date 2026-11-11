/// Typed models for the manager/admin attendance endpoints (backend/docs/api-app-contract.md).
/// Parsing is tolerant: optional fields may be missing or null.
library;

typedef Json = Map<String, dynamic>;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double? _double(Object? v) => (v as num?)?.toDouble();
DateTime? _time(Object? v) => v == null ? null : DateTime.parse('$v');
List<Json> _list(Object? v) =>
    ((v as List?) ?? const []).cast<Map<String, dynamic>>();

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
  });
  final List<T> items;
  final int page, size, totalItems, totalPages;
  bool get hasNext => page + 1 < totalPages;

  factory PageResult.fromJson(Json json, T Function(Json) item) => PageResult(
    items: _list(json['items']).map(item).toList(),
    page: _int(json['page']),
    size: _int(json['size']),
    totalItems: _int(json['totalItems']),
    totalPages: _int(json['totalPages']),
  );
}

class EmployeeRef {
  const EmployeeRef({
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

  factory EmployeeRef.fromJson(Json j) => EmployeeRef(
    id: _int(j['id']),
    employeeCode: '${j['employeeCode'] ?? ''}',
    fullName: '${j['fullName'] ?? ''}',
    position: j['position'] as String?,
    branchId: (j['branchId'] as num?)?.toInt(),
    branchName: j['branchName'] as String?,
    avatarUrl: j['avatarUrl'] as String?,
  );
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

  factory ShiftRef.fromJson(Json j) => ShiftRef(
    assignmentId: _int(j['assignmentId']),
    shiftId: _int(j['shiftId']),
    startsAt: DateTime.parse('${j['startsAt']}'),
    endsAt: DateTime.parse('${j['endsAt']}'),
    branchId: (j['branchId'] as num?)?.toInt(),
    branchName: j['branchName'] as String?,
  );
}

/// GPS / device / Wi-Fi result: VERIFIED, FAILED or UNKNOWN.
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

  factory Verification.fromJson(Json? j) => j == null
      ? const Verification()
      : Verification(
          gps: j['gps'] as String? ?? 'UNKNOWN',
          device: j['device'] as String? ?? 'UNKNOWN',
          wifi: j['wifi'] as String? ?? 'UNKNOWN',
          distanceMeters: _double(j['distanceMeters']),
          radiusMeters: _double(j['radiusMeters']),
          warnings: ((j['warnings'] as List?) ?? const []).cast<String>(),
        );
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

  factory AttendanceInfo.fromJson(Json? j) => j == null
      ? const AttendanceInfo()
      : AttendanceInfo(
          checkInAt: _time(j['checkInAt']),
          checkOutAt: _time(j['checkOutAt']),
          status: j['status'] as String? ?? 'NOT_STARTED',
          arrivalStatus: j['arrivalStatus'] as String?,
          lateMinutes: _int(j['lateMinutes']),
          workedMinutes: _int(j['workedMinutes']),
          breakMinutes: _int(j['breakMinutes']),
          overtimeMinutes: _int(j['overtimeMinutes']),
        );
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.date,
    this.totalEmployees = 0,
    this.checkedIn = 0,
    this.working = 0,
    this.completed = 0,
    this.late = 0,
    this.notCheckedIn = 0,
    this.exceptions = 0,
    this.totalBranches,
    this.totalShifts,
  });
  final String date;
  final int totalEmployees, checkedIn, working, completed, late, notCheckedIn;
  final int exceptions;

  /// Admin summary only.
  final int? totalBranches, totalShifts;

  factory AttendanceSummary.fromJson(Json j) => AttendanceSummary(
    date: '${j['date'] ?? ''}',
    totalEmployees: _int(j['totalEmployees']),
    checkedIn: _int(j['checkedIn']),
    working: _int(j['working']),
    completed: _int(j['completed']),
    late: _int(j['late']),
    notCheckedIn: _int(j['notCheckedIn']),
    exceptions: _int(j['exceptions']),
    totalBranches: (j['totalBranches'] as num?)?.toInt(),
    totalShifts: (j['totalShifts'] as num?)?.toInt(),
  );
}

/// One row of the manager/admin attendance list (and of the exceptions list, which adds [reason]).
class AttendanceRow {
  const AttendanceRow({
    required this.attendanceId,
    required this.employee,
    required this.shift,
    this.checkInAt,
    this.checkOutAt,
    this.status = 'NOT_STARTED',
    this.late = false,
    this.lateMinutes = 0,
    this.workedMinutes = 0,
    this.gps = 'UNKNOWN',
    this.device = 'UNKNOWN',
    this.reason,
  });
  final int attendanceId;
  final EmployeeRef employee;
  final ShiftRef shift;
  final DateTime? checkInAt, checkOutAt;
  final String status, gps, device;
  final bool late;
  final int lateMinutes, workedMinutes;
  final String? reason;

  factory AttendanceRow.fromJson(Json j) {
    final v = (j['verification'] as Map<String, dynamic>?) ?? const {};
    return AttendanceRow(
      attendanceId: _int(j['attendanceId']),
      employee: EmployeeRef.fromJson(j['employee'] as Json),
      shift: ShiftRef.fromJson(j['shift'] as Json),
      checkInAt: _time(j['checkInAt']),
      checkOutAt: _time(j['checkOutAt']),
      status: j['status'] as String? ?? 'NOT_STARTED',
      late: j['late'] == true,
      lateMinutes: _int(j['lateMinutes']),
      workedMinutes: _int(j['workedMinutes']),
      gps: v['gps'] as String? ?? 'UNKNOWN',
      device: v['device'] as String? ?? 'UNKNOWN',
      reason: j['reason'] as String?,
    );
  }
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
    this.verification = const Verification(),
    this.rejectionReason,
  });
  final int eventId;
  final String type, result;
  final DateTime occurredAt;
  final double? latitude, longitude, accuracyMeters, distanceMeters;
  final Verification verification;
  final String? rejectionReason;

  bool get pending => result == 'PENDING_REVIEW';

  factory AttendanceEvent.fromJson(Json j) => AttendanceEvent(
    eventId: _int(j['eventId']),
    type: '${j['type']}',
    occurredAt: DateTime.parse('${j['occurredAt']}'),
    result: '${j['result']}',
    latitude: _double(j['latitude']),
    longitude: _double(j['longitude']),
    accuracyMeters: _double(j['accuracyMeters']),
    distanceMeters: _double(j['distanceMeters']),
    verification: Verification.fromJson(j['verification'] as Json?),
    rejectionReason: j['rejectionReason'] as String?,
  );
}

class AuditEntry {
  const AuditEntry({
    required this.action,
    this.actorName,
    this.at,
    this.detail,
  });
  final String action;
  final String? actorName, detail;
  final DateTime? at;

  factory AuditEntry.fromJson(Json j) => AuditEntry(
    action: '${j['action']}',
    actorName: j['actorName'] as String?,
    at: _time(j['at']),
    detail: j['detail'] is String
        ? j['detail'] as String
        : j['detail']?.toString(),
  );
}

class AttendanceDetail {
  const AttendanceDetail({
    required this.attendanceId,
    required this.employee,
    required this.shift,
    required this.attendance,
    required this.verification,
    required this.events,
    required this.exceptions,
    required this.auditLog,
  });
  final int attendanceId;
  final EmployeeRef employee;
  final ShiftRef shift;
  final AttendanceInfo attendance;
  final Verification verification;
  final List<AttendanceEvent> events;
  final List<String> exceptions;
  final List<AuditEntry> auditLog;

  bool get voided => attendance.status == 'VOIDED';

  factory AttendanceDetail.fromJson(int id, Json j) {
    final item = (j['item'] as Map<String, dynamic>?) ?? const {};
    final shiftJson = (j['shift'] ?? item['shift']) as Json;
    return AttendanceDetail(
      attendanceId: id,
      employee: EmployeeRef.fromJson(j['employee'] as Json),
      shift: ShiftRef.fromJson(shiftJson),
      attendance: AttendanceInfo.fromJson(
        (j['attendance'] as Json?) ??
            {
              'checkInAt': item['checkInAt'],
              'checkOutAt': item['checkOutAt'],
              'status': item['status'],
              'lateMinutes': item['lateMinutes'],
              'workedMinutes': item['workedMinutes'],
            },
      ),
      verification: Verification.fromJson(j['verification'] as Json?),
      events: _list(j['events']).map(AttendanceEvent.fromJson).toList(),
      exceptions: ((j['exceptions'] as List?) ?? const []).cast<String>(),
      auditLog: _list(j['auditLog']).map(AuditEntry.fromJson).toList(),
    );
  }
}

class BranchOption {
  const BranchOption(this.id, this.name);
  final int id;
  final String name;

  /// `/api/schedule/branches` rows are snake_case maps.
  factory BranchOption.fromJson(Json j) =>
      BranchOption(_int(j['id']), '${j['name']}');
}

class DeviceItem {
  const DeviceItem({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.deviceIdentifierMasked,
    required this.status,
    this.platform,
    this.registeredAt,
    this.approvedByName,
    this.revokedAt,
  });
  final int id, employeeId;
  final String employeeName, employeeCode, deviceIdentifierMasked, status;
  final String? platform, approvedByName;
  final DateTime? registeredAt, revokedAt;

  factory DeviceItem.fromJson(Json j) => DeviceItem(
    id: _int(j['id']),
    employeeId: _int(j['employeeId']),
    employeeName: '${j['employeeName'] ?? ''}',
    employeeCode: '${j['employeeCode'] ?? ''}',
    deviceIdentifierMasked: '${j['deviceIdentifierMasked'] ?? ''}',
    platform: j['platform'] as String?,
    registeredAt: _time(j['registeredAt']),
    status: '${j['status']}',
    approvedByName: j['approvedByName'] as String?,
    revokedAt: _time(j['revokedAt']),
  );
}

class ReportRow {
  const ReportRow({
    required this.key,
    required this.label,
    this.totalShifts = 0,
    this.success = 0,
    this.late = 0,
    this.missing = 0,
    this.exceptions = 0,
    this.voided = 0,
    this.workedMinutes = 0,
  });
  final String key, label;
  final int totalShifts, success, late, missing, exceptions, voided;
  final int workedMinutes;

  factory ReportRow.fromJson(Json j) => ReportRow(
    key: '${j['key']}',
    label: '${j['label']}',
    totalShifts: _int(j['totalShifts']),
    success: _int(j['success']),
    late: _int(j['late']),
    missing: _int(j['missing']),
    exceptions: _int(j['exceptions']),
    voided: _int(j['voided']),
    workedMinutes: _int(j['workedMinutes']),
  );
}

class AttendanceReport {
  const AttendanceReport({
    required this.groupBy,
    required this.from,
    required this.to,
    required this.rows,
  });
  final String groupBy, from, to;
  final List<ReportRow> rows;

  factory AttendanceReport.fromJson(Json j) => AttendanceReport(
    groupBy: '${j['groupBy']}',
    from: '${j['from']}',
    to: '${j['to']}',
    rows: _list(j['rows']).map(ReportRow.fromJson).toList(),
  );
}
