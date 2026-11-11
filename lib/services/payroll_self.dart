part of 'workforce_repository.dart';

/// Số tiền lương tính bằng số nguyên VNĐ (không dùng số thực để tránh lệch từng đồng).
class PayAmounts {
  const PayAmounts(this.base, this.overtime);
  final int base;
  final int overtime;

  /// Lương cơ bản/tăng ca từ số phút và hợp đồng; hệ số tăng ca đổi sang phần trăm nguyên (1.5 → 150).
  static PayAmounts of({
    required RowData contract,
    required int regularMinutes,
    required int overtimeMinutes,
    required num overtimeMultiplier,
  }) {
    final percent = (overtimeMultiplier * 100).round();
    final hourly = contract['salary_basis'] == 'hourly';
    final rate =
        (hourly ? contract['hourly_rate_vnd'] : contract['base_salary_vnd'])
            as int;
    final per = hourly ? 60 : contract['standard_minutes_per_month'] as int;
    int div(int numerator, int denominator) =>
        (numerator * 2 + denominator) ~/ (2 * denominator);
    return PayAmounts(
      div(regularMinutes * rate, per),
      div(overtimeMinutes * rate * percent, per * 100),
    );
  }
}

/// M02 Bảng lương (Nhân viên): xem phiếu của mình, lương tạm tính (chỉ đọc), chi tiết và báo sai.
extension PayrollSelf on WorkforceRepository {
  static const disputeKeys = [
    'base_salary',
    'overtime',
    'allowance',
    'bonus',
    'insurance',
    'deduction',
  ];

  static String _today() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year.toString().padLeft(4, '0')}-$m-$d';
  }

  /// Phiếu lương đã chốt của tôi theo năm (mới nhất trước), kèm phụ cấp/thưởng đã tách sẵn.
  Future<List<RowData>> myPayrolls({int? year}) async {
    final db = await _open();
    await _require(db, 'payslips.self');
    return db.rawQuery(
      'SELECT p.*,pp.code period_code,pp.starts_on,pp.ends_on,'
      "COALESCE((SELECT SUM(amount_vnd) FROM payslip_items WHERE payslip_id=p.id AND item_type='allowance'),0) allowance_vnd,"
      "COALESCE((SELECT SUM(amount_vnd) FROM payslip_items WHERE payslip_id=p.id AND item_type='bonus'),0) bonus_vnd,"
      "(SELECT COUNT(*) FROM payroll_disputes d WHERE d.payslip_id=p.id AND d.status='pending') pending_disputes "
      'FROM v_payslip_totals p JOIN employees e ON e.id=p.employee_id JOIN payroll_periods pp ON pp.id=p.period_id '
      "WHERE e.user_id=? AND p.status IN ('approved','paid') "
      "${year == null ? '' : 'AND substr(pp.starts_on,1,4)=? '}"
      'ORDER BY pp.starts_on DESC',
      [session.userId, if (year != null) year.toString()],
    );
  }

  /// Các năm có phiếu lương đã chốt (để chọn bộ lọc), năm mới nhất trước.
  Future<List<int>> payrollYears() async {
    final db = await _open();
    await _require(db, 'payslips.self');
    final rows = await db.rawQuery(
      'SELECT DISTINCT CAST(substr(pp.starts_on,1,4) AS INTEGER) y FROM payslips p '
      'JOIN employees e ON e.id=p.employee_id JOIN payroll_periods pp ON pp.id=p.period_id '
      "WHERE e.user_id=? AND p.status IN ('approved','paid') ORDER BY y DESC",
      [session.userId],
    );
    return [for (final r in rows) r['y'] as int];
  }

  /// Chi tiết một phiếu của tôi: các khoản nhóm theo loại, thực lĩnh và các lần báo sai.
  Future<RowData> payrollBreakdown(int payslipId) async {
    final detail = await payslipDetail(payslipId);
    final items = (detail['items'] as List).cast<RowData>();
    int sum(String type) => items
        .where((i) => i['item_type'] == type)
        .fold<int>(0, (a, i) => a + (i['amount_vnd'] as int));
    final db = await _open();
    final disputes = await db.rawQuery(
      'SELECT d.*,(SELECT group_concat(item_key) FROM payroll_dispute_items WHERE dispute_id=d.id) item_keys '
      'FROM payroll_disputes d WHERE d.payslip_id=? ORDER BY d.id DESC',
      [payslipId],
    );
    return {
      ...detail,
      'allowance_vnd': sum('allowance'),
      'bonus_vnd': sum('bonus'),
      'insurance_vnd': sum('insurance'),
      'tax_vnd': sum('tax'),
      'other_deduction_vnd': sum('deduction'),
      'disputes': disputes,
      'pending_dispute': disputes.any((d) => d['status'] == 'pending'),
    };
  }

  /// Lương tạm tính của kỳ chứa hôm nay. Chỉ đọc: không ghi phiếu nào. Phụ cấp/thưởng chỉ có khi quản lý
  /// đã nhập; bảo hiểm lấy theo phiếu nếu có, nếu không thì ước tính theo tỷ lệ của kỳ.
  Future<RowData> estimatePay() async {
    final db = await _open();
    await _require(db, 'payslips.self');
    final me = await _me(db);
    final today = _today();
    final period = (await db.rawQuery(
      'SELECT p.*,pol.overtime_multiplier,pol.insurance_rate_bp FROM payroll_periods p '
      'JOIN payroll_policies pol ON pol.period_id=p.id '
      'WHERE p.starts_on<=? AND p.ends_on>=? ORDER BY p.starts_on DESC LIMIT 1',
      [today, today],
    )).firstOrNull;
    if (period == null) return {'has_period': false, 'today': today};
    final contract = (await db.rawQuery(
      "SELECT * FROM contracts WHERE employee_id=? AND status='active' AND start_date<=? "
      'AND (end_date IS NULL OR end_date>=?) ORDER BY start_date DESC,id DESC LIMIT 1',
      [me['id'], period['starts_on'], period['ends_on']],
    )).firstOrNull;
    if (contract == null) {
      return {
        'has_period': true,
        'has_contract': false,
        'period': period,
        'today': today,
      };
    }
    final records = await db.rawQuery(
      "SELECT r.*,date(s.starts_at,'localtime') day FROM attendance_records r "
      'JOIN shift_assignments a ON a.id=r.assignment_id JOIN shifts s ON s.id=a.shift_id '
      "WHERE a.employee_id=? AND r.status IN ('present','adjusted') AND r.check_out_at IS NOT NULL "
      "AND date(s.starts_at,'localtime') BETWEEN ? AND ?",
      [me['id'], period['starts_on'], period['ends_on']],
    );
    var regular = 0, overtime = 0;
    for (final r in records) {
      overtime += r['overtime_minutes'] as int;
      final unpaid = ['PENDING', 'REJECTED'].contains(r['overtime_status'])
          ? r['overtime_requested_minutes'] as int
          : 0;
      regular +=
          (r['worked_minutes'] as int) -
          (r['overtime_minutes'] as int) -
          unpaid;
    }
    final pay = PayAmounts.of(
      contract: contract,
      regularMinutes: regular,
      overtimeMinutes: overtime,
      overtimeMultiplier: period['overtime_multiplier'] as num,
    );
    final items = await db.rawQuery(
      'SELECT i.item_type,SUM(i.amount_vnd) total FROM payslip_items i JOIN payslips p ON p.id=i.payslip_id '
      'WHERE p.period_id=? AND p.employee_id=? GROUP BY i.item_type',
      [period['id'], me['id']],
    );
    int of(String type) => items
        .where((i) => i['item_type'] == type)
        .fold(0, (a, i) => a + (i['total'] as int));
    final insuranceEntered = items.any((i) => i['item_type'] == 'insurance');
    final insurance = insuranceEntered
        ? of('insurance')
        : pay.base * (period['insurance_rate_bp'] as int) ~/ 10000;
    final allowance = of('allowance'), bonus = of('bonus');
    final deduction = of('deduction'), tax = of('tax');
    final gross = pay.base + pay.overtime + allowance + bonus;
    return {
      'has_period': true,
      'has_contract': true,
      'today': today,
      'period': period,
      'days_worked': {for (final r in records) r['day']}.length,
      'regular_minutes': regular,
      'overtime_minutes': overtime,
      'base_pay_vnd': pay.base,
      'overtime_pay_vnd': pay.overtime,
      'allowance_vnd': allowance,
      'bonus_vnd': bonus,
      'insurance_vnd': insurance,
      'insurance_estimated': !insuranceEntered,
      'tax_vnd': tax,
      'deduction_vnd': deduction,
      'gross_vnd': gross,
      'net_vnd': gross - insurance - tax - deduction,
    };
  }

  /// Nhân viên báo sai một phiếu đã chốt của chính mình: chọn ít nhất một khoản và nhập mô tả.
  Future<int> submitPayrollDispute(
    int payslipId,
    Set<String> keys,
    String message,
  ) async {
    if (keys.isEmpty || !keys.every(PayrollSelf.disputeKeys.contains)) {
      throw const AuthException('Chọn ít nhất một khoản bị sai.');
    }
    if (message.trim().isEmpty) {
      throw const AuthException('Nhập mô tả khoản bị sai.');
    }
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'payslips.self');
      final me = await _me(tx);
      final slip = (await tx.query(
        'payslips',
        where: 'id=? AND employee_id=?',
        whereArgs: [payslipId, me['id']],
      )).firstOrNull;
      if (slip == null) {
        throw const AuthException('Không có quyền xem phiếu lương này.');
      }
      if (!['approved', 'paid'].contains(slip['status'])) {
        throw const AuthException('Chỉ báo sai được phiếu lương đã chốt.');
      }
      if ((await tx.query(
        'payroll_disputes',
        columns: ['id'],
        where: "payslip_id=? AND status='pending'",
        whereArgs: [payslipId],
      )).isNotEmpty) {
        throw const AuthException('Phiếu này đã có báo sai đang chờ xử lý.');
      }
      final id = await tx.insert('payroll_disputes', {
        'payslip_id': payslipId,
        'employee_id': me['id'],
        'message': message.trim(),
        'created_at': sqlTime(DateTime.now()),
      });
      for (final key in keys) {
        await tx.insert('payroll_dispute_items', {
          'dispute_id': id,
          'item_key': key,
        });
      }
      await _audit(tx, 'payroll.dispute', 'payslips', payslipId, {
        'items': keys.toList(),
      });
      final period = (await tx.query(
        'payroll_periods',
        columns: ['code'],
        where: 'id=?',
        whereArgs: [slip['period_id']],
      )).single['code'];
      final managers = await tx.rawQuery(
        "SELECT DISTINCT ur.user_id FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE r.code IN ('admin','manager')",
      );
      await _notify(
        tx,
        [for (final m in managers) m['user_id'] as int],
        'Nhân viên báo sai lương',
        '${me['full_name']} báo sai phiếu lương kỳ $period: ${message.trim()}',
        'payroll_disputes',
        id,
      );
      return id;
    });
  }
}
