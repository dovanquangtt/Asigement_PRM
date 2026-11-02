import '../../../core/network/api_client.dart';
import '../../manager/data/attendance_models.dart';
import '../../manager/data/attendance_repository.dart';

/// Admin-only endpoints: branches, device management and attendance reports.
class AdminRepository {
  AdminRepository(this._client);
  final ApiClient _client;

  /// `GET /api/schedule/branches` (snake_case rows).
  Future<List<BranchOption>> branches() async =>
      (await _client.getList('/api/schedule/branches'))
          .cast<Map<String, dynamic>>()
          .map(BranchOption.fromJson)
          .toList();

  Future<PageResult<DeviceItem>> devices({
    String? status,
    String? q,
    int page = 0,
    int size = 20,
  }) async => PageResult.fromJson(
    await _client.getMap(
      '/api/admin/devices',
      query: {'status': status, 'q': q?.trim(), 'page': page, 'size': size},
    ),
    DeviceItem.fromJson,
  );

  Future<void> approveDevice(int id) =>
      _client.post('/api/admin/devices/$id/approve');

  Future<void> revokeDevice(int id, {required String reason}) => _client.post(
    '/api/admin/devices/$id/revoke',
    body: {'reason': reason.trim()},
  );

  Future<AttendanceReport> report({
    required DateTime from,
    required DateTime to,
    String groupBy = 'employee',
    int? branchId,
  }) async => AttendanceReport.fromJson(
    await _client.getMap(
      '/api/admin/reports/attendance',
      query: {
        'from': apiDate(from),
        'to': apiDate(to),
        'groupBy': groupBy,
        'branchId': branchId,
      },
    ),
  );
}
