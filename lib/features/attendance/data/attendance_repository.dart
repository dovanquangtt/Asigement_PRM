import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import 'attendance_models.dart';

/// REST calls of the employee attendance module (see backend/docs/api-app-contract.md).
class AttendanceRepository {
  AttendanceRepository([ApiClient? client])
    : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<TodayResponse> today() async =>
      TodayResponse.fromJson(await _client.getMap('/api/attendance/me/today'));

  Future<AttendanceActionResponse> checkIn(AttendanceActionRequest request) =>
      _action('/api/attendance/check-in', request);

  Future<AttendanceActionResponse> checkOut(AttendanceActionRequest request) =>
      _action('/api/attendance/check-out', request);

  Future<AttendanceActionResponse> _action(
    String path,
    AttendanceActionRequest request,
  ) async => AttendanceActionResponse.fromJson(
    await _client.postMap(path, body: request.toJson()),
  );

  /// [from]/[to] are business days; they are sent as yyyy-MM-dd.
  Future<HistoryPage> history({
    DateTime? from,
    DateTime? to,
    int page = 0,
    int size = 20,
  }) async => HistoryPage.fromJson(
    await _client.getMap(
      '/api/attendance/me/history',
      query: {
        'from': from == null ? null : formatDay(from),
        'to': to == null ? null : formatDay(to),
        'page': page,
        'size': size,
      },
    ),
  );

  Future<AttendanceDetail> detail(int attendanceId) async =>
      AttendanceDetail.fromJson(
        await _client.getMap('/api/attendance/me/$attendanceId'),
      );

  /// Registers this phone; a manager must approve it before it can be used (POST /api/devices).
  Future<void> registerDevice({
    required String deviceIdentifier,
    String platform = 'android',
  }) => _client.post(
    '/api/devices',
    body: {'deviceIdentifier': deviceIdentifier, 'platform': platform},
  );

  static String formatDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// User-facing Vietnamese text for an API failure.
String attendanceErrorMessage(ApiException e) => switch (e.code) {
  'DEVICE_NOT_REGISTERED' =>
    'Thiết bị này chưa được đăng ký. Hãy đăng ký thiết bị và chờ quản lý duyệt.',
  'DEVICE_REVOKED' =>
    'Thiết bị này đã bị thu hồi. Hãy liên hệ quản lý để dùng thiết bị khác.',
  'NO_SHIFT' => 'Hôm nay bạn chưa được phân ca làm việc.',
  'DUPLICATE_ATTENDANCE' =>
    'Bạn đã chấm công lần này rồi. Hãy tải lại trang để xem trạng thái.',
  'ATTENDANCE_VOIDED' => 'Công đã bị hủy. Hãy liên hệ quản lý.',
  'ATTENDANCE_LOCKED' => 'Bảng công đã chốt, không thể thay đổi.',
  'UNAUTHORIZED' => 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
  'NETWORK' || 'TIMEOUT' || 'NOT_CONFIGURED' => e.message,
  _ => e.status >= 500
      ? 'Máy chủ gặp lỗi. Hãy thử lại sau.'
      : (e.message.isEmpty ? 'Không xử lý được yêu cầu.' : e.message),
};
