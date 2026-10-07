import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../state/workspace_controller.dart';
import '../services/workspace_actions.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.actions,
  });
  final WorkspaceController controller;
  final WorkspaceActions actions;
  @override
  Widget build(BuildContext context) => page([
    heading('Không gian cá nhân', 'HỒ SƠ CỦA BẠN'),
    panel(
      child: Column(
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: Color(0xFFDCEFE4),
            child: Text(
              'LH',
              style: TextStyle(
                fontSize: 24,
                color: green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nguyễn Linh',
            style: TextStyle(
              fontSize: 23,
              color: ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'NV001 • ${controller.role}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          pill('Đang làm việc'),
        ],
      ),
    ),
    section('Thông tin & tiện ích'),
    panel(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined, color: green),
            title: const Text('Hồ sơ nhân viên'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => actions.detail('Hồ sơ nhân viên', [
              ('Họ tên', 'Nguyễn Linh'),
              ('Mã nhân viên', 'NV001'),
              ('Bộ phận', 'Phục vụ'),
              ('Chi nhánh', 'Trung tâm'),
              ('Ngày vào làm', '01/06/2026'),
              ('Email', 'linh@example.com'),
            ]),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: green),
            title: const Text('Hợp đồng lao động'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => actions.detail('Hợp đồng lao động', [
              ('Mã hợp đồng', 'HĐ001'),
              ('Loại', 'Có thời hạn'),
              ('Hiệu lực', '01/06/2026 — 31/05/2027'),
              ('Lương cơ bản', '10.000.000 ₫'),
            ]),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.beach_access_outlined, color: green),
            title: const Text('Nghỉ phép'),
            subtitle: const Text('Còn 8 ngày • dữ liệu mẫu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => actions.request('Xin nghỉ phép'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inbox_outlined, color: green),
            title: const Text('Yêu cầu đã gửi'),
            subtitle: Text('${controller.requests.length} yêu cầu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: actions.requestList,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined, color: green),
            title: const Text('Thông báo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: actions.notifications,
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    OutlinedButton.icon(
      onPressed: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      ),
      icon: const Icon(Icons.logout),
      label: const Text('Đăng xuất'),
    ),
    const SizedBox(height: 20),
    const Text(
      'Mộc • Phiên bản trải nghiệm 1.0\nDữ liệu chỉ lưu trong phiên sử dụng.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.7),
    ),
  ]);
}
