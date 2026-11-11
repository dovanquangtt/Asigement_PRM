part of 'workforce_repository.dart';

/// M12 Dashboard: thống kê nhân sự, ca làm, điểm danh, nghỉ phép, giờ làm và lương trong
/// một khoảng ngày. Admin thấy tất cả chi nhánh, quản lý chỉ thấy chi nhánh của mình.
extension DashboardSummary on WorkforceRepository {
  Future<RowData> dashboardSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start) || end.difference(start).inDays > 366) {
      throw const AuthException('Khoảng ngày không hợp lệ.');
    }
    final db = await _open();
    await _require(db, 'reports.view');
    final scope = await _attendanceIsAdmin(db)
        ? null
        : (await _me(db))['branch_id'] as int;
    final a = day(start), b = day(end);
    final shiftRange =
        "date(s.starts_at,'localtime') BETWEEN ? AND ?${scope == null ? '' : ' AND s.branch_id=?'}";

    int n(Object? v) => (v as num?)?.toInt() ?? 0;

    final employees = (await db.rawQuery(
      "SELECT COUNT(*) total,SUM(user_id IS NOT NULL) with_account FROM employees WHERE status='active'${scope == null ? '' : ' AND branch_id=?'}",
      [?scope],
    )).single;

    final shiftRows = await db.rawQuery(
      'SELECT s.status,COUNT(*) n FROM shifts s WHERE $shiftRange GROUP BY s.status',
      [a, b, ?scope],
    );
    int shiftCount(String status) => n(
      shiftRows.where((r) => r['status'] == status).firstOrNull?['n'],
    );
    final assignments = n((await db.rawQuery(
      "SELECT COUNT(*) n FROM shift_assignments x JOIN shifts s ON s.id=x.shift_id WHERE x.status<>'cancelled' AND s.status<>'cancelled' AND $shiftRange",
      [a, b, ?scope],
    )).single['n']);
    final understaffed = n((await db.rawQuery(
      "SELECT COUNT(*) n FROM shifts s WHERE s.status<>'cancelled' AND $shiftRange AND (SELECT COUNT(*) FROM shift_assignments x WHERE x.shift_id=s.id AND x.status<>'cancelled')<s.required_staff",
      [a, b, ?scope],
    )).single['n']);

    final att = (await db.rawQuery(
      "SELECT COUNT(*) records,"
      "COALESCE(SUM(r.arrival_status='ON_TIME'),0) on_time,"
      "COALESCE(SUM(r.arrival_status='LATE'),0) late,"
      "COALESCE(SUM(r.check_in_at IS NOT NULL AND r.check_out_at IS NULL),0) open,"
      "COALESCE(SUM(r.worked_minutes),0) worked,COALESCE(SUM(r.overtime_minutes),0) overtime,COALESCE(SUM(r.late_minutes),0) late_minutes "
      "FROM attendance_records r JOIN shift_assignments x ON x.id=r.assignment_id JOIN shifts s ON s.id=x.shift_id "
      "WHERE x.status<>'cancelled' AND r.attendance_state<>'VOIDED' AND $shiftRange",
      [a, b, ?scope],
    )).single;
    final pendingExceptions = n((await db.rawQuery(
      "SELECT COUNT(*) n FROM attendance_events ev JOIN shift_assignments x ON x.id=ev.assignment_id JOIN shifts s ON s.id=x.shift_id WHERE ev.result='pending_review' AND $shiftRange",
      [a, b, ?scope],
    )).single['n']);

    final leaveRows = await db.rawQuery(
      "SELECT l.status,COUNT(*) n,COALESCE(SUM(l.requested_minutes),0) minutes FROM leave_requests l JOIN employees e ON e.id=l.employee_id "
      "WHERE date(l.starts_at,'localtime')<=? AND date(l.ends_at,'localtime')>=?${scope == null ? '' : ' AND e.branch_id=?'} GROUP BY l.status",
      [b, a, ?scope],
    );
    RowData leaveOf(String status) =>
        leaveRows.where((r) => r['status'] == status).firstOrNull ?? const {};

    final payRows = await db.rawQuery(
      "SELECT p.status,COUNT(*) n,COALESCE(SUM(p.base_pay_vnd+p.overtime_pay_vnd),0) gross FROM payslips p JOIN payroll_periods pp ON pp.id=p.period_id JOIN employees e ON e.id=p.employee_id "
      "WHERE pp.starts_on<=? AND pp.ends_on>=?${scope == null ? '' : ' AND e.branch_id=?'} GROUP BY p.status",
      [b, a, ?scope],
    );
    int payCount(String status) =>
        n(payRows.where((r) => r['status'] == status).firstOrNull?['n']);

    return {
      'from': a,
      'to': b,
      'employees': {
        'active': n(employees['total']),
        'with_account': n(employees['with_account']),
      },
      'shifts': {
        'total': shiftRows.fold<int>(0, (s, r) => s + n(r['n'])),
        'scheduled': shiftCount('scheduled'),
        'in_progress': shiftCount('in_progress'),
        'closed': shiftCount('closed'),
        'cancelled': shiftCount('cancelled'),
        'assignments': assignments,
        'understaffed': understaffed,
      },
      'attendance': {
        'records': n(att['records']),
        'on_time': n(att['on_time']),
        'late': n(att['late']),
        'missing_check_out': n(att['open']),
        'pending_exceptions': pendingExceptions,
      },
      'leave': {
        'pending': n(leaveOf('pending')['n']),
        'approved': n(leaveOf('approved')['n']),
        'rejected': n(leaveOf('rejected')['n']),
        'approved_minutes': n(leaveOf('approved')['minutes']),
      },
      'hours': {
        'worked_minutes': n(att['worked']),
        'overtime_minutes': n(att['overtime']),
        'late_minutes': n(att['late_minutes']),
      },
      'payroll': {
        'payslips': payRows.fold<int>(0, (s, r) => s + n(r['n'])),
        'draft': payCount('draft'),
        'approved': payCount('approved'),
        'paid': payCount('paid'),
        'gross_vnd': payRows.fold<int>(0, (s, r) => s + n(r['gross'])),
      },
    };
  }
}
