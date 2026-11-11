import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/workforce_repository.dart';
import '../../widgets/money.dart';
import 'payroll_detail_screen.dart';
import 'payroll_estimate_screen.dart';
import 'payroll_theme.dart';
import 'payroll_verify_screen.dart';

String payslipStatusLabel(Object? status) => switch (status) {
  'paid' => 'Đã thanh toán',
  'approved' => 'Đã duyệt',
  _ => 'Bản nháp',
};

/// Màn 1 – "Bảng lương của tôi": phiếu lương đã chốt theo năm, lối vào lương tạm tính
/// và kiểm tra 6 khoản. Nhân viên chỉ xem, không sửa hay tính lại lương.
class MyPayrollScreen extends StatefulWidget {
  const MyPayrollScreen({super.key, required this.repository, this.onRefresh});
  final WorkforceRepository repository;
  final Future<void> Function()? onRefresh;

  @override
  State<MyPayrollScreen> createState() => _MyPayrollScreenState();
}

class _MyPayrollScreenState extends State<MyPayrollScreen> {
  WorkforceRepository get r => widget.repository;
  int? year;
  late Future<(List<int>, List<RowData>)> loading = _load();

  Future<(List<int>, List<RowData>)> _load() async {
    final years = await r.payrollYears();
    year ??= years.isEmpty ? null : years.first;
    return (years, await r.myPayrolls(year: year));
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      loading = next;
    });
    try {
      await next;
    } catch (_) {}
    await widget.onRefresh?.call();
  }

  void _setYear(int? y) {
    year = y;
    final next = _load();
    setState(() {
      loading = next;
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => PayrollThemed(
    child: Builder(
      builder: (context) {
        final c = PayrollColors.of(context);
        return ColoredBox(
          color: c.background,
          child: FutureBuilder<(List<int>, List<RowData>)>(
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
                          : 'Không tải được bảng lương. Thử lại.',
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (years, rows) = snapshot.data!;
              final latest = rows.isEmpty ? null : rows.first;
              final yearNet = rows.fold<int>(
                0,
                (a, p) => a + (p['net_pay_vnd'] as int),
              );
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    Text(
                      'Bảng lương của tôi',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: c.text,
                      ),
                    ),
                    Text(
                      'Chỉ xem. Phiếu lương do quản lý tính và duyệt.',
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('open-estimate'),
                            onPressed: () =>
                                _push(PayrollEstimateScreen(repository: r)),
                            icon: const Icon(Icons.calculate_outlined),
                            label: const Text('Lương tạm tính'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('open-verify'),
                            onPressed: latest == null
                                ? null
                                : () => _push(
                                    PayrollVerifyScreen(
                                      repository: r,
                                      payslipId: latest['id'] as int,
                                    ),
                                  ),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Kiểm tra 6 khoản'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (years.isNotEmpty)
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final y in years)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  key: Key('year-$y'),
                                  label: Text('Năm $y'),
                                  selected: year == y,
                                  onSelected: (_) => _setYear(y),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (latest != null)
                      Container(
                        key: const Key('latest-card'),
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'THỰC LĨNH GẦN NHẤT • ${latest['period_code']}',
                              style: TextStyle(
                                color: c.onPrimary.withValues(alpha: .75),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              formatVnd(latest['net_pay_vnd'] as num),
                              style: TextStyle(
                                color: c.onPrimary,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${formatDay(latest['starts_on'])} - ${formatDay(latest['ends_on'])} • ${payslipStatusLabel(latest['status'])}',
                              style: TextStyle(color: c.onPrimary),
                            ),
                            if (rows.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Tổng thực lĩnh năm $year: ${formatVnd(yearNet)} (${rows.length} kỳ)',
                                  key: const Key('year-total'),
                                  style: TextStyle(
                                    color: c.onPrimary.withValues(alpha: .85),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (rows.isEmpty)
                      PayrollCard(
                        child: Text(
                          years.isEmpty
                              ? 'Chưa có phiếu lương nào được duyệt. Bạn vẫn xem được lương tạm tính của kỳ hiện tại.'
                              : 'Không có phiếu lương trong năm này.',
                          style: TextStyle(color: c.muted),
                        ),
                      ),
                    for (final p in rows)
                      InkWell(
                        key: Key('payslip-${p['id']}'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _push(
                          PayrollDetailScreen(
                            repository: r,
                            payslipId: p['id'] as int,
                          ),
                        ),
                        child: PayrollCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Kỳ ${p['period_code']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if ((p['pending_disputes'] as int) > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: PayrollChip(
                                        'Đang báo sai',
                                        c.warn,
                                      ),
                                    ),
                                  PayrollChip(
                                    payslipStatusLabel(p['status']),
                                    p['status'] == 'paid' ? c.good : c.primary,
                                  ),
                                ],
                              ),
                              Text(
                                '${formatDay(p['starts_on'])} - ${formatDay(p['ends_on'])}',
                                style: TextStyle(color: c.muted),
                              ),
                              const Divider(height: 22),
                              PayrollLine(
                                'Lương cơ bản + tăng ca',
                                formatVnd(
                                  (p['base_pay_vnd'] as int) +
                                      (p['overtime_pay_vnd'] as int),
                                ),
                              ),
                              PayrollLine(
                                'Phụ cấp + thưởng',
                                formatVnd(
                                  (p['allowance_vnd'] as int) +
                                      (p['bonus_vnd'] as int),
                                ),
                              ),
                              PayrollLine(
                                'Khấu trừ',
                                '-${formatVnd(p['deductions_vnd'] as num)}',
                                color: c.bad,
                              ),
                              PayrollLine(
                                'Thực lĩnh',
                                formatVnd(p['net_pay_vnd'] as num),
                                bold: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
