import 'package:flutter/foundation.dart';

/// Dữ liệu mẫu dùng chung trong một phiên đăng nhập.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.role});
  final String role;
  int tab = 0;
  int selectedDay = 2;
  int month = 10;
  int stars = 12;
  bool entered = false;
  bool exited = false;
  bool closed = false;
  bool notificationsRead = false;
  DateTime? enteredAt;
  final List<String> requests = [];
  bool get manager => role != 'Nhân viên';
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}
