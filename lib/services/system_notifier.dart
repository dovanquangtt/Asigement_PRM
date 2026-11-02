import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Hiển thị thông báo trên thanh trạng thái của điện thoại (heads-up, rung, âm báo).
/// Chỉ hoạt động trên Android/iOS; các nền tảng khác bỏ qua để không lỗi khi chạy test.
class SystemNotifier {
  SystemNotifier._();
  static final SystemNotifier instance = SystemNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationChannel(
    'workflow_alerts',
    'Thông báo công việc',
    description: 'Phân ca, đổi ca, duyệt điểm danh và các yêu cầu cần xử lý.',
    importance: Importance.max,
  );

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    if (_ready || !_supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(_channel);
      // Android 13+ phải xin quyền hiển thị thông báo.
      await android?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> show(int id, String title, String body) async {
    if (!_supported) return;
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
            ticker: title,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }
}
