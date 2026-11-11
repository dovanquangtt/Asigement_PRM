import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/attendance_outcome.dart';
import '../widgets/shift_timeline.dart';

String _hm(Object? utc) {
  if (utc == null) return '--:--';
  final d = utcTime(utc).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Dòng giải thích kết quả, để nhân viên biết vì sao bị đánh dấu X.
String attendanceNote(RowData shift, ShiftPhase phase) => switch (phase) {
  ShiftPhase.completed =>
    'Vào ${_hm(shift['check_in_at'])} • Ra ${_hm(shift['check_out_at'])}',
  ShiftPhase.missingCheckOut =>
    'Có giờ vào ${_hm(shift['check_in_at'])} nhưng thiếu giờ ra',
  ShiftPhase.absent =>
    ((shift['rejected_events'] as num?)?.toInt() ?? 0) > 0
        ? 'Điểm danh bị từ chối'
        : 'Không điểm danh',
  ShiftPhase.voided => 'Công đã bị hủy',
  ShiftPhase.pendingReview => 'Đang chờ quản lý duyệt',
  ShiftPhase.working => 'Đang trong ca (vào ${_hm(shift['check_in_at'])})',
  ShiftPhase.notYet => 'Chưa tới giờ điểm danh',
};

/// Lịch sử điểm danh theo tháng, mỗi ca một thẻ: ✓ xanh nếu điểm danh thành công, ✗ đỏ nếu
/// không điểm danh hoặc điểm danh lỗi. Nhân viên xem của mình; quản lý/Admin chọn nhân viên.
class EmployeeAttendanceHistoryScreen extends StatefulWidget {
  const EmployeeAttendanceHistoryScreen({
    super.key,
    required this.repository,
    this.initialMonth,
    this.now,
  });
  final WorkforceRepository repository;

  /// Tháng hiển thị ban đầu (mặc định tháng hiện tại).
  final DateTime? initialMonth;

  /// Chỉ để kiểm thử; mặc định là giờ hiện tại.
  final DateTime? now;

  @override
  State<EmployeeAttendanceHistoryScreen> createState() =>
      _EmployeeAttendanceHistoryScreenState();
}

class _EmployeeAttendanceHistoryScreenState
    extends State<EmployeeAttendanceHistoryScreen> {
  late DateTime month = () {
    final m = widget.initialMonth ?? DateTime.now();
    return DateTime(m.year, m.month);
  }();
  bool get _reviewer => widget.repository.session.role != 'Nhân viên';
  List<RowData> employees = const [];
  int? employeeId;
  Future<List<RowData>>? loading;
  String? setupError;

  @override
  void initState() {
    super.initState();
    if (_reviewer) {
      _setup();
    } else {
      loading = _load();
    }
  }

  Future<void> _setup() async {
    try {
      final list = await widget.repository.shiftTableEmployees();
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

  Future<List<RowData>> _load() =>
      widget.repository.employeeSchedule(employeeId: employeeId);

  void _reload() {
    final next = _load();
    setState(() {
      loading = next;
    });
  }

  void _moveMonth(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
    });
  }

  Widget _count(String label, int n, Color color, {Key? key}) => Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 38,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$n',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: Colors.black54,
        ),
      ),
    ],
  );

  Widget _card(RowData shift, DateTime now) {
    final phase = shiftPhase(shift, now.toUtc());
    final outcome = attendanceOutcome(phase);
    final color = outcomeColor(outcome);
    final start = utcTime(shift['starts_at']).toLocal();
    final end = utcTime(shift['ends_at']).toLocal();
    final id = shift['assignment_id'];
    final date =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}';
    return Container(
      key: Key('history-row-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ngày: $date',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ca: ${shiftTitleOf(start)} '
                      '(${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'
                      '–${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')})',
                      style: const TextStyle(color: ink),
                    ),
                    Text(
                      'Chi nhánh: ${shift['branch_name']}',
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      attendanceNote(shift, phase),
                      key: Key('history-note-$id'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: outcome == AttendanceOutcome.present
                            ? muted
                            : color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  key: Key('history-icon-$id'),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    outcomeIcon(outcome),
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<RowData> all) {
    final now = widget.now ?? DateTime.now();
    final shifts = [
      for (final s in all)
        if (_inMonth(utcTime(s['starts_at']).toLocal())) s,
    ]..sort((a, b) => '${a['starts_at']}'.compareTo('${b['starts_at']}'));
    final counts = {for (final o in AttendanceOutcome.values) o: 0};
    for (final s in shifts) {
      final o = attendanceOutcome(shiftPhase(s, now.toUtc()));
      counts[o] = counts[o]! + 1;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _count(
                'Có mặt',
                counts[AttendanceOutcome.present]!,
                markPresent,
                key: const Key('history-count-present'),
              ),
              _count(
                'Vắng',
                counts[AttendanceOutcome.absent]!,
                markAbsent,
                key: const Key('history-count-absent'),
              ),
              if (counts[AttendanceOutcome.pending]! > 0)
                _count(
                  'Chờ duyệt',
                  counts[AttendanceOutcome.pending]!,
                  markPending,
                  key: const Key('history-count-pending'),
                ),
              _count(
                'Sắp tới',
                counts[AttendanceOutcome.future]!,
                markFuture,
                key: const Key('history-count-future'),
              ),
            ],
          ),
        ),
        if (shifts.isEmpty)
          Container(
            key: const Key('history-empty'),
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: const Text('Không có ca nào trong tháng này.'),
          )
        else
          for (final s in shifts) _card(s, now),
      ],
    );
  }

  bool _inMonth(DateTime d) => d.year == month.year && d.month == month.month;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF1F8F7),
    appBar: AppBar(
      title: const Text('Lịch sử điểm danh'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: loading == null ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: setupError != null
        ? Center(child: Text(setupError!))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('history-prev-month'),
                      onPressed: () => _moveMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        'Tháng ${month.month}/${month.year}',
                        key: const Key('history-month'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('history-next-month'),
                      onPressed: () => _moveMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              if (_reviewer && employees.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: DropdownButtonFormField<int>(
                    key: const Key('history-employee'),
                    initialValue: employeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Nhân viên'),
                    items: [
                      for (final e in employees)
                        DropdownMenuItem(
                          value: e['id'] as int,
                          child: Text(
                            '${e['full_name']} (${e['employee_code']}) · ${e['branch_name']}',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      employeeId = v;
                      _reload();
                    },
                  ),
                ),
              Expanded(
                child: _reviewer && employees.isEmpty && loading == null
                    ? const Center(
                        child: Text('Chưa có nhân viên đang làm việc.'),
                      )
                    : FutureBuilder<List<RowData>>(
                        future: loading,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            final e = snapshot.error;
                            return Center(
                              child: TextButton(
                                onPressed: _reload,
                                child: Text(
                                  e is AuthException
                                      ? e.message
                                      : 'Không tải được lịch sử. Thử lại.',
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _body(snapshot.data!);
                        },
                      ),
              ),
            ],
          ),
  );
}
