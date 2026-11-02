import '../../../core/network/api_client.dart';

/// Shift scheduling for managers/admins over `/api/schedule` (see backend/docs/api-schedule.md).
/// Rows keep the backend's snake_case keys.
class ScheduleRepository {
  ScheduleRepository(this._client);
  final ApiClient _client;

  static const _base = '/api/schedule';

  List<Map<String, dynamic>> _rows(List<dynamic> raw) =>
      raw.cast<Map<String, dynamic>>();

  /// `[{id, code, name, ...}]`
  Future<List<Map<String, dynamic>>> branches() async =>
      _rows(await _client.getList('$_base/branches'));

  /// Every shift (optionally of one branch) with `assigned_count`, `assigned_staff_names`, `branch_name`.
  Future<List<Map<String, dynamic>>> overview({int? branchId}) async => _rows(
    await _client.getList(
      '$_base/shifts/overview',
      query: {'branchId': branchId},
    ),
  );

  /// Creates a shift; [start]/[end] are sent as UTC instants. Returns the new shift id.
  Future<int> createShift({
    required int branchId,
    required DateTime start,
    required DateTime end,
    required int requiredStaff,
    String note = '',
  }) async {
    final body = await _client.postMap(
      '$_base/shifts',
      body: {
        'branchId': branchId,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'requiredStaff': requiredStaff,
        'note': note,
      },
    );
    return (body['id'] as num).toInt();
  }

  /// Employees of the shift's branch with `is_available`, `is_already_assigned`, `conflict_reason`.
  Future<List<Map<String, dynamic>>> eligibleEmployees(int shiftId) async =>
      _rows(await _client.getList('$_base/shifts/$shiftId/eligible-employees'));

  Future<void> assign(int shiftId, int employeeId) => _client.post(
    '$_base/shifts/$shiftId/assignments',
    body: {'employeeId': employeeId},
  );

  Future<void> unassign(int shiftId, int employeeId) =>
      _client.delete('$_base/shifts/$shiftId/assignments/$employeeId');

  Future<void> cancelShift(int shiftId) =>
      _client.post('$_base/shifts/$shiftId/cancel');

  /// Employee answers an assigned shift (POST /api/schedule/assignments/{id}/respond).
  /// Rejecting needs a [note]; the server frees the slot and notifies the managers.
  Future<void> respond(int assignmentId, bool accept, {String note = ''}) =>
      _client.post(
        '$_base/assignments/$assignmentId/respond',
        body: {'accept': accept, if (!accept) 'note': note},
      );

  /// Employees the caller may inspect: `[{id, full_name, employee_code, branch_id, branch_name}]`.
  Future<List<Map<String, dynamic>>> employees() async =>
      _rows(await _client.getList('$_base/employees'));

  /// Every shift of one employee in [from]..[to] (Vietnam calendar days):
  /// `{employee, from, to, summary:{total,pending,accepted,rejected}, rows:[...]}`.
  Future<Map<String, dynamic>> employeeShifts(
    int employeeId, {
    required DateTime from,
    required DateTime to,
  }) {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return _client.getMap(
      '$_base/employees/$employeeId/shifts',
      query: {'from': day(from), 'to': day(to)},
    );
  }
}
