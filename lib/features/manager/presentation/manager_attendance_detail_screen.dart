import 'package:flutter/material.dart';

import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';
import 'attendance_widgets.dart';

/// Attendance detail for managers/admins. The action buttons (edit, void, review an exception)
/// only appear after the detail loaded from the reviewer endpoint, and [canEdit] can switch
/// them off for read-only use.
class ManagerAttendanceDetailScreen extends StatefulWidget {
  const ManagerAttendanceDetailScreen({
    super.key,
    required this.repository,
    required this.attendanceId,
    this.canEdit = true,
  });
  final ManagerAttendanceRepository repository;
  final int attendanceId;
  final bool canEdit;
  @override
  State<ManagerAttendanceDetailScreen> createState() =>
      _ManagerAttendanceDetailScreenState();
}

class _ManagerAttendanceDetailScreenState
    extends State<ManagerAttendanceDetailScreen> {
  late Future<AttendanceDetail> loading = widget.repository.detail(
    widget.attendanceId,
  );
  bool busy = false;

  Future<void> refresh() async {
    final next = widget.repository.detail(widget.attendanceId);
    setState(() {
      loading = next;
    });
    await next.then((_) {}, onError: (_) {});
  }

  Future<void> run(Future<void> Function() action, String done) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      showSnack(context, done);
      await refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(AttendanceDetail d) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(detail: d),
    );
    if (result == null) return;
    await run(
      () => widget.repository.editTimes(
        d.shift.assignmentId,
        checkIn: result.checkIn,
        checkOut: result.checkOut,
        reason: result.reason,
      ),
      'Đã chỉnh giờ công.',
    );
  }

  Future<void> voidIt(AttendanceDetail d) async {
    final reason = await askReason(
      context,
      'Hủy công ca ${dayText(d.shift.startsAt)} của ${d.employee.fullName}?',
    );
    if (reason == null) return;
    await run(
      () => widget.repository.voidAttendance(
        d.shift.assignmentId,
        reason: reason,
      ),
      'Đã hủy công.',
    );
  }

  Future<void> review(AttendanceEvent e, bool approve) async {
    final note = await askReason(
      context,
      approve ? 'Duyệt điểm danh ngoại lệ?' : 'Từ chối điểm danh ngoại lệ?',
      label: 'Nhận xét (bắt buộc)',
    );
    if (note == null) return;
    await run(
      () => widget.repository.reviewException(
        e.eventId,
        approve: approve,
        note: note,
      ),
      approve ? 'Đã duyệt.' : 'Đã từ chối.',
    );
  }

  Widget section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label: $value'),
  );

  Widget verificationBlock(Verification v) => Wrap(
    spacing: 8,
    children: [
      VerificationDot('GPS', v.gps),
      VerificationDot('Thiết bị', v.device),
      VerificationDot('Wi-Fi', v.wifi),
    ],
  );

  String distance(double? meters, double? radius) => meters == null
      ? 'Chưa có dữ liệu'
      : '${meters.round()} m${radius == null ? '' : ' (cho phép ${radius.round()} m)'}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chi tiết chấm công'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<AttendanceDetail>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorRetry(
            message: errorText(snapshot.error!),
            onRetry: refresh,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snapshot.data!;
        final a = d.attendance;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            section('Nhân viên', [
              line('Họ tên', d.employee.fullName),
              line('Mã', d.employee.employeeCode),
              line('Chức vụ', d.employee.position ?? 'Chưa có'),
              line('Chi nhánh', d.shift.branchName ?? d.employee.branchName ?? ''),
            ]),
            section('Ca và giờ công', [
              line(
                'Ca',
                '${dayText(d.shift.startsAt)} ${clock(d.shift.startsAt)}-${clock(d.shift.endsAt)}',
              ),
              line('Giờ vào', dateTimeText(a.checkInAt)),
              line('Giờ ra', dateTimeText(a.checkOutAt)),
              Row(children: [const Text('Trạng thái: '), StatusText(a.status)]),
              line('Đi muộn', '${a.lateMinutes} phút'),
              line('Giờ làm', hoursText(a.workedMinutes)),
              line('Nghỉ giữa ca', '${a.breakMinutes} phút'),
              line('Tăng ca', '${a.overtimeMinutes} phút'),
            ]),
            section('Xác minh', [
              verificationBlock(d.verification),
              line(
                'Khoảng cách tới chi nhánh',
                distance(
                  d.verification.distanceMeters,
                  d.verification.radiusMeters,
                ),
              ),
              for (final w in d.verification.warnings)
                Text('⚠ $w', style: TextStyle(color: Colors.orange.shade900)),
            ]),
            if (d.exceptions.isNotEmpty)
              section('Ngoại lệ', [for (final e in d.exceptions) Text('• $e')]),
            section('Các lần điểm danh', [
              if (d.events.isEmpty) const Text('Chưa có lần điểm danh nào.'),
              for (final e in d.events) ...[
                Text(
                  '${e.type == 'CHECK_IN' ? 'Vào ca' : 'Ra ca'} · '
                  '${dateTimeText(e.occurredAt)} · ${statusEvent(e.result)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (e.latitude != null)
                  Text(
                    'Tọa độ ${e.latitude!.toStringAsFixed(5)}, ${e.longitude?.toStringAsFixed(5)}'
                    '${e.accuracyMeters == null ? '' : ' · sai số ${e.accuracyMeters!.round()} m'}'
                    ' · ${distance(e.distanceMeters, e.verification.radiusMeters)}',
                  ),
                verificationBlock(e.verification),
                if (e.rejectionReason != null)
                  Text('Lý do: ${e.rejectionReason}'),
                if (widget.canEdit && e.pending)
                  Row(
                    children: [
                      TextButton(
                        key: Key('approve-${e.eventId}'),
                        onPressed: busy ? null : () => review(e, true),
                        child: const Text('Duyệt'),
                      ),
                      TextButton(
                        key: Key('reject-${e.eventId}'),
                        onPressed: busy ? null : () => review(e, false),
                        child: const Text('Từ chối'),
                      ),
                    ],
                  ),
                const Divider(),
              ],
            ]),
            if (d.auditLog.isNotEmpty)
              section('Lịch sử xử lý', [
                for (final l in d.auditLog)
                  Text(
                    '${dateTimeText(l.at)} · ${l.actorName ?? 'Hệ thống'} · ${l.action}'
                    '${l.detail == null ? '' : '\n${l.detail}'}',
                  ),
              ]),
            if (widget.canEdit)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('edit-times'),
                    onPressed: busy ? null : () => edit(d),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(d.voided ? 'Khôi phục / nhập lại giờ' : 'Sửa giờ công'),
                  ),
                  if (!d.voided)
                    OutlinedButton.icon(
                      key: const Key('void-attendance'),
                      onPressed: busy ? null : () => voidIt(d),
                      icon: const Icon(Icons.block, color: Colors.red),
                      label: const Text('Hủy công'),
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );

  String statusEvent(String result) => switch (result) {
    'ACCEPTED' => 'Đã ghi nhận',
    'PENDING_REVIEW' => 'Chờ duyệt',
    'REJECTED' => 'Bị từ chối',
    _ => result,
  };
}

class _EditResult {
  const _EditResult(this.checkIn, this.checkOut, this.reason);
  final DateTime checkIn, checkOut;
  final String reason;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.detail});
  final AttendanceDetail detail;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final reason = TextEditingController();
  late DateTime checkIn = (widget.detail.attendance.checkInAt ??
          widget.detail.shift.startsAt)
      .toLocal();
  late DateTime checkOut = (widget.detail.attendance.checkOutAt ??
          widget.detail.shift.endsAt)
      .toLocal();
  String? error;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pick(bool incoming) async {
    final old = incoming ? checkIn : checkOut;
    final date = await showDatePicker(
      context: context,
      initialDate: old,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old),
    );
    if (time == null || !mounted) return;
    final value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => incoming ? checkIn = value : checkOut = value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sửa giờ công'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.detail.employee.fullName} · ${dayText(widget.detail.shift.startsAt)}. '
            'Thay đổi có hiệu lực ngay và được ghi lại.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => pick(true),
            child: Text('Vào: ${dateTimeText(checkIn)}'),
          ),
          OutlinedButton(
            onPressed: () => pick(false),
            child: Text('Ra: ${dateTimeText(checkOut)}'),
          ),
          TextField(
            key: const Key('edit-reason'),
            controller: reason,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Lý do (bắt buộc)'),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
      FilledButton(
        key: const Key('edit-save'),
        onPressed: () {
          if (reason.text.trim().isEmpty) {
            setState(() => error = 'Nhập lý do chỉnh công.');
          } else if (checkOut.isBefore(checkIn)) {
            setState(() => error = 'Giờ ra phải từ giờ vào trở đi.');
          } else {
            Navigator.pop(
              context,
              _EditResult(checkIn.toUtc(), checkOut.toUtc(), reason.text.trim()),
            );
          }
        },
        child: const Text('Lưu'),
      ),
    ],
  );
}
