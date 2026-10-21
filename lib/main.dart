import 'package:flutter/material.dart';

import 'app.dart';

/// Điểm khởi chạy ứng dụng. Giao diện gốc nằm ở app.dart;
/// DatabaseStartup mở SQLite trước khi hiển thị màn hình đăng nhập.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrmApp());
}
