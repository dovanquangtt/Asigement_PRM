import 'package:flutter/material.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../data/schedule_repository.dart';
import 'employee_shift_table_screen.dart';

const _assignedNote =
    'Nhân viên chỉ thấy ca sau khi được phân công và sẽ nhận thông báo.';

/// Vietnam wall-clock time (UTC+7) of a backend timestamp, independent of the device zone.
DateTime vnTime(Object? iso) =>
    DateTime.parse('$iso').toUtc().add(const Duration(hours: 7));

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
String _dm(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

String scheduleError(
  Object e, {
  String fallback = 'Không xử lý được yêu cầu. Thử lại.',
}) {
  if (e is ApiException) {
    return e.status == 403 ? 'Không có quyền phân ca.' : e.message;
  }
  return fallback;
}

/// "Phân ca" for managers and admins: list the week's shifts, create a shift and assign staff.
class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key, this.client});
  final ApiClient? client;
  @override
  State<ScheduleManagementScreen> createState() =>
      _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  late final ScheduleRepository repo = ScheduleRepository(
    widget.client ?? ApiClient.instance,
  );
  late Future<
    ({List<Map<String, dynamic>> branches, List<Map<String, dynamic>> shifts})
  >
  loading = _load();
  int? branchId;
  late DateTime weekStart = _monday(
    vnTime(DateTime.now().toUtc().toIso8601String()),
  );
  bool busy = false;

  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  Future<
    ({List<Map<String, dynamic>> branches, List<Map<String, dynamic>> shifts})
  >
  _load() async {
    final branches = await repo.branches();
    final shifts = await repo.overview(branchId: branchId);
    return (branches: branches, shifts: shifts);
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      loading = next;
    });
    await next.then((_) {}, onError: (_) {});
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _moveWeek(int weeks) {
    setState(() {
      weekStart = weekStart.add(Duration(days: 7 * weeks));
    });
  }

  Future<void> _create(List<Map<String, dynamic>> branches) async {
    if (busy) return;
    if (branches.isEmpty) {
      _snack('Cần tạo chi nhánh trước khi phân ca.');
      return;
    }
    final input = await showDialog<_NewShift>(
      context: context,
      builder: (_) => _CreateShiftDialog(
        branches: branches,
        initialBranchId: branchId ?? (branches.first['id'] as num).toInt(),
        initialDate: weekStart,
      ),
    );
    if (input == null || !mounted) return;
    setState(() {
      busy = true;
    });
    int? id;
    try {
      id = await repo.createShift(
        branchId: input.branchId,
        start: input.start,
        end: input.end,
        requiredStaff: input.requiredStaff,
        note: input.note,
      );
    } catch (e) {
      if (mounted)
        _snack(scheduleError(e, fallback: 'Không tạo được ca làm. Thử lại.'));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
    if (id == null || !mounted) return;
    _snack('Đã tạo ca. Hãy chọn nhân viên. $_assignedNote');
    await _reload();
    if (!mounted) return;
    await _openAssign(
      id,
      '${_dm(vnTime(input.start))} ${_hm(vnTime(input.start))}–${_hm(vnTime(input.end))}',
    );
  }

  Future<void> _openAssign(int shiftId, String title) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          AssignShiftSheet(repo: repo, shiftId: shiftId, title: title),
    );
    if (mounted) await _reload();
  }

  Future<void> _cancel(Map<String, dynamic> shift) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa ca làm?'),
        content: const Text(
          'Ca sẽ bị xóa. Nhân viên đã được phân vào ca sẽ nhận thông báo và ca biến mất khỏi lịch của họ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa ca'),
          ),
        ],
      ),
    );
    if (ok != true || busy || !mounted) return;
    setState(() {
      busy = true;
    });
    try {
      await repo.cancelShift((shift['id'] as num).toInt());
      if (mounted) _snack('Đã xóa ca. Nhân viên trong ca đã được thông báo.');
      await _reload();
    } catch (e) {
      if (mounted) _snack(scheduleError(e));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: loading,
    builder: (context, snapshot) {
      final data = snapshot.data;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Phân ca'),
          actions: [
            IconButton(
              key: const Key('open-shift-table'),
              tooltip: 'Bảng ca nhân viên',
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      EmployeeShiftTableScreen(client: widget.client),
                ),
              ),
              icon: const Icon(Icons.table_chart_outlined),
            ),
            IconButton(
              tooltip: 'Tải lại',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: data == null
            ? null
            : FloatingActionButton.extended(
                key: const Key('create-shift-fab'),
                onPressed: busy ? null : () => _create(data.branches),
                icon: const Icon(Icons.add),
                label: const Text('Tạo ca'),
              ),
        body: snapshot.hasError
            ? Center(
                child: TextButton(
                  onPressed: _reload,
                  child: Text(
                    scheduleError(
                      snapshot.error!,
                      fallback: 'Không tải được lịch ca. Thử lại.',
                    ),
                  ),
                ),
              )
            : data == null
            ? const Center(child: CircularProgressIndicator())
            : _body(data.branches, data.shifts),
      );
    },
  );

  Widget _body(
    List<Map<String, dynamic>> branches,
    List<Map<String, dynamic>> all,
  ) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final shifts =
        all.where((s) {
          if (s['status'] == 'cancelled') return false; // ca đã xóa
          final d = vnTime(s['starts_at']);
          return !d.isBefore(weekStart) && d.isBefore(weekEnd);
        }).toList()..sort(
          (a, b) => vnTime(a['starts_at']).compareTo(vnTime(b['starts_at'])),
        );
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          DropdownButtonFormField<int?>(
            key: const Key('branch-filter'),
            initialValue: branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chi nhánh'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Tất cả chi nhánh'),
              ),
              for (final b in branches)
                DropdownMenuItem<int?>(
                  value: (b['id'] as num).toInt(),
                  child: Text('${b['name']}'),
                ),
            ],
            onChanged: busy
                ? null
                : (value) {
                    setState(() {
                      branchId = value;
                    });
                    _reload();
                  },
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _moveWeek(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'Tuần ${_dm(weekStart)} – ${_dm(weekStart.add(const Duration(days: 6)))}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => _moveWeek(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (shifts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Chưa có ca nào trong tuần này.\nBấm "Tạo ca" để thêm ca và phân nhân viên.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          for (final s in shifts) _shiftCard(s),
        ],
      ),
    );
  }

  Widget _shiftCard(Map<String, dynamic> s) {
    final start = vnTime(s['starts_at']), end = vnTime(s['ends_at']);
    final id = (s['id'] as num).toInt();
    final cancelled = s['status'] == 'cancelled';
    final names = '${s['assigned_staff_names'] ?? ''}';
    final title = '${_dm(start)} ${_hm(start)}–${_hm(end)}';
    return Card(
      child: Column(
        children: [
          _shiftTile(s, id, cancelled, names, title, start, end),
          if (!cancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: Key('delete-shift-$id'),
                  onPressed: busy ? null : () => _cancel(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Xóa ca làm'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shiftTile(
    Map<String, dynamic> s,
    int id,
    bool cancelled,
    String names,
    String title,
    DateTime start,
    DateTime end,
  ) {
    return ListTile(
        key: Key('shift-$id'),
        leading: Icon(cancelled ? Icons.event_busy : Icons.schedule),
        title: Text(
          '$title${cancelled ? '  (đã hủy)' : ''}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${s['branch_name']} · ${s['assigned_count']}/${s['required_staff']} nhân viên'
          '${names.isEmpty ? ' · chưa phân ai' : '\n$names'}',
        ),
        isThreeLine: names.isNotEmpty,
        onTap: cancelled || busy ? null : () => _openAssign(id, title),
        trailing: cancelled
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) =>
                    v == 'cancel' ? _cancel(s) : _openAssign(id, title),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'assign', child: Text('Phân nhân viên')),
                  PopupMenuItem(value: 'cancel', child: Text('Xóa ca')),
                ],
              ),
    );
  }
}

class _NewShift {
  const _NewShift(
    this.branchId,
    this.start,
    this.end,
    this.requiredStaff,
    this.note,
  );
  final int branchId;
  final DateTime start, end;
  final int requiredStaff;
  final String note;
}

class _CreateShiftDialog extends StatefulWidget {
  const _CreateShiftDialog({
    required this.branches,
    required this.initialBranchId,
    required this.initialDate,
  });
  final List<Map<String, dynamic>> branches;
  final int initialBranchId;
  final DateTime initialDate;
  @override
  State<_CreateShiftDialog> createState() => _CreateShiftDialogState();
}

class _CreateShiftDialogState extends State<_CreateShiftDialog> {
  late int branch = widget.initialBranchId;
  late DateTime date = widget.initialDate;
  TimeOfDay from = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay to = const TimeOfDay(hour: 16, minute: 0);
  final staff = TextEditingController(text: '1');
  final note = TextEditingController();
  String? error;

  @override
  void dispose() {
    staff.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        date = picked;
      });
    }
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? from : to,
    );
    if (picked != null) {
      setState(() {
        if (start) {
          from = picked;
        } else {
          to = picked;
        }
      });
    }
  }

  void _submit() {
    final count = int.tryParse(staff.text.trim());
    if (count == null || count < 1) {
      setState(() => error = 'Số nhân viên phải lớn hơn 0.');
      return;
    }
    // Wall-clock times are Vietnam time (UTC+7).
    DateTime utc(TimeOfDay t) => DateTime.utc(
      date.year,
      date.month,
      date.day,
      t.hour,
      t.minute,
    ).subtract(const Duration(hours: 7));
    final start = utc(from), end = utc(to);
    if (!end.isAfter(start)) {
      setState(() => error = 'Giờ kết thúc phải sau giờ bắt đầu.');
      return;
    }
    Navigator.pop(
      context,
      _NewShift(branch, start, end, count, note.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tạo ca làm'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            initialValue: branch,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chi nhánh'),
            items: [
              for (final b in widget.branches)
                DropdownMenuItem(
                  value: (b['id'] as num).toInt(),
                  child: Text('${b['name']}'),
                ),
            ],
            onChanged: (v) => setState(() => branch = v ?? branch),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _pickDate,
            child: Text(
              'Ngày: ${_two(date.day)}/${_two(date.month)}/${date.year}',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(true),
                  child: Text('Từ ${_two(from.hour)}:${_two(from.minute)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(false),
                  child: Text('Đến ${_two(to.hour)}:${_two(to.minute)}'),
                ),
              ),
            ],
          ),
          const Text('Giờ Việt Nam (UTC+7).', style: TextStyle(fontSize: 12)),
          TextField(
            key: const Key('required-staff'),
            controller: staff,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Số nhân viên cần'),
          ),
          TextField(
            controller: note,
            decoration: const InputDecoration(
              labelText: 'Ghi chú (không bắt buộc)',
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        key: const Key('submit-shift'),
        onPressed: _submit,
        child: const Text('Tạo ca'),
      ),
    ],
  );
}

/// Bottom sheet listing the branch's employees for one shift: assign or remove people.
class AssignShiftSheet extends StatefulWidget {
  const AssignShiftSheet({
    super.key,
    required this.repo,
    required this.shiftId,
    required this.title,
  });
  final ScheduleRepository repo;
  final int shiftId;
  final String title;
  @override
  State<AssignShiftSheet> createState() => _AssignShiftSheetState();
}

class _AssignShiftSheetState extends State<AssignShiftSheet> {
  late Future<List<Map<String, dynamic>>> loading = widget.repo
      .eligibleEmployees(widget.shiftId);
  String query = '';
  bool busy = false;

  Future<void> _reload() async {
    final next = widget.repo.eligibleEmployees(widget.shiftId);
    setState(() {
      loading = next;
    });
    await next.then((_) {}, onError: (_) {});
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(scheduleError(e))));
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            ListTile(
              title: Text(
                'Phân nhân viên · ${widget.title}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(_assignedNote),
              trailing: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Xong'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('employee-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Tìm nhân viên',
                ),
                onChanged: (v) =>
                    setState(() => query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: loading,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: _reload,
                        child: Text(
                          scheduleError(
                            snapshot.error!,
                            fallback:
                                'Không tải được danh sách nhân viên. Thử lại.',
                          ),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final all = snapshot.data!;
                  if (all.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Chi nhánh này chưa có nhân viên đang làm việc.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final rows = all
                      .where(
                        (e) =>
                            query.isEmpty ||
                            '${e['full_name']} ${e['employee_code']}'
                                .toLowerCase()
                                .contains(query),
                      )
                      .toList();
                  if (rows.isEmpty)
                    return const Center(
                      child: Text('Không tìm thấy nhân viên.'),
                    );
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _row(rows[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(Map<String, dynamic> e) {
    final id = (e['id'] as num).toInt();
    final assigned = e['is_already_assigned'] == true;
    final available = e['is_available'] == true;
    final reason = e['conflict_reason'] as String?;
    return ListTile(
      key: Key('employee-$id'),
      title: Text('${e['full_name']} (${e['employee_code']})'),
      subtitle: Text(
        assigned
            ? 'Đã phân vào ca này'
            : (available ? 'Có thể phân ca' : (reason ?? 'Không thể phân ca')),
        style: TextStyle(
          color: assigned || available
              ? Colors.green.shade800
              : Colors.red.shade700,
        ),
      ),
      trailing: assigned
          ? TextButton(
              key: Key('unassign-$id'),
              onPressed: busy
                  ? null
                  : () => _run(
                      () => widget.repo.unassign(widget.shiftId, id),
                      'Đã gỡ nhân viên khỏi ca.',
                    ),
              child: const Text('Gỡ'),
            )
          : FilledButton(
              key: Key('assign-$id'),
              onPressed: busy || !available
                  ? null
                  : () => _run(
                      () => widget.repo.assign(widget.shiftId, id),
                      'Đã phân ca. Nhân viên được thông báo và sẽ thấy ca này.',
                    ),
              child: const Text('Phân ca'),
            ),
    );
  }
}
