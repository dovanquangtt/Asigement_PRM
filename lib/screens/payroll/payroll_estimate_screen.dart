import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/workforce_repository.dart';
import '../../widgets/money.dart';
import 'payroll_theme.dart';

/// Màn 2 – "Lương tạm tính": ước tính lương của kỳ hiện tại từ công đã ghi nhận. Chỉ đọc,
/// không tạo hay sửa phiếu lương; số chính thức nằm ở phiếu lương quản lý đã duyệt.
class PayrollEstimateScreen extends StatefulWidget {
  const PayrollEstimateScreen({super.key, required this.repository});
  final WorkforceRepository repository;

  @override
  State<PayrollEstimateScreen> createState() => _PayrollEstimateScreenState();
}

class _PayrollEstimateScreenState extends State<PayrollEstimateScreen> {
  late Future<RowData> loading = widget.repository.estimatePay();

  void _reload() {
    setState(() {
      loading = widget.repository.estimatePay();
    });
  }

  Widget _message(PayrollColors c, IconData icon, String title, String body) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: c.muted),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            ],
          ),
        ),
      );

  Widget _body(BuildContext context, RowData e) {
    final c = PayrollColors.of(context);
    if (e['has_period'] != true) {
      return _message(
        c,
        Icons.event_busy_outlined,
        'Chưa có kỳ lương',
        'Hôm nay chưa thuộc kỳ lương nào. Quản lý sẽ tạo kỳ lương mới.',
      );
    }
    if (e['has_contract'] != true) {
      return _message(
        c,
        Icons.description_outlined,
        'Chưa có hợp đồng',
        'Bạn chưa có hợp đồng bao phủ kỳ này nên chưa thể ước tính lương. Hãy liên hệ quản lý.',
      );
    }
    final period = e['period'] as RowData;
    int n(String k) => (e[k] as num).toInt();
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
                'THỰC LĨNH TẠM TÍNH • KỲ ${period['code']}',
                style: TextStyle(
                  color: c.onPrimary.withValues(alpha: .75),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatVnd(n('net_vnd')),
                key: const Key('estimate-net'),
                style: TextStyle(
                  color: c.onPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${formatDay(period['starts_on'])} - ${formatDay(period['ends_on'])} • tính đến ${formatDay(e['today'])}',
                style: TextStyle(color: c.onPrimary),
              ),
            ],
          ),
        ),
        PayrollCard(
          child: Column(
            children: [
              PayrollLine('Số ngày có công', '${n('days_worked')} ngày'),
              PayrollLine(
                'Giờ làm thường',
                formatMinutes(n('regular_minutes')),
              ),
              PayrollLine('Giờ tăng ca', formatMinutes(n('overtime_minutes'))),
            ],
          ),
        ),
        PayrollCard(
          child: Column(
            children: [
              PayrollLine('Lương cơ bản', formatVnd(n('base_pay_vnd'))),
              PayrollLine(
                'Lương tăng ca',
                formatVnd(n('overtime_pay_vnd')),
                sub: 'Hệ số ${period['overtime_multiplier']}',
              ),
              if (n('allowance_vnd') > 0)
                PayrollLine('Phụ cấp', formatVnd(n('allowance_vnd'))),
              if (n('bonus_vnd') > 0)
                PayrollLine('Thưởng', formatVnd(n('bonus_vnd'))),
              const Divider(),
              PayrollLine(
                'Tổng thu nhập',
                formatVnd(n('gross_vnd')),
                bold: true,
              ),
              PayrollLine(
                'Bảo hiểm',
                '-${formatVnd(n('insurance_vnd'))}',
                color: c.bad,
                sub: e['insurance_estimated'] == true
                    ? 'Ước tính ${(period['insurance_rate_bp'] as int) / 100}% lương cơ bản'
                    : 'Theo phiếu lương',
              ),
              if (n('tax_vnd') > 0)
                PayrollLine(
                  'Thuế',
                  '-${formatVnd(n('tax_vnd'))}',
                  color: c.bad,
                ),
              if (n('deduction_vnd') > 0)
                PayrollLine(
                  'Khấu trừ khác',
                  '-${formatVnd(n('deduction_vnd'))}',
                  color: c.bad,
                ),
            ],
          ),
        ),
        PayrollCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: c.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Đây là số tạm tính từ công đã ghi nhận, chưa phải phiếu lương chính thức. '
                  'Phụ cấp, thưởng và khấu trừ chỉ hiện khi quản lý đã nhập. Ca chờ duyệt tăng ca chưa được tính.',
                  style: TextStyle(color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PayrollThemed(
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Lương tạm tính'),
          actions: [
            IconButton(
              tooltip: 'Cập nhật',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<RowData>(
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
                        : 'Không tính được. Thử lại.',
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _body(context, snapshot.data!);
          },
        ),
      ),
    ),
  );
}
