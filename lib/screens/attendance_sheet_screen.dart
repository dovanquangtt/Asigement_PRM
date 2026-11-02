import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import 'attendance_management_screen.dart';

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

Color sheetStatusColor(String status) => switch (status) {
  'SUCCESS' => Colors.green.shade700,
  'PENDING_REVIEW' => Colors.orange.shade800,
  'IN_PROGRESS' => Colors.blue.shade700,
  'REJECTED' || 'MISSING_CHECK_IN' || 'MISSING_CHECK_OUT' => Colors.red.shade700,
  _ => Colors.grey.shade700,
};

String _clock(Object? value) {
  if (value == null) return '--:--';
  final d = utcTime(value).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _day(Object? value) {
  final d = utcTime(value).toLocal();
  const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return '${weekdays[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

String _hours(Object? minutes) {
  final m = (minutes as int?) ?? 0;
  return '${m ~/ 60}g${(m % 60).toString().padLeft(2, '0')}';
}

/// Bảng điểm danh theo tháng. Nhân viên chỉ xem bảng của mình; quản lý/Admin chọn
/// từng nhân viên để xem, sửa giờ công hoặc hủy công.
class AttendanceSheetScreen extends StatefulWidget {
  const AttendanceSheetScreen({super.key, required this.repository});
  final WorkforceRepository repository;
  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<RowData> employees = const [];
  int? employeeId;
  Future<RowData>? loading;
  String? setupError;
  bool busy = false;

  bool get reviewer =>
      widget.repository.session.permissions.contains('attendance.review');

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      final list = await widget.repository.attendanceSheetEmployees();
      if (!mounted) return;
      setState(() {
        employees = list;
        employeeId = list.isEmpty ? null : list.first['id'] as int;
        loading = employeeId == null ? null : _load();
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => setupError = e.message);
    } catch (_) {
      if (mounted) setState(() => setupError = 'Không tải được danh sách.');
    }
  }

  Future<RowData> _load() => widget.repository.attendanceSheet(
    employeeId: employeeId,
    from: month,
    to: DateTime(month.year, month.month + 1, 0),
  );

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      loading = next;
    });
    await next.then((_) {}, onError: (_) {});
  }

  void _shiftMonth(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    _refresh();
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action, String done) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      _snack(done);
      await _refresh();
    } on AuthException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Không xử lý được yêu cầu.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openDetail(RowData row) => Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AttendanceCaseScreen(
        repository: widget.repository,
        assignmentId: row['assignment_id'] as int,
      ),
    ),
  );

  Future<void> _rowTapped(RowData row) async {
    if (!reviewer) {
      await _openDetail(row);
      return;
    }
    final locked = row['locked_at'] != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${row['full_name']} · ${_day(row['starts_at'])}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${_statusLabels[row['sheet_status']]}'
                '${locked ? ' · đã chốt công' : ''}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Xem chi tiết và minh chứng'),
              onTap: () => Navigator.pop(c, 'detail'),
            ),
            ListTile(
              enabled: !locked,
              leading: const Icon(Icons.edit_outlined),
              title: Text(
                row['sheet_status'] == 'VOIDED'
                    ? 'Khôi phục / nhập lại giờ công'
                    : 'Sửa giờ công',
              ),
              onTap: locked ? null : () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              enabled: !locked && row['sheet_status'] != 'VOIDED',
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text('Hủy công'),
              onTap: locked || row['sheet_status'] == 'VOIDED'
                  ? null
                  : () => Navigator.pop(c, 'void'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'detail':
        await _openDetail(row);
        if (mounted) await _refresh();
      case 'edit':
        final result = await showDialog<_EditResult>(
          context: context,
          builder: (_) => _EditDialog(row: row),
        );
        if (result == null || !mounted) return;
        await _run(
          () => widget.repository.adminEditAttendance(
            row['assignment_id'] as int,
            checkIn: result.checkIn,
            checkOut: result.checkOut,
            reason: result.reason,
          ),
          'Đã chỉnh giờ công.',
        );
      case 'void':
        final reason = await _askReason(
          context,
          'Hủy công ${_day(row['starts_at'])} của ${row['full_name']}?',
        );
        if (reason == null || !mounted) return;
        await _run(
          () => widget.repository.voidAttendance(
            row['assignment_id'] as int,
            reason: reason,
          ),
          'Đã hủy công.',
        );
    }
  }

  Widget _chip(String label, Object? value, Color color) => Chip(
    avatar: CircleAvatar(
      backgroundColor: color,
      child: Text(
        '$value',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
    label: Text(label),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(reviewer ? 'Bảng điểm danh nhân viên' : 'Bảng điểm danh của tôi'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: busy || loading == null ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: setupError != null
        ? Center(child: Text(setupError!))
        : employees.isEmpty
        ? const Center(child: Text('Chưa có nhân viên để hiển thị.'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: busy ? null : () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        'Tháng ${month.month}/${month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              if (reviewer)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<int>(
                    initialValue: employeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Nhân viên'),
                    items: [
                      for (final e in employees)
                        DropdownMenuItem(
                          value: e['id'] as int,
                          child: Text('${e['full_name']} (${e['employee_code']})'),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() => employeeId = value);
                            _refresh();
                          },
                  ),
                ),
              Expanded(
                child: FutureBuilder<RowData>(
                  future: loading,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: TextButton(
                          onPressed: _refresh,
                          child: Text(
                            snapshot.error is AuthException
                                ? (snapshot.error as AuthException).message
                                : 'Không tải được bảng điểm danh. Thử lại.',
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snapshot.data!;
                    final rows = data['rows'] as List<RowData>;
                    final sum = data['summary'] as RowData;
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              _chip('Thành công', sum['success'], Colors.green.shade700),
                              _chip('Chờ duyệt', sum['pending_review'], Colors.orange.shade800),
                              _chip('Bị từ chối', sum['rejected'], Colors.red.shade700),
                              _chip('Thiếu công', sum['missing'], Colors.red.shade400),
                              _chip('Đã hủy', sum['voided'], Colors.grey.shade700),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '${sum['total']} ca · ${_hours(sum['worked_minutes'])} giờ làm · ${sum['late_count']} lần đi muộn',
                            ),
                          ),
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                child: Text('Không có ca làm trong tháng này.'),
                              ),
                            )
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                showCheckboxColumn: false,
                                columns: const [
                                  DataColumn(label: Text('Ngày')),
                                  DataColumn(label: Text('Ca')),
                                  DataColumn(label: Text('Vào')),
                                  DataColumn(label: Text('Ra')),
                                  DataColumn(label: Text('Giờ làm')),
                                  DataColumn(label: Text('Trạng thái')),
                                ],
                                rows: [
                                  for (final r in rows)
                                    DataRow(
                                      onSelectChanged: busy
                                          ? null
                                          : (_) => _rowTapped(r),
                                      cells: [
                                        DataCell(Text(_day(r['starts_at']))),
                                        DataCell(
                                          Text(
                                            '${_clock(r['starts_at'])}-${_clock(r['ends_at'])}',
                                          ),
                                        ),
                                        DataCell(Text(_clock(r['check_in_at']))),
                                        DataCell(Text(_clock(r['check_out_at']))),
                                        DataCell(Text(_hours(r['worked_minutes']))),
                                        DataCell(
                                          Tooltip(
                                            message:
                                                r['sheet_status'] == 'REJECTED'
                                                ? '${r['last_rejection_reason'] ?? ''}'
                                                : '',
                                            child: Text(
                                              _statusLabels[r['sheet_status']] ??
                                                  '${r['sheet_status']}',
                                              style: TextStyle(
                                                color: sheetStatusColor(
                                                  r['sheet_status'] as String,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          if (!reviewer)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Chạm vào một dòng để xem chi tiết. Muốn sửa giờ công, gửi yêu cầu điều chỉnh trong chi tiết ca.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
  );
}

Future<String?> _askReason(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Lý do (bắt buộc)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(c, controller.text.trim());
            }
          },
          child: const Text('Xác nhận'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

class _EditResult {
  const _EditResult(this.checkIn, this.checkOut, this.reason);
  final DateTime? checkIn, checkOut;
  final String reason;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.row});
  final RowData row;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final reason = TextEditingController();
  late DateTime checkIn = utcTime(
    widget.row['check_in_at'] ?? widget.row['starts_at'],
  ).toLocal();
  late DateTime checkOut = utcTime(
    widget.row['check_out_at'] ?? widget.row['ends_at'],
  ).toLocal();
  String? error;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool incoming) async {
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

  String _label(DateTime value) => attendanceTime(sqlTime(value.toUtc()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sửa giờ công'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.row['full_name']} · ${_day(widget.row['starts_at'])}. Giờ Việt Nam (UTC+7). Thay đổi có hiệu lực ngay và được ghi lại.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _pick(true),
            child: Text('Vào: ${_label(checkIn)}'),
          ),
          OutlinedButton(
            onPressed: () => _pick(false),
            child: Text('Ra: ${_label(checkOut)}'),
          ),
          TextField(
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
