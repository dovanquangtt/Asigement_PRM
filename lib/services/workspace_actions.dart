import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../state/workspace_controller.dart';
import '../widgets/common_widgets.dart';

/// Điều hướng và hộp thoại; không truy cập MySQL trong bản mẫu.
class WorkspaceActions {
  WorkspaceActions(this.context, this.controller);
  final BuildContext context;
  final WorkspaceController controller;
  void toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
  String clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<bool> request(String title) async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Nội dung / lý do',
            hintText: 'Nhập ngày, ca và lý do yêu cầu',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (note.text.trim().isNotEmpty)
                Navigator.pop(ctx, note.text.trim());
            },
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    // The controller is released after the dialog transition finishes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    note.dispose();
    if (!context.mounted || result == null) return false;
    controller.update(() => controller.requests.add('$title: $result'));
    toast('Đã lưu yêu cầu trong phiên trải nghiệm');
    return true;
  }

  Future<void> attendance() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          controller.entered ? 'Xác nhận ra ca?' : 'Xác nhận vào ca?',
        ),
        content: const Text(
          'Điểm danh mô phỏng. Thiết bị, GPS và Wi-Fi chưa được xác thực thực tế.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    controller.update(() {
      if (!controller.entered) {
        controller.entered = true;
        controller.enteredAt = DateTime.now();
      } else {
        controller.exited = true;
      }
    });
    toast(
      controller.exited ? 'Đã ghi nhận ra ca mẫu' : 'Đã ghi nhận vào ca mẫu',
    );
  }

  void detail(String title, List<(String, String)> rows) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            panel(
              child: Column(
                children: rows
                    .map(
                      (r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          r.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        subtitle: Text(
                          r.$2,
                          style: const TextStyle(fontSize: 16, color: ink),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void roster() => detail('Nhân viên trong ca', [
    ('Nguyễn Linh', 'NV001 • Phục vụ'),
    ('Trần Minh', 'NV002 • Phục vụ'),
    ('Lê An', 'NV003 • Thu ngân'),
    ('Phạm Huy', 'NV004 • Bếp'),
  ]);
  void requestList() => detail(
    'Yêu cầu đã gửi',
    controller.requests.isEmpty
        ? [('Chưa có yêu cầu', 'Tạo yêu cầu từ trang chủ hoặc lịch ca.')]
        : controller.requests
              .map((r) => (r, 'Chờ duyệt • dữ liệu mẫu'))
              .toList(),
  );
  void notifications() {
    controller.update(() => controller.notificationsRead = true);
    detail('Thông báo', [
      (
        'Lịch làm tuần này đã sẵn sàng',
        'Kiểm tra lịch ca để chuẩn bị cho tuần mới.',
      ),
      ('Phiếu lương tháng 9', 'Xem chi tiết trong mục Thu nhập.'),
      ('Dữ liệu trải nghiệm', 'Các thông báo trên là dữ liệu mẫu.'),
    ]);
  }

  Future<void> closeShift() async {
    if (!controller.exited) {
      toast('Hãy điểm danh ra ca trước khi đóng ca');
      return;
    }
    if (controller.closed) {
      toast('Bạn đã gửi báo cáo đóng ca');
      return;
    }
    if (await request('Báo cáo đóng ca') && context.mounted) {
      controller.update(() => controller.closed = true);
      toast('Đã lưu ghi chú mẫu. Chụp ảnh sẽ được tích hợp sau.');
    }
  }
}
