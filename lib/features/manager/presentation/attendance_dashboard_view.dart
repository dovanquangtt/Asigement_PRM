import 'package:flutter/material.dart';

import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';
import 'attendance_widgets.dart';
import 'manager_attendance_detail_screen.dart';

/// Summary cards + filterable, paged attendance list shared by the manager and admin dashboards.
class AttendanceDashboardView extends StatefulWidget {
  const AttendanceDashboardView({
    super.key,
    required this.repository,
    this.branches = const [],
    this.initialDate,
  });
  final ManagerAttendanceRepository repository;

  /// Admin only: enables the branch filter.
  final List<BranchOption> branches;
  final DateTime? initialDate;
  @override
  State<AttendanceDashboardView> createState() =>
      _AttendanceDashboardViewState();
}

class _AttendanceDashboardViewState extends State<AttendanceDashboardView> {
  late DateTime date = widget.initialDate ?? DateTime.now();
  int? branchId, shiftId;
  String? status;
  bool onlyExceptions = false;
  final search = TextEditingController();

  AttendanceSummary? summary;
  String? summaryError, listError;
  final rows = <AttendanceRow>[];
  int page = 0;
  bool hasNext = false, loadingSummary = true, loadingList = true;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    final gen = ++generation;
    setState(() {
      loadingSummary = true;
      loadingList = true;
      summaryError = listError = null;
      rows.clear();
      page = 0;
    });
    await Future.wait([_loadSummary(gen), _loadPage(gen, 0)]);
  }

  Future<void> _loadSummary(int gen) async {
    try {
      final s = await widget.repository.summary(date: date, branchId: branchId);
      if (mounted && gen == generation) {
        setState(() {
          summary = s;
          loadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted && gen == generation) {
        setState(() {
          summaryError = errorText(e);
          loadingSummary = false;
        });
      }
    }
  }

  Future<void> _loadPage(int gen, int next) async {
    try {
      final result = onlyExceptions
          ? await widget.repository.exceptions(
              date: date,
              branchId: branchId,
              page: next,
            )
          : await widget.repository.list(
              date: date,
              branchId: branchId,
              shiftId: shiftId,
              status: status,
              q: search.text,
              page: next,
            );
      if (mounted && gen == generation) {
        setState(() {
          rows.addAll(result.items);
          page = result.page;
          hasNext = result.hasNext;
          loadingList = false;
        });
      }
    } catch (e) {
      if (mounted && gen == generation) {
        setState(() {
          listError = errorText(e);
          loadingList = false;
        });
      }
    }
  }

  Future<void> loadMore() async {
    if (loadingList || !hasNext) return;
    setState(() => loadingList = true);
    await _loadPage(generation, page + 1);
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    date = picked;
    shiftId = null;
    await reload();
  }

  Future<void> shiftDay(int delta) async {
    date = date.add(Duration(days: delta));
    shiftId = null;
    await reload();
  }

  Future<void> open(AttendanceRow row) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ManagerAttendanceDetailScreen(
          repository: widget.repository,
          attendanceId: row.attendanceId,
        ),
      ),
    );
    if (mounted) await reload();
  }

  Widget card(String key, String label, int? value, Color color) => SizedBox(
    width: 104,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${value ?? '-'}',
              key: Key('summary-$key'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );

  Widget summaryView() {
    if (summaryError != null) {
      return ErrorRetry(message: summaryError!, onRetry: reload);
    }
    if (loadingSummary) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final s = summary!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (s.totalBranches != null)
          card('totalBranches', 'Chi nhánh', s.totalBranches, Colors.teal),
        if (s.totalShifts != null)
          card('totalShifts', 'Ca trong ngày', s.totalShifts, Colors.teal),
        card('totalEmployees', 'Nhân viên', s.totalEmployees, Colors.black87),
        card('checkedIn', 'Đã vào ca', s.checkedIn, Colors.green.shade700),
        card('working', 'Đang làm', s.working, Colors.blue.shade700),
        card('completed', 'Hoàn thành', s.completed, Colors.green.shade900),
        card('late', 'Đi muộn', s.late, Colors.orange.shade800),
        card('notCheckedIn', 'Chưa vào ca', s.notCheckedIn, Colors.red.shade700),
        card('exceptions', 'Ngoại lệ', s.exceptions, Colors.deepOrange),
      ],
    );
  }

  List<ShiftRef> get shiftOptions {
    final seen = <int, ShiftRef>{};
    for (final r in rows) {
      seen.putIfAbsent(r.shift.shiftId, () => r.shift);
    }
    return seen.values.toList();
  }

  Widget filters() => Column(
    children: [
      Row(
        children: [
          IconButton(
            tooltip: 'Ngày trước',
            onPressed: () => shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('date-picker'),
              onPressed: pickDate,
              icon: const Icon(Icons.event),
              label: Text(dayText(date)),
            ),
          ),
          IconButton(
            tooltip: 'Ngày sau',
            onPressed: () => shiftDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      if (widget.branches.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DropdownButtonFormField<int?>(
            key: const Key('branch-filter'),
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
            onChanged: (v) {
              branchId = v;
              shiftId = null;
              reload();
            },
          ),
        ),
      const SizedBox(height: 8),
      Row(
        children: [
          ChoiceChip(
            key: const Key('tab-all'),
            label: const Text('Tất cả'),
            selected: !onlyExceptions,
            onSelected: (_) {
              onlyExceptions = false;
              reload();
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const Key('tab-exceptions'),
            label: const Text('Ngoại lệ'),
            selected: onlyExceptions,
            onSelected: (_) {
              onlyExceptions = true;
              reload();
            },
          ),
        ],
      ),
      if (!onlyExceptions) ...[
        const SizedBox(height: 8),
        TextField(
          key: const Key('search-field'),
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Tìm tên hoặc mã nhân viên',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Tìm',
              onPressed: reload,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          onSubmitted: (_) => reload(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: const Key('status-filter'),
                initialValue: status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả'),
                  ),
                  for (final e in sheetStatusLabels.entries)
                    DropdownMenuItem<String?>(
                      value: e.key,
                      child: Text(e.value),
                    ),
                ],
                onChanged: (v) {
                  status = v;
                  reload();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int?>(
                // Rebuilt when the selection is reset (date/branch change).
                key: ValueKey('shift-filter-$shiftId-${shiftOptions.length}'),
                initialValue: shiftOptions.any((s) => s.shiftId == shiftId)
                    ? shiftId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ca'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tất cả ca'),
                  ),
                  for (final s in shiftOptions)
                    DropdownMenuItem<int?>(
                      value: s.shiftId,
                      child: Text('${clock(s.startsAt)}-${clock(s.endsAt)}'),
                    ),
                ],
                onChanged: (v) {
                  shiftId = v;
                  reload();
                },
              ),
            ),
          ],
        ),
      ],
    ],
  );

  Widget rowTile(AttendanceRow r) => Card(
    child: ListTile(
      key: Key('row-${r.attendanceId}'),
      onTap: () => open(r),
      title: Text('${r.employee.fullName} (${r.employee.employeeCode})'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${r.employee.position ?? 'Nhân viên'} · '
              'Ca ${clock(r.shift.startsAt)}-${clock(r.shift.endsAt)}',
            ),
            Text('Vào ${clock(r.checkInAt)} · Ra ${clock(r.checkOutAt)}'),
            StatusText(r.status),
            if (r.late)
              Text(
                'Muộn ${r.lateMinutes}p',
                style: TextStyle(color: Colors.orange.shade800),
              ),
            VerificationDot('GPS', r.gps),
            VerificationDot('Thiết bị', r.device),
            if (r.reason != null)
              Text(r.reason!, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
  );

  Widget listView() {
    if (listError != null) {
      return ErrorRetry(message: listError!, onRetry: reload);
    }
    if (rows.isEmpty && loadingList) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          key: Key('empty-list'),
          child: Text('Không có dữ liệu chấm công phù hợp.'),
        ),
      );
    }
    return Column(
      children: [
        for (final r in rows) rowTile(r),
        if (hasNext)
          Padding(
            padding: const EdgeInsets.all(8),
            child: loadingList
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    key: const Key('load-more'),
                    onPressed: loadMore,
                    child: const Text('Tải thêm'),
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [filters(), const SizedBox(height: 12), summaryView(), const SizedBox(height: 12), listView()],
    ),
  );
}
