import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_evidence.dart';
import 'auth_service.dart';

/// Đọc bằng chứng từ plugin trên điện thoại; không tự đánh dấu điểm danh hợp lệ.
/// Quyền truy cập được hỏi khi dùng chức năng, không sửa cấu hình hệ điều hành.
class AttendanceSensors {
  /// Preserve missing/failed checks for Admin review instead of blocking submission.
  Future<({AttendanceEvidence evidence, List<String> issues})>
  collectForReview({bool requireGps = true, bool requireWifi = true}) async {
    final device = await collect(location: false);
    AttendanceEvidence? gpsSample, wifiSample;
    final issues = <String>[];
    try {
      if (requireGps) gpsSample = await collect(wifi: false);
    } catch (e) {
      issues.add(e is AuthException ? e.message : 'Không thu thập được GPS');
    }
    try {
      if (requireWifi) wifiSample = await collect(gps: false);
    } catch (e) {
      issues.add(e is AuthException ? e.message : 'Không thu thập được Wi-Fi');
    }
    return (
      evidence: AttendanceEvidence(
        deviceIdentifier: device.deviceIdentifier,
        platform: device.platform,
        collectedAt: gpsSample?.collectedAt ?? device.collectedAt,
        latitude: gpsSample?.latitude,
        longitude: gpsSample?.longitude,
        accuracy: gpsSample?.accuracy,
        mocked: gpsSample?.mocked ?? false,
        ssid: wifiSample?.ssid,
        bssid: wifiSample?.bssid,
      ),
      issues: issues,
    );
  }

  Future<AttendanceEvidence> collect({
    bool location = true,
    bool gps = true,
    bool wifi = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // ID riêng cho lần cài app, không phụ thuộc đường dẫn hoặc máy phát triển.
    var installation = prefs.getString('device_installation');
    installation ??= List.generate(
      32,
      (_) => Random.secure().nextInt(256),
    ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString('device_installation', installation);
    final info = await DeviceInfoPlugin().deviceInfo;
    final identifier = sha256
        .convert(
          utf8.encode(
            '$installation:${info.data['fingerprint'] ?? info.data['machineId'] ?? Platform.operatingSystem}',
          ),
        )
        .toString();
    Position? position;
    if (location) {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const AuthException('Hãy bật dịch vụ vị trí trên điện thoại.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const AuthException(
          'Cần cấp quyền vị trí để kiểm tra GPS và Wi-Fi.',
        );
      }
      if (gps) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20),
            ),
          );
        } on TimeoutException {
          throw const AuthException(
            'Chưa lấy được vị trí GPS. Hãy ra nơi thoáng, bật vị trí chính xác và thử lại.',
          );
        }
      }
    }
    String? ssid, bssid;
    if (location && wifi) {
      final network = NetworkInfo();
      ssid = await network.getWifiName();
      bssid = await network.getWifiBSSID();
      if (ssid != null &&
          ssid.length >= 2 &&
          ssid.startsWith('"') &&
          ssid.endsWith('"')) {
        ssid = ssid.substring(1, ssid.length - 1);
      }
    }
    return AttendanceEvidence(
      deviceIdentifier: identifier,
      platform: Platform.operatingSystem,
      collectedAt: position?.timestamp.toUtc() ?? DateTime.now().toUtc(),
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
      ssid: ssid,
      bssid: bssid,
      mocked: position?.isMocked ?? false,
    );
  }
}
