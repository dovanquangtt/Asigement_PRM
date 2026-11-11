import 'package:flutter/material.dart';

import '../data/attendance_models.dart';
import 'attendance_ui.dart';

/// What the employee chose on a success screen; the caller performs the navigation.
enum SuccessNext { history, detail, home }

class _SuccessScaffold extends StatelessWidget {
  const _SuccessScaffold({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.details,
    required this.buttons,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final List<Widget> details, buttons;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.pop(context, SuccessNext.home);
    },
    child: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 12),
            Center(
              child: CircleAvatar(
                radius: 42,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, size: 52, color: color),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(subtitle!, textAlign: TextAlign.center),
              ),
            const SizedBox(height: 20),
            ...details,
            const SizedBox(height: 4),
            ...buttons,
          ],
        ),
      ),
    ),
  );
}

Widget _button(
  BuildContext context,
  String label,
  SuccessNext next, {
  bool primary = false,
}) {
  void go() => Navigator.pop(context, next);
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: primary
        ? FilledButton(onPressed: go, child: Text(label))
        : OutlinedButton(
            onPressed: go,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            child: Text(label),
          ),
  );
}

/// Shown after POST /api/attendance/check-in returned 2xx. Everything displayed is the response.
class CheckInSuccessScreen extends StatelessWidget {
  const CheckInSuccessScreen({super.key, required this.response});
  final AttendanceActionResponse response;

  @override
  Widget build(BuildContext context) {
    final pending = response.pendingReview;
    final color = pending ? Colors.orange.shade800 : Colors.green.shade700;
    return _SuccessScaffold(
      icon: pending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
      color: color,
      title: pending
          ? 'Đã gửi, chờ quản lý xác nhận'
          : 'Chấm công vào thành công',
      subtitle: pending
          ? 'Lần chấm công vào ca được ghi nhận như một ngoại lệ. Quản lý sẽ xem xét và xác nhận.'
          : response.message,
      details: [
        SectionCard(
          children: [
            InfoRow('Nhân viên', response.employee.fullName),
            InfoRow(
              'Giờ vào (máy chủ)',
              fmtDateTime(response.serverTime),
              bold: true,
            ),
            InfoRow('Chi nhánh', response.branchName ?? '—'),
            InfoRow('Ca làm', fmtShift(response.shift)),
            InfoRow(
              'Trạng thái',
              pending ? 'Chờ xác nhận' : stateLabel(response.status),
              bold: true,
            ),
          ],
        ),
        SectionCard(
          title: 'Kết quả xác minh',
          children: [VerificationBlock(response.verification)],
        ),
      ],
      buttons: [
        _button(
          context,
          'Xem lịch sử chấm công',
          SuccessNext.history,
          primary: true,
        ),
        _button(context, 'Quay lại trang chủ', SuccessNext.home),
      ],
    );
  }
}

/// Shown after POST /api/attendance/check-out returned 2xx.
class CheckOutSuccessScreen extends StatelessWidget {
  const CheckOutSuccessScreen({super.key, required this.response});
  final AttendanceActionResponse response;

  @override
  Widget build(BuildContext context) {
    final pending = response.pendingReview;
    final color = pending ? Colors.orange.shade800 : Colors.green.shade700;
    final a = response.attendance;
    final out = a?.checkOutAt ?? response.serverTime;
    final total = (a?.checkInAt != null && out != null)
        ? out.difference(a!.checkInAt!)
        : null;
    return _SuccessScaffold(
      icon: pending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
      color: color,
      title: pending
          ? 'Đã gửi, chờ quản lý xác nhận'
          : 'Chấm công ra thành công',
      subtitle: pending
          ? 'Lần chấm công ra ca được ghi nhận như một ngoại lệ. Quản lý sẽ xem xét và xác nhận.'
          : response.message,
      details: [
        SectionCard(
          children: [
            InfoRow('Nhân viên', response.employee.fullName),
            InfoRow('Giờ vào', fmtDateTime(a?.checkInAt)),
            InfoRow('Giờ ra (máy chủ)', fmtDateTime(out), bold: true),
            InfoRow(
              'Tổng thời gian',
              total == null ? 'Chưa có dữ liệu' : fmtMinutes(total.inMinutes),
            ),
            if (a != null) InfoRow('Giờ nghỉ', fmtMinutes(a.breakMinutes)),
            if (a != null)
              InfoRow(
                'Giờ công tính lương',
                pending ? 'Chờ xác nhận' : fmtMinutes(a.workedMinutes),
                bold: true,
              ),
            InfoRow('Chi nhánh', response.branchName ?? '—'),
            InfoRow('Ca làm', fmtShift(response.shift)),
            InfoRow(
              'Trạng thái',
              pending
                  ? 'Chờ xác nhận'
                  : a != null
                  ? statusLabel(a.status)
                  : stateLabel(response.status),
              bold: true,
            ),
          ],
        ),
        SectionCard(
          title: 'Kết quả xác minh',
          children: [VerificationBlock(response.verification)],
        ),
      ],
      buttons: [
        _button(
          context,
          'Xem chi tiết chấm công',
          SuccessNext.detail,
          primary: true,
        ),
        _button(context, 'Xem lịch sử chấm công', SuccessNext.history),
        _button(context, 'Quay lại trang chủ', SuccessNext.home),
      ],
    );
  }
}
