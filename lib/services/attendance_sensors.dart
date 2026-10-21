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
  Future<AttendanceEvidence> collect({bool location = true}) async {
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
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    }
    String? ssid, bssid;
    if (location) {
      final wifi = NetworkInfo();
      ssid = await wifi.getWifiName();
      bssid = await wifi.getWifiBSSID();
    }
    return AttendanceEvidence(
      deviceIdentifier: identifier,
      platform: Platform.operatingSystem,
      collectedAt: DateTime.now().toUtc(),
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
      ssid: ssid?.replaceAll('"', ''),
      bssid: bssid,
      mocked: position?.isMocked ?? false,
    );
  }
}
