import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/workforce_repository.dart';
import '../../widgets/money.dart';
import 'payroll_theme.dart';

String disputeStatusLabel(Object? status) => switch (status) {
  'resolved' => 'Đã xử lý',
  'rejected' => 'Bị từ chối',
  _ => 'Chờ xử lý',
};

String disputeItemLabel(String key) => switch (key) {
  'base_salary' => 'Lương cơ bản',
  'overtime' => 'Tăng ca',
  'allowance' => 'Phụ cấp',
  'bonus' => 'Thưởng',
  'insurance' => 'Bảo hiểm',
  _ => 'Khấu trừ',
};

/// Màn 3 – "Kiểm tra 6 khoản": đối chiếu từng khoản của một phiếu lương và báo sai khoản nào
/// không đúng kèm mô tả. Mỗi phiếu chỉ có một báo sai đang chờ xử lý.
class PayrollVerifyScreen extends StatefulWidget {
  const PayrollVerifyScreen({
    super.key,
    required this.repository,
    required this.payslipId,
  });
  final WorkforceRepository repository;
  final int payslipId;

  @override
  State<PayrollVerifyScreen> createState() => _PayrollVerifyScreenState();
}

class _PayrollVerifyScreenState extends State<PayrollVerifyScreen> {
  WorkforceRepository get r => widget.repository;
  late Future<RowData> loading = r.payrollBreakdown(widget.payslipId);
  final selected = <String>{};
  final message = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    loading = r.payrollBreakdown(widget.payslipId);
  });

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await r.submitPayrollDispute(widget.payslipId, selected, message.text);
      if (!mounted) return;
      selected.clear();
      message.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gửi báo sai. Quản lý sẽ phản hồi.')),
      );
      _reload();
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Không gửi được báo sai.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<(String, String, int, String)> _rows(RowData p) {
    final items = (p['items'] as List).cast<RowData>();
    String names(Set<String> types) {
      final n = items
          .where((i) => types.contains(i['item_type']))
          .map((i) => '${i['name']}')
          .toList();
      return n.isEmpty ? 'Không có khoản nào' : n.join(', ');
    }

    return [
      (
        'base_salary',
        'Lương cơ bản',
        p['base_pay_vnd'] as int,
        '${formatMinutes(p['regular_minutes'] as num)} làm thường',
      ),
      (
        'overtime',
        'Tăng ca',
        p['overtime_pay_vnd'] as int,
        '${formatMinutes(p['overtime_minutes'] as num)} tăng ca',
      ),
      ('allowance', 'Phụ cấp', p['allowance_vnd'] as int, names({'allowance'})),
      ('bonus', 'Thưởng', p['bonus_vnd'] as int, names({'bonus'})),
      (
        'insurance',
        'Bảo hiểm',
        p['insurance_vnd'] as int,
        names({'insurance'}),
      ),
      (
        'deduction',
        'Khấu trừ khác',
        (p['tax_vnd'] as int) + (p['other_deduction_vnd'] as int),
        names({'tax', 'deduction'}),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => PayrollThemed(
    child: Builder(
      builder: (context) {
        final c = PayrollColors.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Kiểm tra 6 khoản')),
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
                          : 'Không tải được phiếu lương.',
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final p = snapshot.data!;
              final rows = _rows(p);
              final pending = p['pending_dispute'] == true;
              final disputes = (p['disputes'] as List).cast<RowData>();
              // Cộng các khoản phải ra đúng thực lĩnh.
              final earned = rows.take(4).fold<int>(0, (a, e) => a + e.$3);
              final taken = rows.skip(4).fold<int>(0, (a, e) => a + e.$3);
              final consistent = earned - taken == (p['net_pay_vnd'] as int);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Kỳ ${p['period_code']} • ${formatDay(p['starts_on'])} - ${formatDay(p['ends_on'])}',
                    style: TextStyle(color: c.muted),
                  ),
                  const SizedBox(height: 10),
                  for (final row in rows)
                    PayrollCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.$2,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  row.$4,
                                  style: TextStyle(
                                    color: c.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${row.$1 == 'insurance' || row.$1 == 'deduction' ? '-' : ''}${formatVnd(row.$3)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    color:
                                        row.$1 == 'insurance' ||
                                            row.$1 == 'deduction'
                                        ? c.bad
                                        : c.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilterChip(
                            key: Key('flag-${row.$1}'),
                            label: Text(
                              selected.contains(row.$1)
                                  ? 'Đã chọn sai'
                                  : 'Báo sai',
                            ),
                            selected: selected.contains(row.$1),
                            avatar: Icon(
                              selected.contains(row.$1)
                                  ? Icons.flag
                                  : Icons.outlined_flag,
                              size: 16,
                            ),
                            onSelected: pending
                                ? null
                                : (v) => setState(
                                    () => v
                                        ? selected.add(row.$1)
                                        : selected.remove(row.$1),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  PayrollCard(
                    child: Column(
                      children: [
                        PayrollLine(
                          'Thực lĩnh',
                          formatVnd(p['net_pay_vnd'] as num),
                          bold: true,
                        ),
                        Row(
                          children: [
                            Icon(
                              consistent
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 16,
                              color: consistent ? c.good : c.warn,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                consistent
                                    ? 'Tổng các khoản khớp với thực lĩnh.'
                                    : 'Tổng các khoản chưa khớp thực lĩnh, hãy báo sai.',
                                key: const Key('consistency'),
                                style: TextStyle(color: c.muted, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (pending)
                    PayrollCard(
                      child: Text(
                        'Phiếu này đang có báo sai chờ quản lý xử lý. Bạn chỉ gửi được báo sai mới sau khi có phản hồi.',
                        key: const Key('pending-note'),
                        style: TextStyle(color: c.warn),
                      ),
                    )
                  else ...[
                    TextField(
                      key: const Key('dispute-message'),
                      controller: message,
                      maxLines: 3,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: 'Mô tả khoản bị sai',
                        hintText: 'Ví dụ: thiếu 2 giờ tăng ca ngày 15/10',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!, style: TextStyle(color: c.bad)),
                      ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const Key('send-dispute'),
                      onPressed: busy ? null : _submit,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(busy ? 'Đang gửi…' : 'Gửi báo sai'),
                    ),
                  ],
                  if (disputes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Lịch sử báo sai',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final d in disputes)
                      PayrollCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${('${d['item_keys'] ?? ''}').split(',').where((k) => k.isNotEmpty).map(disputeItemLabel).join(', ')}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                PayrollChip(
                                  disputeStatusLabel(d['status']),
                                  switch (d['status']) {
                                    'resolved' => c.good,
                                    'rejected' => c.bad,
                                    _ => c.warn,
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${d['message']}'),
                            if ((d['resolution_note'] ?? '')
                                .toString()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Phản hồi: ${d['resolution_note']}',
                                  style: TextStyle(color: c.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
