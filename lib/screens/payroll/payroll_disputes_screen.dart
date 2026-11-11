import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/workforce_repository.dart';
import '../../widgets/review_note_dialog.dart';
import 'payroll_theme.dart';
import 'payroll_verify_screen.dart' show disputeItemLabel, disputeStatusLabel;

/// Quản lý/Admin: danh sách báo sai lương của nhân viên, lọc theo trạng thái và phản hồi
/// (đã xử lý / từ chối, bắt buộc có nội dung để nhân viên biết kết quả).
class PayrollDisputesScreen extends StatefulWidget {
  const PayrollDisputesScreen({super.key, required this.repository});
  final WorkforceRepository repository;

  @override
  State<PayrollDisputesScreen> createState() => _PayrollDisputesScreenState();
}

class _PayrollDisputesScreenState extends State<PayrollDisputesScreen> {
  WorkforceRepository get r => widget.repository;
  late Future<List<RowData>> loading = r.payrollDisputes();
  String filter = 'pending';

  void _reload() {
    setState(() {
      loading = r.payrollDisputes();
    });
  }

  Future<void> _resolve(RowData d, bool accept) async {
    final note = await askReviewNote(
      context,
      approve: accept,
      label: '${d['full_name']}',
      subject: 'báo sai lương của',
    );
    if (note == null) return;
    try {
      await r.resolvePayrollDispute(
        d['id'] as int,
        accept: accept,
        note: note.isEmpty ? 'Đã kiểm tra và điều chỉnh.' : note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Đã xử lý báo sai.' : 'Đã từ chối báo sai.'),
        ),
      );
      _reload();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PayrollThemed(
    child: Builder(
      builder: (context) {
        final c = PayrollColors.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Báo sai lương')),
          body: FutureBuilder<List<RowData>>(
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
                          : 'Không tải được. Thử lại.',
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              final rows = filter == 'all'
                  ? all
                  : all.where((d) => d['status'] == filter).toList();
              int count(String s) => s == 'all'
                  ? all.length
                  : all.where((d) => d['status'] == s).length;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final f in const [
                          ('pending', 'Chờ xử lý'),
                          ('resolved', 'Đã xử lý'),
                          ('rejected', 'Từ chối'),
                          ('all', 'Tất cả'),
                        ])
                          ChoiceChip(
                            key: Key('dispute-filter-${f.$1}'),
                            label: Text('${f.$2} (${count(f.$1)})'),
                            selected: filter == f.$1,
                            onSelected: (_) => setState(() => filter = f.$1),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(
                            child: Text(
                              'Không có báo sai nào.',
                              style: TextStyle(color: c.muted),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              for (final d in rows)
                                PayrollCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${d['full_name']} • ${d['period_code']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
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
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          for (final k
                                              in ('${d['item_keys'] ?? ''}')
                                                  .split(',')
                                                  .where((k) => k.isNotEmpty))
                                            Chip(
                                              label: Text(disputeItemLabel(k)),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                      Text('${d['message']}'),
                                      if ((d['resolution_note'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            'Phản hồi: ${d['resolution_note']}',
                                            style: TextStyle(color: c.muted),
                                          ),
                                        ),
                                      if (d['status'] == 'pending')
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              key: Key(
                                                'dispute-reject-${d['id']}',
                                              ),
                                              onPressed: () =>
                                                  _resolve(d, false),
                                              child: const Text('Từ chối'),
                                            ),
                                            FilledButton(
                                              key: Key(
                                                'dispute-resolve-${d['id']}',
                                              ),
                                              onPressed: () =>
                                                  _resolve(d, true),
                                              child: const Text('Đã xử lý'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                            ],
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
