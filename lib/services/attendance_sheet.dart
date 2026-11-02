part of 'workforce_repository.dart';

/// Bảng điểm danh theo nhân viên: nhân viên chỉ xem, quản lý/Admin xem theo từng
/// nhân viên và được sửa giờ công hoặc hủy công trực tiếp (bắt buộc ghi lý do).
extension AttendanceSheet on WorkforceRepository {
  /// Nhân viên có thể chọn trong bảng điểm danh: Admin thấy tất cả, quản lý theo chi nhánh,
  /// nhân viên chỉ thấy chính mình.
  Future<List<RowData>> attendanceSheetEmployees() async {
    final db = await _open();
    if (!await _can(db, 'attendance.review')) {
      await _require(db, 'attendance.self');
      final me = await _me(db);
      return [
        {
          'id': me['id'],
          'full_name': me['full_name'],
          'employee_code': me['employee_code'],
          'branch_id': me['branch_id'],
        },
      ];
    }
    final scope = await _attendanceScope(db);
    return db.rawQuery(
      "SELECT id,full_name,employee_code,branch_id FROM employees WHERE status='active' ${scope == null ? '' : 'AND branch_id=?'} ORDER BY full_name",
      [?scope],
    );
  }

  /// Trạng thái hiển thị của một ca trong bảng điểm danh.
  static String sheetStatus(RowData r, DateTime now) {
    if (r['attendance_state'] == 'VOIDED') return 'VOIDED';
    final hasIn = r['check_in_at'] != null, hasOut = r['check_out_at'] != null;
    if (hasIn && hasOut) return 'SUCCESS';
    if ((r['pending_events'] as int? ?? 0) > 0) return 'PENDING_REVIEW';
    final ended = utcTime(r['ends_at']).isBefore(now);
    if (hasIn) return ended ? 'MISSING_CHECK_OUT' : 'IN_PROGRESS';
    if ((r['rejected_events'] as int? ?? 0) > 0) return 'REJECTED';
    return ended ? 'MISSING_CHECK_IN' : 'NOT_STARTED';
  }

  Future<RowData> attendanceSheet({
    int? employeeId,
    required DateTime from,
    required DateTime to,
    DateTime? now,
  }) async {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start) || end.difference(start).inDays > 92) {
      throw const AuthException('Khoảng ngày không hợp lệ.');
    }
    final db = await _open();
    int? scope;
    int? target;
    if (await _can(db, 'attendance.review')) {
      scope = await _attendanceScope(db);
      target = employeeId;
      if (target != null && scope != null) {
        final inScope = await db.query(
          'employees',
          columns: ['id'],
          where: 'id=? AND branch_id=?',
          whereArgs: [target, scope],
        );
        if (inScope.isEmpty) {
          throw const AuthException(
            'Chỉ được xử lý chấm công trong chi nhánh của mình.',
          );
        }
      }
    } else {
      await _require(db, 'attendance.self');
      final me = await _me(db);
      if (employeeId != null && employeeId != me['id']) {
        throw const AuthException(
          'Tài khoản không có quyền thực hiện thao tác này.',
        );
      }
      target = me['id'] as int;
    }
    final rows = await db.rawQuery(
      "SELECT a.id assignment_id,e.id employee_id,e.user_id,e.full_name,e.employee_code,s.id shift_id,s.branch_id,b.name branch_name,s.starts_at,s.ends_at,"
      "r.id attendance_id,r.check_in_at,r.check_out_at,r.worked_minutes,r.late_minutes,r.overtime_minutes,r.overtime_status,r.arrival_status,r.status record_status,r.attendance_state,r.locked_at,"
      "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id=a.id AND ev.result='accepted') accepted_events,"
      "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id=a.id AND ev.result='pending_review') pending_events,"
      "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id=a.id AND ev.result='rejected') rejected_events,"
      "(SELECT ev.rejection_reason FROM attendance_events ev WHERE ev.assignment_id=a.id AND ev.result='rejected' ORDER BY ev.id DESC LIMIT 1) last_rejection_reason "
      "FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id JOIN branches b ON b.id=s.branch_id "
      "LEFT JOIN attendance_records r ON r.assignment_id=a.id "
      "WHERE a.status<>'cancelled' AND s.status<>'cancelled' AND date(s.starts_at,'localtime') BETWEEN ? AND ? "
      "${scope == null ? '' : 'AND s.branch_id=? '}${target == null ? '' : 'AND a.employee_id=? '}"
      "ORDER BY s.starts_at,e.full_name",
      [day(start), day(end), ?scope, ?target],
    );
    final clock = (now ?? DateTime.now()).toUtc();
    final entries = [
      for (final r in rows)
        <String, Object?>{...r, 'sheet_status': sheetStatus(r, clock)},
    ];
    int count(String status) =>
        entries.where((r) => r['sheet_status'] == status).length;
    RowData? employee;
    if (target != null) {
      employee = (await db.query(
        'employees',
        columns: ['id', 'full_name', 'employee_code'],
        where: 'id=?',
        whereArgs: [target],
      )).firstOrNull;
    }
    return {
      'from': day(start),
      'to': day(end),
      'employee': employee,
      'rows': entries,
      'summary': {
        'total': entries.length,
        'success': count('SUCCESS'),
        'pending_review': count('PENDING_REVIEW'),
        'rejected': count('REJECTED'),
        'missing':
            count('MISSING_CHECK_IN') + count('MISSING_CHECK_OUT'),
        'voided': count('VOIDED'),
        'worked_minutes': entries.fold<int>(
          0,
          (n, r) => n + (r['worked_minutes'] as int? ?? 0),
        ),
        'late_count': entries
            .where((r) => (r['late_minutes'] as int? ?? 0) > 0)
            .length,
      },
    };
  }

  /// Kiểm tra chung cho sửa/hủy công trực tiếp; trả về dòng phân ca và công hiện tại.
  Future<({RowData assignment, RowData? record})> _directEditContext(
    DatabaseExecutor tx,
    int assignmentId,
  ) async {
    final scope = await _attendanceScope(tx);
    final rows = await tx.rawQuery(
      'SELECT a.id,a.status assignment_status,a.employee_id,e.user_id,e.full_name,s.branch_id,s.status shift_status FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id WHERE a.id=?',
      [assignmentId],
    );
    if (rows.isEmpty) throw const AuthException('Không tìm thấy phân ca.');
    final a = rows.single;
    if (scope != null && scope != a['branch_id']) {
      throw const AuthException(
        'Chỉ được xử lý chấm công trong chi nhánh của mình.',
      );
    }
    if (a['user_id'] == session.userId) {
      throw const AuthException('Không được tự sửa công của mình.');
    }
    if (a['assignment_status'] == 'cancelled' ||
        a['shift_status'] == 'cancelled') {
      throw const AuthException('Ca đã hủy.');
    }
    await _ensureAttendanceEditable(tx, assignmentId);
    final record = (await tx.query(
      'attendance_records',
      where: 'assignment_id=?',
      whereArgs: [assignmentId],
    )).firstOrNull;
    return (assignment: a, record: record);
  }

  /// Gỡ các yêu cầu còn chờ xử lý vì quản lý đã quyết định trực tiếp.
  Future<void> _supersedePending(
    DatabaseExecutor tx,
    int assignmentId,
    int? recordId,
    String rejection,
    List<String> eventResults,
  ) async {
    await tx.rawUpdate(
      "UPDATE attendance_events SET result='rejected',rejection_reason=?,reviewed_by=?,reviewed_at=? WHERE assignment_id=? AND result IN (${eventResults.map((_) => '?').join(',')})",
      [
        rejection,
        session.userId,
        sqlTime(DateTime.now()),
        assignmentId,
        ...eventResults,
      ],
    );
    if (recordId != null) {
      await tx.update(
        'attendance_adjustment_requests',
        {'status': 'cancelled'},
        where: "attendance_id=? AND status='pending'",
        whereArgs: [recordId],
      );
    }
  }

  /// Quản lý/Admin sửa giờ vào/ra trực tiếp. Giờ không truyền giữ nguyên giờ hiện có.
  Future<void> adminEditAttendance(
    int assignmentId, {
    DateTime? checkIn,
    DateTime? checkOut,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const AuthException('Nhập lý do chỉnh công.');
    }
    if (checkIn == null && checkOut == null) {
      throw const AuthException('Nhập giờ vào hoặc giờ ra cần chỉnh.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      final ctx = await _directEditContext(tx, assignmentId);
      var record = ctx.record;
      if (record == null) {
        final id = await tx.insert('attendance_records', {
          'assignment_id': assignmentId,
          'status': 'pending',
          'attendance_state': 'MISSING_CHECK_IN',
        });
        record = (await tx.query(
          'attendance_records',
          where: 'id=?',
          whereArgs: [id],
        )).single;
      }
      final voided = record['attendance_state'] == 'VOIDED';
      await tx.update(
        'attendance_records',
        {
          if (checkIn != null) 'check_in_at': sqlTime(checkIn),
          if (checkOut != null) 'check_out_at': sqlTime(checkOut),
          'status': 'adjusted',
          'approved_by': session.userId,
          'approved_at': sqlTime(DateTime.now()),
        },
        where: 'id=?',
        whereArgs: [record['id']],
      );
      // Khôi phục công đã hủy chỉ giữ giờ mới, không giữ giờ cũ đã bị xóa.
      if (voided && (checkIn == null || checkOut == null)) {
        await tx.update(
          'attendance_records',
          {
            if (checkIn == null) 'check_in_at': null,
            if (checkOut == null) 'check_out_at': null,
          },
          where: 'id=?',
          whereArgs: [record['id']],
        );
      }
      await _refreshAttendanceMetrics(tx, assignmentId);
      await _supersedePending(
        tx,
        assignmentId,
        record['id'] as int,
        'Đã chỉnh công trực tiếp: ${reason.trim()}',
        ['pending_review'],
      );
      final after = (await tx.query(
        'attendance_records',
        where: 'id=?',
        whereArgs: [record['id']],
      )).single;
      await _audit(
        tx,
        'attendance.admin_edit',
        'attendance_records',
        record['id'] as int,
        {'before': record, 'after': after, 'reason': reason.trim()},
      );
      await _notify(
        tx,
        [ctx.assignment['user_id'] as int?].whereType<int>(),
        'Giờ công đã được chỉnh',
        'Quản lý đã chỉnh giờ công của bạn. Lý do: ${reason.trim()}',
        'attendance_records',
        record['id'] as int,
      );
    });
  }

  /// Hủy công: xóa giờ vào/ra và số phút, ghi trạng thái VOIDED. Nhân viên không tự
  /// điểm danh lại được; quản lý có thể khôi phục bằng cách chỉnh lại giờ công.
  Future<void> voidAttendance(int assignmentId, {required String reason}) async {
    if (reason.trim().isEmpty) {
      throw const AuthException('Nhập lý do hủy công.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      final ctx = await _directEditContext(tx, assignmentId);
      var record = ctx.record;
      if (record == null) {
        final id = await tx.insert('attendance_records', {
          'assignment_id': assignmentId,
        });
        record = (await tx.query(
          'attendance_records',
          where: 'id=?',
          whereArgs: [id],
        )).single;
      }
      await tx.update(
        'attendance_records',
        {
          'check_in_at': null,
          'check_out_at': null,
          'worked_minutes': 0,
          'overtime_minutes': 0,
          'late_minutes': 0,
          'overtime_requested_minutes': 0,
          'overtime_status': 'NOT_REQUIRED',
          'arrival_status': null,
          'status': 'absent',
          'attendance_state': 'VOIDED',
          'approved_by': session.userId,
          'approved_at': sqlTime(DateTime.now()),
        },
        where: 'id=?',
        whereArgs: [record['id']],
      );
      await _supersedePending(
        tx,
        assignmentId,
        record['id'] as int,
        'Đã hủy công: ${reason.trim()}',
        ['accepted', 'pending_review'],
      );
      await _audit(
        tx,
        'attendance.void',
        'attendance_records',
        record['id'] as int,
        {'before': record, 'reason': reason.trim()},
      );
      await _notify(
        tx,
        [ctx.assignment['user_id'] as int?].whereType<int>(),
        'Công bị hủy',
        'Quản lý đã hủy công của bạn. Lý do: ${reason.trim()}',
        'attendance_records',
        record['id'] as int,
      );
    });
  }
}
