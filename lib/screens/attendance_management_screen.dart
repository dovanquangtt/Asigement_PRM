import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';

String attendanceTime(Object? value) {
  if (value == null) return 'Chưa ghi nhận';
  final d = utcTime(value).toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String attendanceLabel(Object? state) =>
    const {
      'ON_TIME': 'Đúng giờ',
      'LATE': 'Đi muộn',
      'IN_PROGRESS': 'Đang trong ca',
      'MISSING_CHECK_IN': 'Thiếu giờ vào',
      'MISSING_CHECK_OUT': 'Thiếu giờ ra',
      'PENDING_ADJUSTMENT': 'Chờ sửa công',
      'COMPLETED': 'Đủ giờ vào / ra',
      'NOT_STARTED': 'Chưa vào ca',
      'PENDING': 'Chờ duyệt tăng ca',
      'APPROVED': 'Đã duyệt',
      'REJECTED': 'Đã từ chối',
      'pending': 'Chờ duyệt',
      'approved': 'Đã duyệt',
      'rejected': 'Đã từ chối',
      'pending_review': 'Chờ xử lý ngoại lệ',
      'accepted': 'Đã ghi nhận',
      'NOT_REQUIRED': 'Không cần duyệt',
    }[state] ??
    '$state';

Future<String?> _reviewNote(BuildContext context, String title) async {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Nhận xét / lý do'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Nhập lý do xử lý' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(c, controller.text.trim());
            }
          },
          child: const Text('Xác nhận'),
        ),
      ],
    ),
  );
  // Let the dialog finish its reverse transition before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

class AttendanceManagementScreen extends StatefulWidget {
  const AttendanceManagementScreen({
    super.key,
    required this.repository,
    this.self = false,
  });
  final WorkforceRepository repository;
  final bool self;
  @override
  State<AttendanceManagementScreen> createState() =>
      _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState
    extends State<AttendanceManagementScreen> {
  DateTime day = DateTime.now();
  late Future<RowData> loading;
  String filter = 'all';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    loading = load();
  }

  Future<RowData> load() =>
      widget.repository.attendanceManagement(day: day, self: widget.self);
  Future<void> refresh() async {
    final next = load();
    setState(() => loading = next);
    await next;
  }

  bool needs(RowData r) =>
      r['adjustment_id'] != null ||
      r['overtime_status'] == 'PENDING' ||
      (r['pending_exceptions'] as int) > 0;
  Future<void> open(RowData row) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AttendanceCaseScreen(
          repository: widget.repository,
          assignmentId: row['assignment_id'] as int,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> closeDay() async {
    final note = await _reviewNote(context, 'Chốt bảng công ngày đã chọn?');
    if (note == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.closeAttendanceDay(day, note: note);
      if (mounted) await refresh();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không chốt được bảng công.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget stat(String title, Object? value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.self ? 'Công của tôi' : 'Quản lý chấm công'),
      actions: [
        IconButton(
          tooltip: 'Cập nhật',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<RowData>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: Text(
                snapshot.error is AuthException
                    ? (snapshot.error as AuthException).message
                    : 'Không tải được bảng công. Thử lại',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final all = data['rows'] as List<RowData>;
        final rows = all
            .where(
              (r) =>
                  filter == 'all' ||
                  filter == 'needs' && needs(r) ||
                  filter == 'late' && r['arrival_status'] == 'LATE' ||
                  filter == 'missing' &&
                      [
                        'MISSING_CHECK_IN',
                        'MISSING_CHECK_OUT',
                      ].contains(r['work_state']),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(18),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                widget.self
                    ? 'Theo dõi công, yêu cầu bổ sung và sửa giờ'
                    : 'Điểm danh hợp lệ tự ghi nhận. Chỉ xử lý ngoại lệ.',
                style: const TextStyle(color: Color(0xFF657468)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null && mounted) {
                          day = selected;
                          await refresh();
                        }
                      },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  '${day.day}/${day.month}/${day.year} • Theo ngày bắt đầu ca (VN)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: stat(
                      'Tổng nhân viên',
                      data['employees'],
                      Icons.groups_outlined,
                      const Color(0xFF355C4C),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: stat(
                      'Đã điểm danh',
                      data['checked_in'],
                      Icons.fact_check_outlined,
                      const Color(0xFF286854),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: stat(
                      'Đi muộn',
                      data['late'],
                      Icons.schedule,
                      const Color(0xFF9C6C27),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: stat(
                      'Chờ xử lý',
                      data['pending'],
                      Icons.pending_actions,
                      const Color(0xFFAB583A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: [
                  for (final item in const [
                    ('all', 'Tất cả'),
                    ('needs', 'Cần xử lý'),
                    ('late', 'Đi muộn'),
                    ('missing', 'Thiếu giờ'),
                  ])
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: filter == item.$1,
                      onSelected: (_) => setState(() => filter = item.$1),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Không có dữ liệu phù hợp trong ngày đã chọn.'),
                ),
              for (final row in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      '${row['full_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${row['branch_name']} • ${attendanceTime(row['starts_at'])}\n${attendanceLabel(row['work_state'])}${row['arrival_status'] == 'LATE' ? ' • Muộn ${row['late_minutes']} phút' : ''}${row['adjustment_id'] != null ? '\nChờ bổ sung / sửa công' : ''}${row['overtime_status'] == 'PENDING' ? '\nChờ xác nhận tăng ca' : ''}${(row['pending_exceptions'] as int) > 0 ? '\nCó điểm danh bất thường' : ''}${row['locked_at'] != null ? '\nĐã chốt công' : ''}',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(row),
                  ),
                ),
              if (!widget.self)
                OutlinedButton.icon(
                  onPressed: busy ? null : closeDay,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(busy ? 'Đang chốt…' : 'Chốt bảng công ngày này'),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class AttendanceCaseScreen extends StatefulWidget {
  const AttendanceCaseScreen({
    super.key,
    required this.repository,
    required this.assignmentId,
  });
  final WorkforceRepository repository;
  final int assignmentId;
  @override
  State<AttendanceCaseScreen> createState() => _AttendanceCaseScreenState();
}

class _AttendanceCaseScreenState extends State<AttendanceCaseScreen> {
  late Future<RowData> loading;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    loading = widget.repository.attendanceCaseDetail(widget.assignmentId);
  }

  Future<void> refresh() async {
    final next = widget.repository.attendanceCaseDetail(widget.assignmentId);
    setState(() => loading = next);
    await next;
  }

  Future<void> review(
    String title,
    Future<void> Function(String) action,
  ) async {
    if (busy) return;
    final note = await _reviewNote(context, title);
    if (note == null || !mounted) return;
    setState(() => busy = true);
    try {
      await action(note);
      if (mounted) await refresh();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không xử lý được yêu cầu.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
  Widget line(String name, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text('$name: $value', style: const TextStyle(height: 1.5)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chi tiết chấm công'),
      actions: [
        IconButton(
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<RowData>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: Text(
                snapshot.error is AuthException
                    ? (snapshot.error as AuthException).message
                    : 'Không tải được chi tiết.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!,
            s = data['shift'] as RowData,
            r = data['record'] as RowData?;
        final reviewer = data['can_review'] == true;
        final owner = s['user_id'] == widget.repository.session.userId;
        final events = data['events'] as List<RowData>;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            card('Ca được phân công', [
              line('Nhân viên', s['full_name']),
              line('Chi nhánh', s['branch_name']),
              line('Bắt đầu', attendanceTime(s['starts_at'])),
              line('Kết thúc', attendanceTime(s['ends_at'])),
            ]),
            card('Bảng công hiện tại', [
              line('Giờ vào', attendanceTime(r?['check_in_at'])),
              line('Giờ ra', attendanceTime(r?['check_out_at'])),
              if (r?['arrival_status'] != null)
                line(
                  'Tình trạng vào ca',
                  attendanceLabel(r!['arrival_status']),
                ),
              line(
                'Đi muộn',
                '${r?['late_minutes'] ?? 0} phút — không tự phạt lương',
              ),
              line('Công thực tế', '${r?['worked_minutes'] ?? 0} phút'),
              line('Tăng ca được tính', '${r?['overtime_minutes'] ?? 0} phút'),
              if (r?['overtime_status'] == 'PENDING') ...[
                line(
                  'Tăng ca chờ xác nhận',
                  '${r?['overtime_requested_minutes']} phút',
                ),
                if (reviewer)
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => review(
                                'Duyệt tăng ca',
                                (note) =>
                                    widget.repository.reviewAttendanceOvertime(
                                      widget.assignmentId,
                                      true,
                                      note: note,
                                    ),
                              ),
                        child: const Text('Duyệt tăng ca'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => review(
                                'Từ chối tăng ca',
                                (note) =>
                                    widget.repository.reviewAttendanceOvertime(
                                      widget.assignmentId,
                                      false,
                                      note: note,
                                    ),
                              ),
                        child: const Text('Từ chối tăng ca'),
                      ),
                    ],
                  ),
              ],
              if (r?['overtime_review_note'] != null)
                line('Nhận xét tăng ca', r?['overtime_review_note']),
              if (r?['locked_at'] != null)
                line('Đã chốt', attendanceTime(r?['locked_at'])),
              if (owner && r?['locked_at'] == null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => _AdjustmentDialog(
                                repository: widget.repository,
                                assignmentId: widget.assignmentId,
                                shift: s,
                                record: r,
                              ),
                            );
                            if (mounted) await refresh();
                          },
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Yêu cầu bổ sung / sửa công'),
                  ),
                ),
            ]),
            card('Giờ ghi nhận gốc & kiểm tra cảm biến', [
              if (events.isEmpty)
                const Text(
                  'Chưa có điểm danh gốc. Có thể gửi yêu cầu bổ sung công.',
                ),
              for (final event in events) ...[
                Text(
                  '${event['event_type'] == 'check_in' ? 'Vào ca' : 'Ra ca'} • ${attendanceTime(event['occurred_at'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                line('Trạng thái', attendanceLabel(event['result'])),
                line(
                  'Thiết bị thực tế',
                  event['actual_device_identifier'] ??
                      event['device_id'] ??
                      'Không có',
                ),
                line(
                  'Thiết bị đã chọn',
                  event['selected_device_identifier'] ?? 'Không có',
                ),
                line(
                  'GPS',
                  '${event['latitude'] ?? 'Không có'}, ${event['longitude'] ?? 'Không có'} • ±${event['gps_accuracy_m'] ?? '?'} m',
                ),
                line(
                  'Wi-Fi',
                  '${event['wifi_ssid'] ?? 'Không đọc được'} / ${event['wifi_bssid'] ?? 'Không đọc được'}',
                ),
                if (event['checks_snapshot'] != null)
                  for (final warning
                      in (jsonDecode(event['checks_snapshot'] as String)
                              as Map<String, dynamic>)['warnings']
                          as List)
                    Text(
                      '⚠ $warning',
                      style: const TextStyle(color: Color(0xFFAC5D31)),
                    ),
                if (event['review_note'] != null)
                  line('Nhận xét', event['review_note']),
                if (reviewer && event['result'] == 'pending_review')
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => review(
                                'Duyệt ngoại lệ',
                                (note) => widget.repository.reviewAttendance(
                                  event['id'] as int,
                                  true,
                                  note: note,
                                ),
                              ),
                        child: const Text('Duyệt ngoại lệ'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => review(
                                'Từ chối ngoại lệ',
                                (note) => widget.repository.reviewAttendance(
                                  event['id'] as int,
                                  false,
                                  note: note,
                                ),
                              ),
                        child: const Text('Từ chối'),
                      ),
                    ],
                  ),
                const Divider(height: 24),
              ],
            ]),
            card('Yêu cầu điều chỉnh', [
              if ((data['adjustments'] as List).isEmpty)
                const Text('Chưa có yêu cầu điều chỉnh.'),
              for (final q in data['adjustments'] as List<RowData>) ...[
                Text(
                  '#${q['id']} • ${attendanceLabel(q['status'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (q['before_json'] != null) ...[
                  line(
                    'Giờ vào trước điều chỉnh',
                    attendanceTime(
                      (jsonDecode(q['before_json'] as String)
                          as Map)['check_in_at'],
                    ),
                  ),
                  line(
                    'Giờ ra trước điều chỉnh',
                    attendanceTime(
                      (jsonDecode(q['before_json'] as String)
                          as Map)['check_out_at'],
                    ),
                  ),
                ],
                line(
                  'Đề nghị giờ vào',
                  attendanceTime(q['requested_check_in']),
                ),
                line(
                  'Đề nghị giờ ra',
                  attendanceTime(q['requested_check_out']),
                ),
                line('Lý do', q['reason']),
                if (q['evidence_path'] != null &&
                    File(q['evidence_path'] as String).existsSync())
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(q['evidence_path'] as String),
                      height: 180,
                      fit: BoxFit.contain,
                    ),
                  ),
                if (q['reviewed_by'] != null)
                  line(
                    'Người xử lý',
                    '${q['reviewer_name']} • ${attendanceTime(q['reviewed_at'])}',
                  ),
                if (q['review_note'] != null)
                  line('Nhận xét', q['review_note']),
                if (reviewer && q['status'] == 'pending')
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => review(
                                'Duyệt điều chỉnh',
                                (note) => widget.repository
                                    .reviewAttendanceAdjustment(
                                      q['id'] as int,
                                      true,
                                      note: note,
                                    ),
                              ),
                        child: const Text('Duyệt điều chỉnh'),
                      ),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => review(
                                'Từ chối điều chỉnh',
                                (note) => widget.repository
                                    .reviewAttendanceAdjustment(
                                      q['id'] as int,
                                      false,
                                      note: note,
                                    ),
                              ),
                        child: const Text('Từ chối'),
                      ),
                    ],
                  ),
                const Divider(height: 24),
              ],
            ]),
            card('Lịch sử thao tác', [
              if ((data['audit'] as List).isEmpty)
                const Text('Chưa có thao tác.'),
              for (final a in data['audit'] as List<RowData>)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${a['actor_name'] ?? 'Hệ thống'} • ${a['action']}\n${attendanceTime(a['created_at'])}',
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
            ]),
          ],
        );
      },
    ),
  );
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog({
    required this.repository,
    required this.assignmentId,
    required this.shift,
    this.record,
  });
  final WorkforceRepository repository;
  final int assignmentId;
  final RowData shift;
  final RowData? record;
  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final reason = TextEditingController();
  bool changeIn = true;
  bool changeOut = false;
  @override
  void initState() {
    super.initState();
    changeIn =
        widget.record?['check_in_at'] == null ||
        widget.record?['check_out_at'] != null;
    changeOut =
        widget.record?['check_out_at'] == null &&
        utcTime(widget.shift['ends_at']).isBefore(DateTime.now().toUtc());
    if (!changeIn && !changeOut) changeIn = true;
  }

  late DateTime checkIn = utcTime(
    widget.record?['check_in_at'] ?? widget.shift['starts_at'],
  ).toLocal();
  late DateTime checkOut = utcTime(
    widget.record?['check_out_at'] ?? widget.shift['ends_at'],
  ).toLocal();
  String? photo, error;
  bool busy = false;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> selectTime(bool incoming) async {
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
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (incoming) {
        checkIn = value;
      } else {
        checkOut = value;
      }
    });
  }

  DateTime toUtc(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
  ).toUtc();
  Future<void> attach() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (image == null) return;
      final folder = Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          'attendance_evidence',
        ),
      );
      await folder.create(recursive: true);
      final path = p.join(
        folder.path,
        '${DateTime.now().microsecondsSinceEpoch}${p.extension(image.path)}',
      );
      await image.saveTo(path);
      if (mounted) setState(() => photo = path);
    } catch (_) {
      if (mounted) setState(() => error = 'Không đọc được ảnh minh chứng.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.repository.requestAttendanceAdjustment(
        widget.assignmentId,
        checkIn: changeIn ? toUtc(checkIn) : null,
        checkOut: changeOut ? toUtc(checkOut) : null,
        reason: reason.text,
        evidencePath: photo,
      );
      if (mounted) Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Không gửi được yêu cầu.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Bổ sung / sửa giờ công'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Giờ Việt Nam (UTC+7). Yêu cầu chưa thay đổi bảng công cho đến khi được duyệt.',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bổ sung / sửa giờ vào'),
              value: changeIn,
              onChanged: busy
                  ? null
                  : (value) => setState(() => changeIn = value!),
            ),
            OutlinedButton(
              onPressed: busy || !changeIn ? null : () => selectTime(true),
              child: Text('Vào: ${attendanceTime(sqlTime(toUtc(checkIn)))}'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bổ sung / sửa giờ ra'),
              value: changeOut,
              onChanged: busy
                  ? null
                  : (value) => setState(() => changeOut = value!),
            ),
            OutlinedButton(
              onPressed: busy || !changeOut ? null : () => selectTime(false),
              child: Text('Ra: ${attendanceTime(sqlTime(toUtc(checkOut)))}'),
            ),
            TextField(
              controller: reason,
              maxLines: 3,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Lý do điều chỉnh'),
            ),
            TextButton.icon(
              onPressed: busy ? null : attach,
              icon: const Icon(Icons.attach_file),
              label: Text(
                photo == null ? 'Đính kèm ảnh (nếu cần)' : 'Đã đính kèm ảnh',
              ),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Đang gửi…' : 'Gửi yêu cầu'),
        ),
      ],
    ),
  );
}
