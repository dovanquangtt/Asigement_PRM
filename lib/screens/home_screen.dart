import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../state/workspace_controller.dart';
import '../services/workspace_actions.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.actions,
  });
  final WorkspaceController controller;
  final WorkspaceActions actions;
  @override
  Widget build(BuildContext context) => page([
    Row(
      children: [
        const BrandMark(),
        const SizedBox(width: 10),
        const Text(
          'mộc',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: actions.notifications,
          tooltip: 'Thông báo',
          icon: Badge(
            isLabelVisible: !controller.notificationsRead,
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => controller.update(() => controller.tab = 3),
          child: const CircleAvatar(
            backgroundColor: Color(0xFFE0EBD4),
            child: Text(
              'LH',
              style: TextStyle(
                color: green,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 28),
    const Text(
      'Chào Linh',
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
    ),
    const SizedBox(height: 5),
    const Text(
      'Sẵn sàng cho một ngày thật tốt?',
      style: TextStyle(color: muted, fontSize: 13),
    ),
    const SizedBox(height: 22),
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF245B49), Color(0xFF153D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: .16),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -65,
            top: -70,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .04),
                  width: 35,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CA LÀM HÔM NAY',
                        style: TextStyle(
                          color: Color(0xFFC1D7C7),
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    pill(
                      controller.exited
                          ? 'Hoàn thành'
                          : controller.entered
                          ? 'Trong ca'
                          : 'Sắp bắt đầu',
                      dark: true,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '08:00',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              letterSpacing: -1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'BẮT ĐẦU',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF9ABAA9),
                        size: 23,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '16:00',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              letterSpacing: -1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'KẾT THÚC',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFF496D5E), height: 1),
                const SizedBox(height: 15),
                const Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: Color(0xFFC1D7C7),
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Trung tâm • Phục vụ • Ca sáng',
                        style: TextStyle(
                          color: Color(0xFFC1D7C7),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Icon(Icons.wb_sunny_outlined, color: lime, size: 18),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: lime,
                      foregroundColor: ink,
                      disabledBackgroundColor: const Color(0xFF4B6D59),
                      disabledForegroundColor: Colors.white70,
                    ),
                    onPressed: controller.exited ? null : actions.attendance,
                    icon: Icon(
                      controller.entered
                          ? Icons.logout_rounded
                          : Icons.fingerprint,
                      size: 22,
                    ),
                    label: Text(
                      controller.exited
                          ? 'Đã kết thúc ca'
                          : controller.entered
                          ? 'Điểm danh ra ca'
                          : 'Điểm danh vào ca',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (controller.enteredAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Vào ca lúc ' +
                          actions.clock(controller.enteredAt!) +
                          ' • dữ liệu mẫu',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(child: metric('Công tháng này', '18', 'ngày', Icons.schedule)),
        const SizedBox(width: 12),
        Expanded(
          child: metric(
            'Sao tích lũy',
            '${controller.stars}',
            'ngôi sao',
            Icons.star_outline_rounded,
          ),
        ),
      ],
    ),
    section('Thao tác nhanh'),
    Row(
      children: [
        Expanded(
          child: quick(
            Icons.event_available_outlined,
            'Xin nghỉ phép',
            () => actions.request('Xin nghỉ phép'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: quick(
            Icons.swap_horiz,
            'Đổi ca',
            () => actions.request('Đổi ca'),
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: quick(
            Icons.edit_calendar_outlined,
            'Điều chỉnh công',
            () => actions.request('Điều chỉnh công'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: quick(Icons.task_alt, 'Đóng ca', actions.closeShift)),
      ],
    ),
    section('Kiểm tra điểm danh'),
    panel(
      child: const Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_android, color: green),
            title: Text('Thiết bị Pixel'),
            subtitle: Text('Mô phỏng thiết bị'),
          ),
          Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.my_location, color: green),
            title: Text('Vị trí nhà hàng'),
            subtitle: Text('Chưa xác thực GPS thực tế'),
          ),
          Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.wifi, color: green),
            title: Text('Wi-Fi nhà hàng'),
            subtitle: Text('Chưa xác thực mạng thực tế'),
          ),
        ],
      ),
    ),
    if (controller.manager) ...[
      section(
        controller.role == 'Admin' ? 'Quản trị hệ thống' : 'Không gian quản lý',
      ),
      panel(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: green),
              title: const Text('Nhân viên trong ca'),
              subtitle: const Text('4 nhân viên • ca sáng'),
              trailing: const Icon(Icons.chevron_right),
              onTap: actions.roster,
            ),
            ListTile(
              leading: const Icon(Icons.approval_outlined, color: green),
              title: const Text('Yêu cầu đã gửi'),
              subtitle: Text('${controller.requests.length} yêu cầu mẫu'),
              trailing: const Icon(Icons.chevron_right),
              onTap: actions.requestList,
            ),
            ListTile(
              leading: const Icon(Icons.star_outline, color: green),
              title: const Text('Tặng sao cho Linh'),
              onTap: () {
                controller.update(() => controller.stars++);
                actions.toast('Đã tặng 1 sao mẫu');
              },
            ),
            if (controller.role == 'Admin')
              ListTile(
                leading: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: green,
                ),
                title: const Text('Tài khoản và phân quyền'),
                onTap: () => actions.detail('Phân quyền', [
                  ('Admin', 'Quản trị hệ thống'),
                  ('Manager', 'Quản lý nghiệp vụ'),
                  ('Employee', 'Dữ liệu cá nhân'),
                ]),
              ),
          ],
        ),
      ),
    ],
    const SizedBox(height: 24),
    const Text(
      'DỮ LIỆU TRẢI NGHIỆM • CHƯA ĐỒNG BỘ',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.black45),
    ),
  ]);
}
