import 'package:flutter/material.dart';

import '../services/workforce_repository.dart';
import '../widgets/common_widgets.dart';

class PayrollChecksScreen extends StatelessWidget {
  const PayrollChecksScreen({
    super.key,
    required this.payslip,
    required this.checks,
    required this.checksCurrent,
  });

  final RowData payslip;
  final List<RowData> checks;
  final bool checksCurrent;

  String _status(int stepNumber) {
    final exists = checks.any((check) => check['step_number'] == stepNumber);
    if (!exists) return 'Chưa thực hiện';
    return checksCurrent ? 'Đạt' : 'Cần tính lại';
  }

  Color _statusColor(String status) => switch (status) {
    'Đạt' => const Color(0xFF286B4F),
    'Cần tính lại' => const Color(0xFF9A641B),
    _ => const Color(0xFF596B74),
  };

  @override
  Widget build(BuildContext context) {
    final checkByStep = {
      for (final check in checks) check['step_number'] as int: check,
    };
    final complete =
        checkByStep.length == 6 &&
        List<int>.generate(
          6,
          (index) => index + 1,
        ).every(checkByStep.containsKey);

    return Scaffold(
      appBar: AppBar(title: const Text('Kiểm tra 6 bước tính lương')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          heading(
            '${payslip['full_name']}',
            'KỲ ${payslip['period_code']} • PHIẾU #${payslip['id']}',
          ),
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete
                      ? checksCurrent
                            ? 'Đã hoàn thành 6/6 bước'
                            : 'Có 6 bước đã chạy nhưng dữ liệu đã thay đổi'
                      : 'Đã hoàn thành ${checkByStep.length}/6 bước',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  complete && checksCurrent
                      ? 'Kết quả kiểm tra còn khớp với dữ liệu hiện tại.'
                      : complete
                      ? 'Cần tính lại lương trước khi quản lý duyệt.'
                      : 'Một số bước chưa có kết quả. Hãy chạy lại kiểm tra lương.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          section('Bảng thống kê các bước'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Bước')),
                DataColumn(label: Text('Nội dung kiểm tra')),
                DataColumn(label: Text('Kết quả đối chiếu')),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: [
                for (var step = 1; step <= 6; step++)
                  _buildStepRow(step, checkByStep[step]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Bảng này phản ánh kết quả của lần tính gần nhất. Nếu công, hợp đồng hoặc khoản điều chỉnh thay đổi, cần tính lại để cập nhật trạng thái.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildStepRow(int step, RowData? check) {
    final status = _status(step);
    return DataRow(
      cells: [
        DataCell(Text('$step')),
        DataCell(
          SizedBox(
            width: 190,
            child: Text('${check?['name'] ?? 'Bước $step'}', softWrap: true),
          ),
        ),
        DataCell(
          SizedBox(
            width: 280,
            child: Text(
              '${check?['detail'] ?? 'Chưa có dữ liệu kiểm tra.'}',
              softWrap: true,
            ),
          ),
        ),
        DataCell(
          Text(
            status,
            style: TextStyle(
              color: _statusColor(status),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
