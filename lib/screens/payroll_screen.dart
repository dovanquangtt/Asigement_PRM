import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../state/workspace_controller.dart';
import '../services/workspace_actions.dart';
import '../widgets/common_widgets.dart';

class PayrollScreen extends StatelessWidget {
  const PayrollScreen({
    super.key,
    required this.controller,
    required this.actions,
  });
  final WorkspaceController controller;
  final WorkspaceActions actions;
  @override
  Widget build(BuildContext context) => page([
    heading('Thu nhập', 'MỖI ĐÓNG GÓP ĐỀU ĐƯỢC GHI NHẬN'),
    Row(
      children: [
        const Text('Kỳ lương', style: TextStyle(color: Colors.black54)),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButton<int>(
            isExpanded: true,
            style: const TextStyle(fontSize: 15, color: ink),
            value: controller.month,
            underline: const SizedBox(),
            items: [9, 10]
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text('Tháng $m / 2026'),
                  ),
                )
                .toList(),
            onChanged: (v) => controller.update(() => controller.month = v!),
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: green,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.month == 10 ? 'THU NHẬP DỰ KIẾN' : 'THU NHẬP THỰC NHẬN',
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            child: Text(
              controller.month == 10 ? '10.600.000 ₫' : '10.200.000 ₫',
              style: const TextStyle(
                fontSize: 31,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          pill(
            controller.month == 10
                ? 'Tạm tính • dữ liệu mẫu'
                : 'Đã trả • dữ liệu mẫu',
            dark: true,
          ),
        ],
      ),
    ),
    section('Chi tiết bảng lương'),
    panel(
      child: Column(
        children: [
          money('Lương cơ bản', '10.000.000 ₫'),
          money(
            'Lương tăng ca',
            controller.month == 10 ? '+500.000 ₫' : '+100.000 ₫',
          ),
          money('Phụ cấp', '+200.000 ₫'),
          money('Khấu trừ', '−100.000 ₫'),
          const Divider(height: 28),
          money(
            'Thực nhận',
            controller.month == 10 ? '10.600.000 ₫' : '10.200.000 ₫',
            bold: true,
          ),
        ],
      ),
    ),
    section('Tổng hợp công'),
    Row(
      children: [
        Expanded(
          child: metric('Công được tính', '18', 'ngày', Icons.event_available),
        ),
        const SizedBox(width: 12),
        Expanded(child: metric('Tăng ca', '5', 'giờ', Icons.more_time)),
      ],
    ),
    const SizedBox(height: 20),
    OutlinedButton.icon(
      onPressed: () => actions.detail('Phiếu lương tháng ${controller.month}', [
        ('Nhân viên', 'Nguyễn Linh • NV001'),
        ('Hợp đồng', 'HĐ001 • Toàn thời gian'),
        ('Kỳ lương', 'Tháng ${controller.month}/2026'),
        ('Trạng thái', controller.month == 10 ? 'Tạm tính' : 'Đã thanh toán'),
        ('Dữ liệu', 'Phiếu mẫu, chưa lấy từ MySQL'),
      ]),
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Mở phiếu lương'),
    ),
    if (controller.manager) ...[
      section('Thao tác quản lý lương'),
      FilledButton.icon(
        onPressed: () => actions.request('Yêu cầu tính lương'),
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Tạo yêu cầu tính lương mẫu'),
      ),
    ],
  ]);
}
