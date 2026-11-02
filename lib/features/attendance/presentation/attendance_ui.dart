import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/attendance_models.dart';

String two(int n) => n.toString().padLeft(2, '0');

/// HH:mm in the phone's local time (Vietnam time for the target users); "--:--" when missing.
String fmtTime(DateTime? t) {
  if (t == null) return '--:--';
  final d = t.toLocal();
  return '${two(d.hour)}:${two(d.minute)}';
}

String fmtDate(DateTime? t) {
  if (t == null) return '';
  final d = t.toLocal();
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String fmtDateTime(DateTime? t) =>
    t == null ? 'Chưa ghi nhận' : '${fmtDate(t)} ${fmtTime(t)}';

String fmtWeekday(DateTime t) {
  const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  final d = t.toLocal();
  return '${days[d.weekday - 1]} ${two(d.day)}/${two(d.month)}';
}

String fmtMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m phút';
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

String fmtElapsed(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}

String fmtShift(ShiftRef? s) =>
    s == null ? 'Không có ca' : '${fmtTime(s.startsAt)} - ${fmtTime(s.endsAt)}';

const _statusLabels = {
  'SUCCESS': 'Thành công',
  'PENDING_REVIEW': 'Chờ duyệt',
  'REJECTED': 'Bị từ chối',
  'IN_PROGRESS': 'Đang trong ca',
  'MISSING_CHECK_IN': 'Thiếu giờ vào',
  'MISSING_CHECK_OUT': 'Thiếu giờ ra',
  'NOT_STARTED': 'Chưa đến ca',
  'VOIDED': 'Đã hủy công',
};

String statusLabel(String status) => _statusLabels[status] ?? status;

Color statusColor(String status) => switch (status) {
  'SUCCESS' => Colors.green.shade700,
  'PENDING_REVIEW' => Colors.orange.shade800,
  'IN_PROGRESS' => Colors.blue.shade700,
  'REJECTED' ||
  'MISSING_CHECK_IN' ||
  'MISSING_CHECK_OUT' => Colors.red.shade700,
  _ => Colors.grey.shade700,
};

String stateLabel(AttendanceState s) => switch (s) {
  AttendanceState.working => 'Đang làm việc',
  AttendanceState.completed => 'Đã hoàn thành ca',
  AttendanceState.exception => 'Có ngoại lệ cần quản lý xử lý',
  AttendanceState.notCheckedIn => 'Chưa chấm công vào',
  AttendanceState.noShift => 'Hôm nay không có ca làm',
};

Color stateColor(AttendanceState s) => switch (s) {
  AttendanceState.working => Colors.blue.shade700,
  AttendanceState.completed => Colors.green.shade700,
  AttendanceState.exception => Colors.orange.shade800,
  _ => Colors.grey.shade700,
};

String eventTypeLabel(String type) => type == 'CHECK_OUT' ? 'Ra ca' : 'Vào ca';

String eventResultLabel(String result) => switch (result) {
  'ACCEPTED' => 'Đã ghi nhận',
  'PENDING_REVIEW' => 'Chờ quản lý xác nhận',
  'REJECTED' => 'Bị từ chối',
  _ => result,
};

/// Coloured pill, used for statuses and verification results.
class Badge2 extends StatelessWidget {
  const Badge2(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title!,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ...children,
        ],
      ),
    ),
  );
}

String _verifyText(String v) => switch (v) {
  'VERIFIED' => 'Đạt',
  'FAILED' => 'Không đạt',
  _ => 'Chưa có dữ liệu',
};

Color _verifyColor(String v) => switch (v) {
  'VERIFIED' => Colors.green.shade700,
  'FAILED' => Colors.red.shade700,
  _ => Colors.grey.shade700,
};

/// GPS / device / Wi-Fi results straight from the server; never invents a result.
class VerificationBlock extends StatelessWidget {
  const VerificationBlock(this.verification, {super.key});
  final Verification? verification;
  @override
  Widget build(BuildContext context) {
    final v = verification;
    if (v == null) {
      return const Text(
        'Chưa có dữ liệu xác minh',
        style: TextStyle(color: muted),
      );
    }
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 118, child: Text(label, style: const TextStyle(color: muted))),
          Badge2(_verifyText(value), _verifyColor(value)),
        ],
      ),
    );
    final distance = v.distanceMeters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('GPS', v.gps),
        row('Thiết bị', v.device),
        row('Wi-Fi', v.wifi),
        if (distance != null)
          InfoRow(
            'Khoảng cách',
            v.radiusMeters == null
                ? '${distance.round()} m'
                : '${distance.round()} m (cho phép ${v.radiusMeters!.round()} m)',
          ),
        for (final w in v.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(child: Text(w)),
              ],
            ),
          ),
      ],
    );
  }
}
