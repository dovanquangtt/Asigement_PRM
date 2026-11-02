part of 'workforce_repository.dart';

/// Nhân viên chấp nhận / từ chối ca được phân, và bảng toàn bộ ca của từng nhân viên
/// cho quản lý / Admin.
extension ShiftResponse on WorkforceRepository {
  /// Phản hồi một phân công đang chờ. Từ chối bắt buộc có lý do và giải phóng chỗ trong ca.
  Future<void> respondAssignment(
    int assignmentId,
    bool accept, {
    String note = '',
    DateTime? now,
  }) async {
    if (!accept && note.trim().isEmpty) {
      throw const AuthException('Nhập lý do từ chối ca.');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'schedule.self');
      final me = await _me(tx);
      final rows = await tx.rawQuery(
        'SELECT a.*,s.starts_at,s.ends_at,s.branch_id,s.status shift_status FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.id=? AND a.employee_id=?',
        [assignmentId, me['id']],
      );
      if (rows.isEmpty) {
        throw const AuthException('Phân ca không thuộc bạn.');
      }
      final a = rows.single;
      if (a['status'] != 'assigned' || a['response_status'] != 'pending') {
        throw const AuthException(
          'Ca đã được phản hồi hoặc không còn hiệu lực.',
        );
      }
      final started = !utcTime(a['starts_at']).isAfter(clock);
      final hasAttendance = (await tx.query(
        'attendance_events',
        columns: ['id'],
        where: 'assignment_id=?',
        whereArgs: [assignmentId],
        limit: 1,
      )).isNotEmpty;
      if (a['shift_status'] != 'scheduled' || started || hasAttendance) {
        throw const AuthException(
          'Không thể phản hồi ca đã bắt đầu hoặc đã có chấm công.',
        );
      }
      await tx.update(
        'shift_assignments',
        {
          'response_status': accept ? 'accepted' : 'rejected',
          'responded_at': sqlTime(clock),
          'response_note': accept ? null : note.trim(),
          if (!accept) 'status': 'cancelled',
        },
        where: 'id=?',
        whereArgs: [assignmentId],
      );
      await _audit(
        tx,
        accept ? 'shift.accept' : 'shift.reject',
        'shift_assignments',
        assignmentId,
        {'note': note.trim()},
      );
      final recipients = {
        a['assigned_by'] as int,
        ...await _attendanceReviewers(tx, a['branch_id'] as int),
      };
      final label = _shiftLabel(a);
      await _notify(
        tx,
        recipients,
        accept ? 'Nhân viên chấp nhận ca' : 'Nhân viên từ chối ca',
        accept
            ? '${me['full_name']} đã chấp nhận ca $label.'
            : '${me['full_name']} đã từ chối ca $label. Lý do: ${note.trim()}',
        'shifts',
        a['shift_id'] as int,
      );
    });
  }

  Future<int?> _shiftScope(DatabaseExecutor db) async {
    await _require(db, 'shifts.manage');
    if (await _attendanceIsAdmin(db)) return null;
    return (await _me(db))['branch_id'] as int;
  }

  /// Nhân viên có thể chọn để xem bảng ca: Admin thấy tất cả, quản lý theo chi nhánh.
  Future<List<RowData>> shiftTableEmployees() async {
    final db = await _open();
    final scope = await _shiftScope(db);
    return db.rawQuery(
      "SELECT e.id,e.full_name,e.employee_code,e.branch_id,b.name branch_name FROM employees e JOIN branches b ON b.id=e.branch_id WHERE e.status='active' ${scope == null ? '' : 'AND e.branch_id=?'} ORDER BY e.full_name",
      [?scope],
    );
  }

  /// Toàn bộ ca của một nhân viên trong khoảng ngày, kể cả ca nhân viên đã từ chối.
  /// Ca bị quản lý gỡ hoặc hủy không hiện.
  Future<RowData> employeeShiftTable(
    int employeeId, {
    required DateTime from,
    required DateTime to,
  }) async {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start) || end.difference(start).inDays > 92) {
      throw const AuthException('Khoảng ngày không hợp lệ.');
    }
    final db = await _open();
    final scope = await _shiftScope(db);
    final employees = await db.query(
      'employees',
      columns: ['id', 'full_name', 'employee_code', 'branch_id'],
      where: 'id=?',
      whereArgs: [employeeId],
    );
    if (employees.isEmpty) {
      throw const AuthException('Không tìm thấy nhân viên.');
    }
    if (scope != null && employees.single['branch_id'] != scope) {
      throw const AuthException(
        'Chỉ được xử lý chấm công trong chi nhánh của mình.',
      );
    }
    final rows = await db.rawQuery(
      "SELECT a.id assignment_id,s.id shift_id,s.starts_at,s.ends_at,s.branch_id,b.name branch_name,s.status shift_status,a.status assignment_status,a.response_status,a.responded_at,a.response_note,a.assigned_at,COALESCE(ae.full_name,au.username) assigned_by_name,r.check_in_at,r.check_out_at,r.attendance_state "
      "FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id LEFT JOIN users au ON au.id=a.assigned_by LEFT JOIN employees ae ON ae.user_id=a.assigned_by LEFT JOIN attendance_records r ON r.assignment_id=a.id "
      "WHERE a.employee_id=? AND s.status<>'cancelled' AND (a.status<>'cancelled' OR a.response_status='rejected') AND date(s.starts_at,'localtime') BETWEEN ? AND ? ORDER BY s.starts_at",
      [employeeId, day(start), day(end)],
    );
    int count(String status) =>
        rows.where((r) => r['response_status'] == status).length;
    return {
      'employee': employees.single,
      'from': day(start),
      'to': day(end),
      'rows': rows,
      'summary': {
        'total': rows.length,
        'pending': count('pending'),
        'accepted': count('accepted'),
        'rejected': count('rejected'),
      },
    };
  }
}
