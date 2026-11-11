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
    int shiftCount(String status) =>
        n(shiftRows.where((r) => r['status'] == status).firstOrNull?['n']);
    final assignments = n(
      (await db.rawQuery(
        "SELECT COUNT(*) n FROM shift_assignments x JOIN shifts s ON s.id=x.shift_id WHERE x.status<>'cancelled' AND s.status<>'cancelled' AND $shiftRange",
        [a, b, ?scope],
      )).single['n'],
    );
    final understaffed = n(
      (await db.rawQuery(
        "SELECT COUNT(*) n FROM shifts s WHERE s.status<>'cancelled' AND $shiftRange AND (SELECT COUNT(*) FROM shift_assignments x WHERE x.shift_id=s.id AND x.status<>'cancelled')<s.required_staff",
        [a, b, ?scope],
      )).single['n'],
    );

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
    final pendingExceptions = n(
      (await db.rawQuery(
        "SELECT COUNT(*) n FROM attendance_events ev JOIN shift_assignments x ON x.id=ev.assignment_id JOIN shifts s ON s.id=x.shift_id WHERE ev.result='pending_review' AND $shiftRange",
        [a, b, ?scope],
      )).single['n'],
    );

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

  static String _clockOf(Object? v) {
    if (v == null) return '--:--';
    final t = utcTime(v).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  static String _dmyOf(Object? v) {
    final t = utcTime(v).toLocal();
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
  }

  static String _vndOf(int v) =>
      '${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫';

  /// Danh sách chi tiết đằng sau từng thẻ của dashboard. Mỗi dòng có `title`, `subtitle`, `badge`
  /// (nhãn trạng thái) và `ok` (tô màu) để một màn hình chung hiển thị. `employees` liệt kê toàn bộ
  /// nhân viên trong phạm vi (Admin: cả hệ thống, Quản lý: chi nhánh của mình), kể cả người đã nghỉ.
  Future<List<RowData>> dashboardDetail(
    String kind, {
    required DateTime from,
    required DateTime to,
  }) async {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final a = day(from), b = day(to);
    final db = await _open();
    await _require(db, 'reports.view');
    final scope = await _attendanceIsAdmin(db)
        ? null
        : (await _me(db))['branch_id'] as int;
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    String hm(int minutes) =>
        '${minutes ~/ 60}g${(minutes % 60).toString().padLeft(2, '0')}';
    final byBranch = scope == null ? '' : ' AND s.branch_id=?';
    switch (kind) {
      case 'employees':
        final rows = await db.rawQuery(
          'SELECT e.*,b.name branch_name,p.name position_name,u.username FROM employees e '
          'LEFT JOIN branches b ON b.id=e.branch_id LEFT JOIN positions p ON p.id=e.position_id '
          'LEFT JOIN users u ON u.id=e.user_id ${scope == null ? '' : 'WHERE e.branch_id=?'} '
          "ORDER BY CASE e.status WHEN 'active' THEN 0 ELSE 1 END,e.full_name",
          [?scope],
        );
        return [
          for (final r in rows)
            {
              'title': '${r['full_name']}',
              'subtitle':
                  '${r['employee_code']} • ${r['position_name'] ?? 'Chưa có chức danh'} • ${r['branch_name'] ?? ''}\n'
                  '${(r['phone'] ?? '').toString().isEmpty ? 'Chưa có số điện thoại' : r['phone']} • '
                  '${r['username'] == null ? 'Chưa có tài khoản' : 'Tài khoản: ${r['username']}'}',
              'badge': r['status'] == 'active' ? 'Đang làm' : 'Đã nghỉ',
              'ok': r['status'] == 'active',
            },
        ];
      case 'shifts':
        final rows = await db.rawQuery(
          "SELECT s.*,b.name branch_name,(SELECT group_concat(e.full_name,', ') FROM shift_assignments x JOIN employees e ON e.id=x.employee_id WHERE x.shift_id=s.id AND x.status<>'cancelled') names,"
          "(SELECT COUNT(*) FROM shift_assignments x WHERE x.shift_id=s.id AND x.status<>'cancelled') assigned "
          "FROM shifts s JOIN branches b ON b.id=s.branch_id WHERE date(s.starts_at,'localtime') BETWEEN ? AND ?$byBranch ORDER BY s.starts_at",
          [a, b, ?scope],
        );
        return [
          for (final r in rows)
            {
              'title':
                  '${_dmyOf(r['starts_at'])} • ${_clockOf(r['starts_at'])}–${_clockOf(r['ends_at'])}',
              'subtitle':
                  '${r['branch_name']} • ${r['assigned']}/${r['required_staff']} người\n${r['names'] ?? 'Chưa phân công'}',
              'badge': switch (r['status']) {
                'scheduled' => 'Chưa bắt đầu',
                'in_progress' => 'Đang diễn ra',
                'closed' => 'Đã đóng',
                _ => 'Đã hủy',
              },
              'ok': r['status'] != 'cancelled',
            },
        ];
      case 'attendance':
        final rows = await db.rawQuery(
          'SELECT r.*,e.full_name,s.starts_at FROM attendance_records r JOIN shift_assignments x ON x.id=r.assignment_id '
          'JOIN shifts s ON s.id=x.shift_id JOIN employees e ON e.id=x.employee_id '
          "WHERE x.status<>'cancelled' AND r.attendance_state<>'VOIDED' AND date(s.starts_at,'localtime') BETWEEN ? AND ?$byBranch ORDER BY s.starts_at DESC,e.full_name",
          [a, b, ?scope],
        );
        return [
          for (final r in rows)
            {
              'title': '${r['full_name']} • ${_dmyOf(r['starts_at'])}',
              'subtitle':
                  'Vào ${_clockOf(r['check_in_at'])} • Ra ${_clockOf(r['check_out_at'])} • ${hm(n(r['worked_minutes']))}'
                  '${n(r['late_minutes']) > 0 ? ' • Muộn ${n(r['late_minutes'])} phút' : ''}',
              'badge': r['check_out_at'] == null
                  ? 'Chưa ra ca'
                  : r['arrival_status'] == 'LATE'
                  ? 'Đi muộn'
                  : 'Đúng giờ',
              'ok': r['check_out_at'] != null && r['arrival_status'] != 'LATE',
            },
        ];
      case 'leave':
        final rows = await db.rawQuery(
          'SELECT l.*,e.full_name,t.name type_name FROM leave_requests l JOIN employees e ON e.id=l.employee_id '
          'LEFT JOIN leave_types t ON t.id=l.leave_type_id '
          "WHERE date(l.starts_at,'localtime')<=? AND date(l.ends_at,'localtime')>=?${scope == null ? '' : ' AND e.branch_id=?'} ORDER BY l.starts_at DESC",
          [b, a, ?scope],
        );
        return [
          for (final r in rows)
            {
              'title': '${r['full_name']} • ${r['type_name'] ?? 'Nghỉ phép'}',
              'subtitle':
                  '${_dmyOf(r['starts_at'])} ${_clockOf(r['starts_at'])} – ${_dmyOf(r['ends_at'])} ${_clockOf(r['ends_at'])}\n${r['reason'] ?? ''}',
              'badge': switch (r['status']) {
                'approved' => 'Đã duyệt',
                'rejected' => 'Từ chối',
                'cancelled' => 'Đã hủy',
                _ => 'Chờ duyệt',
              },
              'ok': r['status'] == 'approved',
            },
        ];
      case 'hours':
        final rows = await db.rawQuery(
          'SELECT e.full_name,SUM(r.worked_minutes) worked,SUM(r.overtime_minutes) ot,SUM(r.late_minutes) late,COUNT(*) shifts '
          'FROM attendance_records r JOIN shift_assignments x ON x.id=r.assignment_id JOIN shifts s ON s.id=x.shift_id JOIN employees e ON e.id=x.employee_id '
          "WHERE x.status<>'cancelled' AND r.attendance_state<>'VOIDED' AND date(s.starts_at,'localtime') BETWEEN ? AND ?$byBranch GROUP BY e.id ORDER BY worked DESC",
          [a, b, ?scope],
        );
        return [
          for (final r in rows)
            {
              'title': '${r['full_name']}',
              'subtitle':
                  '${r['shifts']} ca • Tăng ca ${hm(n(r['ot']))} • Muộn ${n(r['late'])} phút',
              'badge': hm(n(r['worked'])),
              'ok': true,
            },
        ];
      case 'payroll':
        final rows = await db.rawQuery(
          'SELECT p.status,p.base_pay_vnd,p.overtime_pay_vnd,e.full_name,pp.code FROM payslips p JOIN payroll_periods pp ON pp.id=p.period_id JOIN employees e ON e.id=p.employee_id '
          "WHERE pp.starts_on<=? AND pp.ends_on>=?${scope == null ? '' : ' AND e.branch_id=?'} ORDER BY pp.starts_on DESC,e.full_name",
          [b, a, ?scope],
        );
        return [
          for (final r in rows)
            {
              'title': '${r['full_name']} • ${r['code']}',
              'subtitle':
                  'Cơ bản ${_vndOf(n(r['base_pay_vnd']))} • Tăng ca ${_vndOf(n(r['overtime_pay_vnd']))}',
              'badge': switch (r['status']) {
                'paid' => 'Đã trả',
                'approved' => 'Đã duyệt',
                _ => 'Nháp',
              },
              'ok': r['status'] == 'paid',
            },
        ];
    }
    throw const AuthException('Loại thống kê không hợp lệ.');
  }
}
