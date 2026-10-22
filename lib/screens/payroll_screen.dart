import 'package:flutter/material.dart';

import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';

class EmployeePayrollScreen extends StatefulWidget {
  const EmployeePayrollScreen({
    super.key,
    required this.payslips,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<RowData> payslips;
  final Future<void> Function() onRefresh;
  final ValueChanged<RowData> onOpen;

  @override
  State<EmployeePayrollScreen> createState() => _EmployeePayrollScreenState();
}

class _EmployeePayrollScreenState extends State<EmployeePayrollScreen> {
  String filter = 'all';

  static const filters = [
    ('all', 'Tất cả'),
    ('draft', 'Bản nháp'),
    ('approved', 'Đã duyệt'),
    ('paid', 'Đã thanh toán'),
  ];

  List<RowData> get visiblePayslips => widget.payslips
      .where((row) => filter == 'all' || row['status'] == filter)
      .toList();

  String money(Object? value) {
    final digits = (value as num?)?.toInt().toString() ?? '0';
    return '${digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫';
  }

  String statusLabel(Object? status) => switch (status) {
    'paid' => 'Đã thanh toán',
    'approved' => 'Đã duyệt',
    _ => 'Bản nháp',
  };

  Color statusColor(Object? status) => switch (status) {
    'paid' => const Color(0xFF286B4F),
    'approved' => const Color(0xFF9A641B),
    _ => const Color(0xFF596B74),
  };

  String periodLabel(RowData row) {
    final start = DateTime.tryParse('${row['starts_on'] ?? ''}');
    final end = DateTime.tryParse('${row['ends_on'] ?? ''}');
    if (start == null || end == null) {
      return '${row['period_code'] ?? 'Kỳ lương'}';
    }
    String date(DateTime value) =>
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    return '${date(start)} - ${date(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final payslips = widget.payslips;
    final latest = payslips.isEmpty ? null : payslips.first;
    final paidCount = payslips.where((row) => row['status'] == 'paid').length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          heading('Bảng lương của tôi', 'THU NHẬP CÁ NHÂN'),
          if (latest != null) ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: green,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFFDCEFAD),
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'PHIẾU LƯƠNG GẦN NHẤT',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _StatusTag(
                        label: statusLabel(latest['status']),
                        color: Colors.white,
                        background: Colors.white.withValues(alpha: .14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    periodLabel(latest),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Thực lĩnh',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      money(latest['net_pay_vnd']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (latest['status'] == 'draft') ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Phiếu đang ở trạng thái nháp và có thể được cập nhật.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => widget.onOpen(latest),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Xem chi tiết phiếu'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryValue(
                    label: 'Số phiếu',
                    value: '${payslips.length}',
                    icon: Icons.description_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryValue(
                    label: 'Đã thanh toán',
                    value: '$paidCount',
                    icon: Icons.check_circle_outline,
                  ),
                ),
              ],
            ),
          ],
          section('Lịch sử bảng lương'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item.$2),
                      selected: filter == item.$1,
                      onSelected: (_) => setState(() => filter = item.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (visiblePayslips.isEmpty)
            panel(
              child: Column(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 32,
                    color: muted,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    payslips.isEmpty
                        ? 'Chưa có phiếu lương được lưu cho tài khoản này.'
                        : 'Không có phiếu lương ở trạng thái này.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted),
                  ),
                  if (payslips.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Phiếu sẽ xuất hiện sau khi kỳ lương được tính.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          for (final row in visiblePayslips) ...[
            _PayslipTile(
              row: row,
              period: periodLabel(row),
              status: statusLabel(row['status']),
              statusColor: statusColor(row['status']),
              net: money(row['net_pay_vnd']),
              gross: money(row['gross_pay_vnd']),
              deductions: money(row['deductions_vnd']),
              onTap: () => widget.onOpen(row),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => panel(
    child: Row(
      children: [
        Icon(icon, color: green, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PayslipTile extends StatelessWidget {
  const _PayslipTile({
    required this.row,
    required this.period,
    required this.status,
    required this.statusColor,
    required this.net,
    required this.gross,
    required this.deductions,
    required this.onTap,
  });

  final RowData row;
  final String period;
  final String status;
  final Color statusColor;
  final String net;
  final String gross;
  final String deductions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE4EAE5)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, color: green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        period,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Phiếu #${row['id']}',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                _StatusTag(label: status, color: statusColor),
              ],
            ),
            const Divider(height: 24),
            money('Tổng thu nhập', gross),
            money('Khấu trừ', deductions),
            money('Thực lĩnh', net, bold: true),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Chi tiết phiếu',
                  style: TextStyle(color: green, fontSize: 12),
                ),
                SizedBox(width: 5),
                Icon(Icons.arrow_forward, color: green, size: 15),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color, this.background});

  final String label;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
    ),
  );
}
