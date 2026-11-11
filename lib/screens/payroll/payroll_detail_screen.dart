import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/auth_service.dart';
import '../../services/payslip_pdf.dart';
import '../../services/workforce_repository.dart';
import '../../widgets/money.dart';
import 'my_payroll_screen.dart' show payslipStatusLabel;
import 'payroll_theme.dart';
import 'payroll_verify_screen.dart';

/// Màn 4 – "Chi tiết phiếu lương": các khoản thu nhập, khấu trừ, thực lĩnh; xuất PDF, in và báo sai.
class PayrollDetailScreen extends StatefulWidget {
  const PayrollDetailScreen({
    super.key,
    required this.repository,
    required this.payslipId,
  });
  final WorkforceRepository repository;
  final int payslipId;

  @override
  State<PayrollDetailScreen> createState() => _PayrollDetailScreenState();
}

class _PayrollDetailScreenState extends State<PayrollDetailScreen> {
  late Future<RowData> loading = widget.repository.payrollBreakdown(
    widget.payslipId,
  );
  bool exporting = false;

  Future<void> _export(RowData pay, {required bool print}) async {
    setState(() => exporting = true);
    try {
      final bytes = await buildPayslipPdf(pay);
      final name = 'phieu-luong-${pay['period_code']}.pdf';
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tạo được file PDF.')),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  static String _type(Object? t) => switch (t) {
    'allowance' => 'Phụ cấp',
    'bonus' => 'Thưởng',
    'insurance' => 'Bảo hiểm',
    'tax' => 'Thuế',
    _ => 'Khấu trừ',
  };

  @override
  Widget build(BuildContext context) => PayrollThemed(
    child: Builder(
      builder: (context) {
        final c = PayrollColors.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Chi tiết phiếu lương')),
          body: FutureBuilder<RowData>(
            future: loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final e = snapshot.error;
                return Center(
                  child: Text(
                    e is AuthException
                        ? e.message
                        : 'Không tải được phiếu lương.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final p = snapshot.data!;
              final items = (p['items'] as List).cast<RowData>();
              bool minus(RowData i) => const [
                'insurance',
                'tax',
                'deduction',
              ].contains(i['item_type']);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p['full_name']} • KỲ ${p['period_code']}',
                          style: TextStyle(
                            color: c.onPrimary.withValues(alpha: .75),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatVnd(p['net_pay_vnd'] as num),
                          key: const Key('detail-net'),
                          style: TextStyle(
                            color: c.onPrimary,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${formatDay(p['starts_on'])} - ${formatDay(p['ends_on'])} • ${payslipStatusLabel(p['status'])}',
                          style: TextStyle(color: c.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  PayrollCard(
                    child: Column(
                      children: [
                        PayrollLine(
                          'Giờ làm thường',
                          formatMinutes(p['regular_minutes'] as num),
                        ),
                        PayrollLine(
                          'Giờ tăng ca',
                          formatMinutes(p['overtime_minutes'] as num),
                        ),
                      ],
                    ),
                  ),
                  PayrollCard(
                    child: Column(
                      children: [
                        PayrollLine(
                          'Lương cơ bản',
                          formatVnd(p['base_pay_vnd'] as num),
                        ),
                        PayrollLine(
                          'Lương tăng ca',
                          formatVnd(p['overtime_pay_vnd'] as num),
                        ),
                        for (final i in items)
                          PayrollLine(
                            '${i['name']}',
                            '${minus(i) ? '-' : '+'}${formatVnd(i['amount_vnd'] as num)}',
                            sub: _type(i['item_type']),
                            color: minus(i) ? c.bad : null,
                          ),
                        const Divider(),
                        PayrollLine(
                          'Tổng thu nhập',
                          formatVnd(p['gross_pay_vnd'] as num),
                        ),
                        PayrollLine(
                          'Tổng khấu trừ',
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
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('export-pdf'),
                          onPressed: exporting
                              ? null
                              : () => _export(p, print: false),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Xuất PDF'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('print-pdf'),
                          onPressed: exporting
                              ? null
                              : () => _export(p, print: true),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('In phiếu'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('detail-verify'),
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PayrollVerifyScreen(
                            repository: widget.repository,
                            payslipId: widget.payslipId,
                          ),
                        ),
                      );
                      if (mounted) {
                        setState(() {
                          loading = widget.repository.payrollBreakdown(
                            widget.payslipId,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      p['pending_dispute'] == true
                          ? 'Đang có báo sai chờ xử lý'
                          : 'Kiểm tra 6 khoản / Báo sai',
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
