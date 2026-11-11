import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';

/// M12 Dashboard cho quản lý/Admin: thống kê theo tháng về nhân sự, ca làm, điểm danh,
/// nghỉ phép, giờ làm và lương. Quản lý chỉ thấy chi nhánh của mình.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository});
  final WorkforceRepository repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<RowData> loading = _load();

  Future<RowData> _load() => widget.repository.dashboardSummary(
    from: month,
    to: DateTime(month.year, month.month + 1, 0),
  );

  void _shift(int delta) {
    month = DateTime(month.year, month.month + delta);
    final next = _load();
    setState(() {
      loading = next;
    });
  }

  static String hours(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h giờ' : '$h giờ $m phút';
  }

  static String days(int minutes) =>
      (minutes / 480).toStringAsFixed(minutes % 480 == 0 ? 0 : 1);

  static String vnd(int amount) =>
      '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫';

  Widget _card(String title, IconData icon, List<(String, String)> rows) =>
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE6EAE8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: green),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in rows) money(r.$1, r.$2),
            ],
          ),
        ),
      );

  Widget _body(RowData d) {
    final e = d['employees'] as RowData;
    final s = d['shifts'] as RowData;
    final a = d['attendance'] as RowData;
    final l = d['leave'] as RowData;
    final h = d['hours'] as RowData;
    final p = d['payroll'] as RowData;
    int i(Object? v) => (v as num?)?.toInt() ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card('Nhân sự', Icons.groups_outlined, [
          ('Nhân viên đang làm', '${i(e['active'])}'),
          ('Có tài khoản đăng nhập', '${i(e['with_account'])}'),
        ]),
        _card('Ca làm', Icons.calendar_month_outlined, [
          ('Tổng số ca', '${i(s['total'])}'),
          ('Chưa bắt đầu', '${i(s['scheduled'])}'),
          ('Đang diễn ra', '${i(s['in_progress'])}'),
          ('Đã đóng', '${i(s['closed'])}'),
          ('Đã hủy', '${i(s['cancelled'])}'),
          ('Lượt phân ca', '${i(s['assignments'])}'),
          ('Ca còn thiếu người', '${i(s['understaffed'])}'),
        ]),
        _card('Điểm danh', Icons.fingerprint, [
          ('Bảng công', '${i(a['records'])}'),
          ('Đúng giờ', '${i(a['on_time'])}'),
          ('Đi muộn', '${i(a['late'])}'),
          ('Chưa ra ca', '${i(a['missing_check_out'])}'),
          ('Ngoại lệ chờ duyệt', '${i(a['pending_exceptions'])}'),
        ]),
        _card('Nghỉ phép', Icons.beach_access_outlined, [
          ('Chờ duyệt', '${i(l['pending'])}'),
          ('Đã duyệt', '${i(l['approved'])}'),
          ('Từ chối', '${i(l['rejected'])}'),
          ('Số ngày đã duyệt', days(i(l['approved_minutes']))),
        ]),
        _card('Giờ làm', Icons.schedule, [
          ('Tổng giờ làm', hours(i(h['worked_minutes']))),
          ('Tăng ca', hours(i(h['overtime_minutes']))),
          ('Đi muộn', hours(i(h['late_minutes']))),
        ]),
        _card('Lương', Icons.account_balance_wallet_outlined, [
          ('Phiếu lương', '${i(p['payslips'])}'),
          ('Nháp / Đã duyệt / Đã trả',
              '${i(p['draft'])} / ${i(p['approved'])} / ${i(p['paid'])}'),
          ('Tổng lương (cơ bản + tăng ca)', vnd(i(p['gross_vnd']))),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dashboard thống kê')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              IconButton(
                key: const Key('dashboard-prev'),
                onPressed: () => _shift(-1),
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
                key: const Key('dashboard-next'),
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
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
                    onPressed: () => _shift(0),
                    child: Text(
                      e is AuthException
                          ? e.message
                          : 'Không tải được thống kê. Thử lại.',
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return _body(snapshot.data!);
            },
          ),
        ),
      ],
    ),
  );
}
