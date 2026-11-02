import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';

const _responseLabels = {
  'pending': 'Chờ xác nhận',
  'accepted': 'Đã chấp nhận',
  'rejected': 'Đã từ chối',
};

Color _responseColor(String status) => switch (status) {
  'accepted' => Colors.green.shade700,
  'rejected' => Colors.red.shade700,
  _ => Colors.orange.shade800,
};

String _dayText(Object? value) {
  final d = utcTime(value).toLocal();
  const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return '${names[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

String _clockText(Object? value) {
  if (value == null) return '--:--';
  final d = utcTime(value).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Bảng toàn bộ ca làm của từng nhân viên: chọn một nhân viên để xem mọi ca được phân,
/// trạng thái họ đã chấp nhận hay từ chối, và giờ chấm công. Dành cho quản lý / Admin.
class EmployeeShiftTableScreen extends StatefulWidget {
  const EmployeeShiftTableScreen({super.key, required this.repository});
  final WorkforceRepository repository;
  @override
  State<EmployeeShiftTableScreen> createState() =>
      _EmployeeShiftTableScreenState();
}

class _EmployeeShiftTableScreenState extends State<EmployeeShiftTableScreen> {
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<RowData> employees = const [];
  int? employeeId;
  Future<RowData>? loading;
  String? setupError;

  @override
  void initState() {
    super.initState();
    _setup();
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

  Future<RowData> _load() => widget.repository.employeeShiftTable(
    employeeId!,
    from: month,
    to: DateTime(month.year, month.month + 1, 0),
  );

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bảng ca theo nhân viên'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: loading == null ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: setupError != null
        ? Center(child: Text(setupError!))
        : employees.isEmpty
        ? const Center(child: Text('Chưa có nhân viên đang làm việc.'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
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
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
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
                child: FutureBuilder<RowData>(
                  future: loading,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final e = snapshot.error;
                      return Center(
                        child: TextButton(
                          onPressed: _refresh,
                          child: Text(
                            e is AuthException
                                ? e.message
                                : 'Không tải được bảng ca. Thử lại.',
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
                              _responseColor('pending'),
                            ),
                            _chip(
                              'Đã chấp nhận',
                              sum['accepted'],
                              _responseColor('accepted'),
                            ),
                            _chip(
                              'Đã từ chối',
                              sum['rejected'],
                              _responseColor('rejected'),
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
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Ngày')),
                                DataColumn(label: Text('Ca')),
                                DataColumn(label: Text('Chi nhánh')),
                                DataColumn(label: Text('Phản hồi')),
                                DataColumn(label: Text('Vào')),
                                DataColumn(label: Text('Ra')),
                                DataColumn(label: Text('Ghi chú')),
                              ],
                              rows: [
                                for (final r in rows)
                                  DataRow(
                                    cells: [
                                      DataCell(Text(_dayText(r['starts_at']))),
                                      DataCell(
                                        Text(
                                          '${_clockText(r['starts_at'])}-${_clockText(r['ends_at'])}',
                                        ),
                                      ),
                                      DataCell(Text('${r['branch_name']}')),
                                      DataCell(
                                        Text(
                                          _responseLabels[r['response_status']] ??
                                              '${r['response_status']}',
                                          style: TextStyle(
                                            color: _responseColor(
                                              '${r['response_status']}',
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_clockText(r['check_in_at'])),
                                      ),
                                      DataCell(
                                        Text(_clockText(r['check_out_at'])),
                                      ),
                                      DataCell(
                                        Text(
                                          r['response_status'] == 'rejected'
                                              ? 'Lý do: ${r['response_note'] ?? ''}'
                                              : 'Phân bởi ${r['assigned_by_name'] ?? ''}',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
  );
}
