/// Ảnh chụp trạng thái cảm biến tại một thời điểm, dùng để đối chiếu trong SQLite.
/// Không chứa cờ "được chấp nhận" do giao diện tự quyết định.
class AttendanceEvidence {
  const AttendanceEvidence({
    required this.deviceIdentifier,
    required this.platform,
    required this.collectedAt,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.ssid,
    this.bssid,
    this.mocked = false,
  });
  final String deviceIdentifier;
  final String platform;
  final DateTime collectedAt;
  final double? latitude, longitude, accuracy;
  final String? ssid, bssid;
  final bool mocked;
}
