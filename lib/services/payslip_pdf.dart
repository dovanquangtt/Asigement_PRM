import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../widgets/money.dart';
import 'workforce_repository.dart';

/// Dựng phiếu lương PDF (khổ A4, font Roboto nhúng để có đủ dấu tiếng Việt) từ kết quả
/// `payrollBreakdown`. Dùng được cho cả tải/chia sẻ lẫn in.
Future<Uint8List> buildPayslipPdf(
  RowData pay, {
  pw.Font? regular,
  pw.Font? bold,
}) async {
  final base =
      regular ??
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final strong =
      bold ??
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final doc = pw.Document(title: 'Phiếu lương ${pay['period_code']}');
  final items = (pay['items'] as List).cast<RowData>();
  String type(Object? t) => switch (t) {
    'allowance' => 'Phụ cấp',
    'bonus' => 'Thưởng',
    'insurance' => 'Bảo hiểm',
    'tax' => 'Thuế',
    _ => 'Khấu trừ',
  };
  pw.Widget row(String a, String b, {bool bolded = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(a, style: pw.TextStyle(font: bolded ? strong : base)),
        pw.Text(b, style: pw.TextStyle(font: bolded ? strong : base)),
      ],
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(base: base, bold: strong),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ANH EM QUÁN',
            style: pw.TextStyle(font: strong, fontSize: 12),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'PHIẾU LƯƠNG',
            style: pw.TextStyle(font: strong, fontSize: 24),
          ),
          pw.Text(
            'Kỳ ${pay['period_code']}: ${formatDay(pay['starts_on'])} - ${formatDay(pay['ends_on'])}',
          ),
          pw.SizedBox(height: 12),
          row('Nhân viên', '${pay['full_name']}', bolded: true),
          row(
            'Trạng thái',
            pay['status'] == 'paid' ? 'Đã thanh toán' : 'Đã duyệt',
          ),
          pw.Divider(),
          row('Giờ làm thường', formatMinutes(pay['regular_minutes'] as num?)),
          row('Giờ tăng ca', formatMinutes(pay['overtime_minutes'] as num?)),
          pw.Divider(),
          row('Lương cơ bản', formatVnd(pay['base_pay_vnd'] as num?)),
          row('Lương tăng ca', formatVnd(pay['overtime_pay_vnd'] as num?)),
          for (final i in items)
            row(
              '${i['name']} (${type(i['item_type'])})',
              '${const ['insurance', 'tax', 'deduction'].contains(i['item_type']) ? '-' : '+'}${formatVnd(i['amount_vnd'] as num?)}',
            ),
          pw.Divider(),
          row('Tổng thu nhập', formatVnd(pay['gross_pay_vnd'] as num?)),
          row('Tổng khấu trừ', formatVnd(pay['deductions_vnd'] as num?)),
          row('THỰC LĨNH', formatVnd(pay['net_pay_vnd'] as num?), bolded: true),
          pw.Spacer(),
          pw.Text(
            'Phiếu lương #${pay['id']} • Xuất từ ứng dụng quản lý nhân sự Anh Em Quán.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
