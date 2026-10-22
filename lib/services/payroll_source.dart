import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Cùng một cách tính hash cho nghiệp vụ và bộ dữ liệu mẫu.
/// Không phụ thuộc Flutter, đường dẫn máy hoặc ID bản ghi được gán cố định.
Future<String> payrollSourceHash(
  DatabaseExecutor tx,
  int periodId,
  int employeeId,
  int contractId,
) async {
  final p = (await tx.query(
    'payroll_periods',
    where: 'id=?',
    whereArgs: [periodId],
  )).single;
  final policy = await tx.query(
    'payroll_policies',
    where: 'period_id=?',
    whereArgs: [periodId],
  );
  final contract = await tx.query(
    'contracts',
    where: 'employee_id=? OR id=?',
    whereArgs: [employeeId, contractId],
    orderBy: 'id',
  );
  final records = await tx.rawQuery(
    "SELECT r.*,a.employee_id,s.starts_at,s.ends_at FROM attendance_records r JOIN shift_assignments a ON a.id=r.assignment_id JOIN shifts s ON s.id=a.shift_id WHERE a.employee_id=? AND r.status IN ('present','adjusted') AND r.check_out_at IS NOT NULL AND date(s.starts_at,'localtime') BETWEEN ? AND ? ORDER BY r.id",
    [employeeId, p['starts_on'], p['ends_on']],
  );
  final items = await tx.rawQuery(
    'SELECT i.code,i.name,i.item_type,i.amount_vnd FROM payslip_items i JOIN payslips ps ON ps.id=i.payslip_id WHERE ps.employee_id=? AND ps.period_id=? ORDER BY i.code',
    [employeeId, periodId],
  );
  final pay = await tx.query(
    'payslips',
    columns: [
      'base_pay_vnd',
      'overtime_pay_vnd',
      'regular_minutes',
      'overtime_minutes',
    ],
    where: 'period_id=? AND employee_id=?',
    whereArgs: [periodId, employeeId],
  );
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            p['starts_on'],
            p['ends_on'],
            policy,
            contract,
            records,
            items,
            pay,
          ]),
        ),
      )
      .toString();
}
