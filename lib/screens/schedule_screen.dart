import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../state/workspace_controller.dart';
import '../services/workspace_actions.dart';
import '../widgets/common_widgets.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({
    super.key,
    required this.controller,
    required this.actions,
  });
  final WorkspaceController controller;
  final WorkspaceActions actions;
  @override
  Widget build(BuildContext context) => page([
    heading('Lịch làm của bạn', 'SẮP XẾP MỘT TUẦN THẬT TỐT'),
    const Text(
      '05 — 11 tháng 10, 2026 • tuần mẫu',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 20),
    Row(
      children: List.generate(
        7,
        (i) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: controller.selectedDay == i ? green : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () =>
                    controller.update(() => controller.selectedDay = i),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i],
                        style: TextStyle(
                          fontSize: 11,
                          color: controller.selectedDay == i
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${5 + i}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: controller.selectedDay == i
                              ? Colors.white
                              : ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    section('Ca ngày ${5 + controller.selectedDay}/10'),
    if (controller.selectedDay == 6)
      panel(
        child: const Column(
          children: [
            Icon(Icons.weekend_outlined, size: 48, color: green),
            SizedBox(height: 12),
            Text('Hôm nay bạn được nghỉ'),
            SizedBox(height: 6),
            Text(
              'Dành một chút thời gian cho bản thân.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      )
    else
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny_outlined, color: Color(0xFFB48031)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ca sáng',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                pill('Đã phân ca'),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              '08:00 — 16:00',
              style: TextStyle(
                fontSize: 26,
                color: ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Phục vụ • Khu vực tầng 1\nNghỉ giữa ca: 30 phút',
              style: TextStyle(color: Colors.black54, height: 1.7),
            ),
            const Divider(height: 30),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cùng ca với 3 đồng nghiệp',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(onPressed: actions.roster, child: const Text('Xem')),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => actions.request(
                  'Đổi ca ngày ${5 + controller.selectedDay}/10',
                ),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Yêu cầu đổi ca'),
              ),
            ),
          ],
        ),
      ),
    section('Yêu cầu của bạn'),
    if (controller.requests.isEmpty)
      panel(
        child: const Text(
          'Chưa có yêu cầu trong phiên này.',
          style: TextStyle(color: Colors.black54),
        ),
      )
    else
      ...controller.requests.map(
        (r) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r),
                const SizedBox(height: 10),
                pill('Chờ duyệt'),
              ],
            ),
          ),
        ),
      ),
    const SizedBox(height: 20),
    OutlinedButton.icon(
      onPressed: () => actions.request('Xin nghỉ phép'),
      icon: const Icon(Icons.add),
      label: const Text('Tạo yêu cầu nghỉ phép'),
    ),
    if (controller.manager)
      FilledButton.icon(
        onPressed: () => actions.request('Phân ca mới'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Tạo phân ca mẫu'),
      ),
  ]);
}
