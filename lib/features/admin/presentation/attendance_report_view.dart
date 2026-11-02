import 'package:flutter/material.dart';

import '../../manager/data/attendance_models.dart';
import '../../manager/presentation/attendance_widgets.dart';
import '../data/admin_repository.dart';

/// Attendance report grouped by employee, branch or date over a date range.
class AttendanceReportView extends StatefulWidget {
  const AttendanceReportView({
    super.key,
    required this.repository,
    this.branches = const [],
    this.initialFrom,
    this.initialTo,
  });
  final AdminRepository repository;
  final List<BranchOption> branches;
  final DateTime? initialFrom, initialTo;
  @override
  State<AttendanceReportView> createState() => _AttendanceReportViewState();
}

class _AttendanceReportViewState extends State<AttendanceReportView> {
  late DateTime from =
      widget.initialFrom ?? DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime to = widget.initialTo ?? DateTime.now();
  String groupBy = 'employee';
  int? branchId;
  Future<AttendanceReport>? loading;

  @override
  void initState() {
    super.initState();
    run();
  }

  void run() {
    final next = widget.repository.report(
      from: from,
      to: to,
      groupBy: groupBy,
      branchId: branchId,
    );
    setState(() {
      loading = next;
    });
  }

  Future<void> pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => start ? from = picked : to = picked);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('report-from'),
              onPressed: () => pick(true),
              child: Text('Từ ${dayText(from)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('report-to'),
              onPressed: () => pick(false),
              child: Text('Đến ${dayText(to)}'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        key: const Key('report-group'),
        segments: const [
          ButtonSegment(value: 'employee', label: Text('Nhân viên')),
          ButtonSegment(value: 'branch', label: Text('Chi nhánh')),
          ButtonSegment(value: 'date', label: Text('Ngày')),
        ],
        selected: {groupBy},
        onSelectionChanged: (s) => setState(() => groupBy = s.first),
      ),
      if (widget.branches.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          key: const Key('report-branch'),
          initialValue: branchId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Chi nhánh'),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Tất cả chi nhánh'),
            ),
            for (final b in widget.branches)
              DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
          ],
          onChanged: (v) => branchId = v,
        ),
      ],
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('report-run'),
        onPressed: run,
        child: const Text('Xem báo cáo'),
      ),
      const SizedBox(height: 12),
      FutureBuilder<AttendanceReport>(
        future: loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorText(snapshot.error!),
              onRetry: run,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!.rows;
          if (rows.isEmpty) {
            return const Center(
              key: Key('empty-report'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Không có dữ liệu trong khoảng đã chọn.'),
              ),
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Nhóm')),
                DataColumn(label: Text('Số ca'), numeric: true),
                DataColumn(label: Text('Thành công'), numeric: true),
                DataColumn(label: Text('Đi muộn'), numeric: true),
                DataColumn(label: Text('Thiếu công'), numeric: true),
                DataColumn(label: Text('Ngoại lệ'), numeric: true),
                DataColumn(label: Text('Đã hủy'), numeric: true),
                DataColumn(label: Text('Giờ làm'), numeric: true),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(r.label)),
                      DataCell(Text('${r.totalShifts}')),
                      DataCell(Text('${r.success}')),
                      DataCell(Text('${r.late}')),
                      DataCell(Text('${r.missing}')),
                      DataCell(Text('${r.exceptions}')),
                      DataCell(Text('${r.voided}')),
                      DataCell(Text(hoursText(r.workedMinutes))),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    ],
  );
}
