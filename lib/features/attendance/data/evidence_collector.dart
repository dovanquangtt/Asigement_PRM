import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../../../services/attendance_sensors.dart';
import '../../../services/auth_service.dart' show AuthException;
import 'attendance_models.dart';

enum LocationProblemKind {
  serviceDisabled,
  denied,
  permanentlyDenied,
  mocked,
  stale,
  inaccurate,
  failed,
}

/// Why GPS evidence could not be collected; [message] is user-facing Vietnamese.
class LocationProblem implements Exception {
  const LocationProblem(this.kind, this.message);
  final LocationProblemKind kind;
  final String message;
  @override
  String toString() => 'LocationProblem($kind: $message)';
}

/// This phone as the backend knows it: a random per-install id (never IMEI / Android ID).
class DeviceIdentity {
  const DeviceIdentity(this.id, this.platform, this.model);
  final String id, platform;
  final String? model;
}

abstract interface class EvidenceCollector {
  Future<DeviceIdentity> deviceIdentity();

  /// Builds the request body from fresh GPS / Wi-Fi readings.
  /// Throws [LocationProblem] when location evidence is unusable.
  Future<AttendanceActionRequest> collect({int? assignmentId});

  Future<void> openAppSettings();
}

/// Real implementation: Geolocator permissions + the existing [AttendanceSensors] readings.
class DeviceEvidenceCollector implements EvidenceCollector {
  DeviceEvidenceCollector({
    FlutterSecureStorage? storage,
    AttendanceSensors? sensors,
    this.maxAccuracyMeters = 100,
    this.maxAge = const Duration(minutes: 2),
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _sensors = sensors ?? AttendanceSensors();

  final FlutterSecureStorage _storage;
  final AttendanceSensors _sensors;
  final double maxAccuracyMeters;
  final Duration maxAge;
  static const _idKey = 'device_registration_id';

  @override
  Future<DeviceIdentity> deviceIdentity() async {
    var id = await _storage.read(key: _idKey);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      id =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      await _storage.write(key: _idKey, value: id);
    }
    String? model;
    try {
      model = (await DeviceInfoPlugin().androidInfo).model;
    } catch (_) {
      model = null;
    }
    return DeviceIdentity(id, 'android', model);
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<AttendanceActionRequest> collect({int? assignmentId}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationProblem(
        LocationProblemKind.serviceDisabled,
        'Hãy bật dịch vụ vị trí (GPS) trên điện thoại rồi thử lại.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationProblem(
        LocationProblemKind.permanentlyDenied,
        'Quyền vị trí đã bị từ chối vĩnh viễn. Hãy mở cài đặt ứng dụng và cấp quyền vị trí.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationProblem(
        LocationProblemKind.denied,
        'Cần cấp quyền vị trí để chấm công.',
      );
    }
    final device = await deviceIdentity();
    final evidence = await _read();
    final lat = evidence.latitude, lon = evidence.longitude;
    if (lat == null || lon == null) {
      throw const LocationProblem(
        LocationProblemKind.failed,
        'Chưa lấy được vị trí GPS. Hãy ra nơi thoáng và thử lại.',
      );
    }
    if (evidence.mocked) {
      throw const LocationProblem(
        LocationProblemKind.mocked,
        'Phát hiện vị trí giả lập. Hãy tắt ứng dụng giả vị trí rồi thử lại.',
      );
    }
    if (DateTime.now().toUtc().difference(evidence.collectedAt.toUtc()) >
        maxAge) {
      throw const LocationProblem(
        LocationProblemKind.stale,
        'Vị trí đã cũ. Hãy chờ GPS cập nhật và thử lại.',
      );
    }
    final accuracy = evidence.accuracy;
    if (accuracy != null && accuracy > maxAccuracyMeters) {
      throw LocationProblem(
        LocationProblemKind.inaccurate,
        'Độ chính xác GPS thấp (±${accuracy.round()} m). Hãy ra nơi thoáng và thử lại.',
      );
    }
    return AttendanceActionRequest(
      assignmentId: assignmentId,
      deviceIdentifier: device.id,
      devicePlatform: device.platform,
      deviceModel: device.model,
      latitude: lat,
      longitude: lon,
      accuracyMeters: accuracy,
      locationCollectedAt: evidence.collectedAt.toUtc(),
      mockLocation: evidence.mocked,
      wifiSsid: evidence.ssid,
      wifiBssid: evidence.bssid,
    );
  }

  Future<_Reading> _read() async {
    try {
      final e = await _sensors.collect();
      return _Reading(
        e.latitude,
        e.longitude,
        e.accuracy,
        e.collectedAt,
        e.mocked,
        e.ssid,
        e.bssid,
      );
    } on AuthException catch (e) {
      // AttendanceSensors raises user-facing Vietnamese messages (GPS timeout, Wi-Fi, ...).
      throw LocationProblem(LocationProblemKind.failed, e.message);
    } on Exception {
      throw const LocationProblem(
        LocationProblemKind.failed,
        'KhÃ´ng láº¥y ÄÆ°á»£c vá» trÃ­. HÃ£y báº­t GPS vÃ  thá»­ láº¡i.',
      );
    }
  }
}

class _Reading {
  const _Reading(
    this.latitude,
    this.longitude,
    this.accuracy,
    this.collectedAt,
    this.mocked,
    this.ssid,
    this.bssid,
  );
  final double? latitude, longitude, accuracy;
  final DateTime collectedAt;
  final bool mocked;
  final String? ssid, bssid;
}
