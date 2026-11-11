import 'package:flutter/material.dart';

import '../../../widgets/review_note_dialog.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../manager/data/attendance_repository.dart';
import '../data/schedule_repository.dart';
import '../../../widgets/employee_shift_row_card.dart';

/// Bảng toàn bộ ca của từng nhân viên (API): chọn nhân viên, xem mọi ca được phân,
/// việc họ chấp nhận / từ chối và giờ chấm công. Dành cho quản lý / Admin.
class EmployeeShiftTableScreen extends StatefulWidget {
  const EmployeeShiftTableScreen({super.key, this.client});
  final ApiClient? client;
  @override
  State<EmployeeShiftTableScreen> createState() =>
      _EmployeeShiftTableScreenState();
}

class _EmployeeShiftTableScreenState extends State<EmployeeShiftTableScreen> {
  late final ScheduleRepository repo = ScheduleRepository(
    widget.client ?? ApiClient.instance,
  );
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> employees = const [];
  int? employeeId;
  Future<Map<String, dynamic>>? loading;
  String? setupError;
  bool setupDone = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  String _message(Object e, String fallback) => e is ApiException
      ? (e.status == 403
            ? 'Không có quyền xem bảng ca. ${e.message}'
            : e.message)
      : fallback;

  Future<void> _setup() async {
    try {
      final list = await repo.employees();
      if (!mounted) return;
      setState(() {
        employees = list;
        setupDone = true;
        setupError = null;
        employeeId = list.isEmpty ? null : (list.first['id'] as num).toInt();
        loading = employeeId == null ? null : _load();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        setupError = _message(e, 'Không tải được danh sách nhân viên.');
      });
    }
  }

  Future<Map<String, dynamic>> _load() => repo.employeeShifts(
    employeeId!,
    from: month,
    to: DateTime(month.year, month.month + 1, 0),
  );

  /// Hỏi lý do rồi duyệt/từ chối một lượt điểm danh đang chờ; từ chối bắt buộc có lý do.
  Future<void> _review(int eventId, bool approve, String label) async {
    final note = await askReviewNote(context, approve: approve, label: label);
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ManagerAttendanceRepository(widget.client ?? ApiClient.instance)
          .reviewException(eventId, approve: approve, note: note);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Đã duyệt điểm danh $label.'
                : 'Đã từ chối điểm danh $label.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Không xử lý được. Hãy thử lại.')),
      );
    }
    if (mounted) _refresh();
  }

  void _refresh() {
    final next = _load();
    setState(() {
      loading = next;
    });
  }

  void _shiftMonth(int delta) {
    month = DateTime(month.year, month.month + delta);
    _refresh();
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

  Widget _body() {
    if (setupError != null) {
      return Center(
        child: TextButton(onPressed: _setup, child: Text(setupError!)),
      );
    }
    if (!setupDone) return const Center(child: CircularProgressIndicator());
    if (employees.isEmpty) {
      return const Center(child: Text('Chưa có nhân viên đang làm việc.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              IconButton(
                key: const Key('table-prev-month'),
                onPressed: () => _shiftMonth(-1),
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
                key: const Key('table-next-month'),
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<int>(
            key: const Key('table-employee'),
            initialValue: employeeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nhân viên'),
            items: [
              for (final e in employees)
                DropdownMenuItem(
                  value: (e['id'] as num).toInt(),
                  child: Text(
                    '${e['full_name']} (${e['employee_code']}) · ${e['branch_name']}',
                  ),
                ),
            ],
            onChanged: (value) {
              employeeId = value;
              _refresh();
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: _refresh,
                    child: Text(
                      _message(
                        snapshot.error!,
                        'Không tải được bảng ca. Thử lại.',
                      ),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
              final sum = Map<String, dynamic>.from(data['summary'] as Map);
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('Tổng ca', sum['total'], Colors.blueGrey),
                      _chip(
                        'Chờ xác nhận',
                        sum['pending'],
                        shiftResponseColor('pending'),
                      ),
                      _chip(
                        'Đã chấp nhận',
                        sum['accepted'],
                        shiftResponseColor('accepted'),
                      ),
                      _chip(
                        'Đã từ chối',
                        sum['rejected'],
                        shiftResponseColor('rejected'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Nhân viên chưa có ca nào trong tháng này.',
                        ),
                      ),
                    )
                  else ...[
                    for (final r in rows)
                      EmployeeShiftRowCard(
                        key: ValueKey('shift-row-${r['assignment_id']}'),
                        row: r,
                        parseTime: (v) => DateTime.parse('$v'),
                        onReview: _review,
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bảng ca theo nhân viên')),
    body: _body(),
  );
}
