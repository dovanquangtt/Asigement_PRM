part of 'workforce_repository.dart';

extension AttendanceManagement on WorkforceRepository {
  Future<int> attendanceNotificationAssignment(String entity, int id) async {
    final db = await _open();
    await _require(db, 'profile.self');
    final sql = switch (entity) {
      'attendance_events' =>
        'SELECT assignment_id FROM attendance_events WHERE id=?',
      'attendance_records' =>
        'SELECT assignment_id FROM attendance_records WHERE id=?',
      'attendance_adjustment_requests' => 'SELECT r.assignment_id FROM attendance_adjustment_requests q JOIN attendance_records r ON r.id=q.attendance_id WHERE q.id=?',
      _ => throw const AuthException('Loại thông báo không hợp lệ.'),
    };
    final rows = await db.rawQuery(sql, [id]);
    if (rows.isEmpty) {
      throw const AuthException('Không tìm thấy dữ liệu chấm công.');
    }
    final assignment = rows.single['assignment_id'] as int;
    await attendanceCaseDetail(assignment);
    return assignment;
  }

  Future<bool> _attendanceIsAdmin(DatabaseExecutor db) async =>
      (await db.rawQuery(
        "SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id WHERE u.id=? AND u.is_active=1 AND r.code='admin'",
        [session.userId],
      )).isNotEmpty;

  Future<int?> _attendanceScope(DatabaseExecutor db) async {
    await _require(db, 'attendance.review');
    if (await _attendanceIsAdmin(db)) return null;
    return (await _me(db))['branch_id'] as int;
  }

  Future<void> _requireAttendanceBranch(
    DatabaseExecutor db,
    int branchId,
  ) async {
    final scope = await _attendanceScope(db);
    if (scope != null && scope != branchId) {
      throw const AuthException(
        'Chỉ được xử lý chấm công trong chi nhánh của mình.',
      );
    }
  }

  Future<List<int>> _attendanceReviewers(
    DatabaseExecutor tx,
    int branchId,
  ) async {
    final people = await tx.rawQuery(
      "SELECT DISTINCT u.id,e.branch_id,r.code FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id LEFT JOIN employees e ON e.user_id=u.id AND e.status='active' WHERE u.is_active=1 AND (r.code='admin' OR (r.code='manager' AND e.branch_id=?))",
      [branchId],
    );
    return people.map((r) => r['id'] as int).toSet().toList();
  }

  Future<void> _ensureAttendanceEditable(
    DatabaseExecutor db,
    int assignmentId,
  ) async {
    final rows = await db.rawQuery(
      "SELECT r.locked_at FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id LEFT JOIN attendance_records r ON r.assignment_id=a.id WHERE a.id=? AND (r.locked_at IS NOT NULL OR EXISTS(SELECT 1 FROM payslips p JOIN payroll_periods pp ON pp.id=p.period_id WHERE p.employee_id=a.employee_id AND p.status IN ('approved','paid') AND date(s.starts_at,'localtime') BETWEEN pp.starts_on AND pp.ends_on))",
      [assignmentId],
    );
    if (rows.isNotEmpty) {
      throw const AuthException(
        'Bảng công hoặc kỳ lương đã chốt, không thể thay đổi.',
      );
    }
  }

  Future<void> _refreshAttendanceMetrics(
    DatabaseExecutor db,
    int assignmentId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT r.*,s.starts_at,s.ends_at,b.require_overtime_approval,COALESCE(t.break_minutes,0) break_minutes,COALESCE(t.late_grace_minutes,0) late_grace_minutes FROM attendance_records r JOIN shift_assignments a ON a.id=r.assignment_id JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id LEFT JOIN shift_templates t ON t.id=s.template_id WHERE a.id=?',
      [assignmentId],
    );
    if (rows.isEmpty) return;
    final r = rows.single;
    final inAt = r['check_in_at'] == null ? null : utcTime(r['check_in_at']);
    final outAt = r['check_out_at'] == null ? null : utcTime(r['check_out_at']);
    if (outAt != null && (inAt == null || outAt.isBefore(inAt))) {
      throw const AuthException('Giờ ra phải từ giờ vào trở đi.');
    }
    final late = inAt == null
        ? 0
        : math.max(
            0,
            inAt.difference(utcTime(r['starts_at'])).inMinutes -
                (r['late_grace_minutes'] as int),
          );
    final worked = inAt == null || outAt == null
        ? 0
        : math.max(
            0,
            outAt.difference(inAt).inMinutes - (r['break_minutes'] as int),
          );
    final extra = outAt == null
        ? 0
        : math.min(
            worked,
            math.max(0, outAt.difference(utcTime(r['ends_at'])).inMinutes),
          );
    final needsReview = r['require_overtime_approval'] == 1 && extra > 0;
    final previousDecision =
        r['overtime_requested_minutes'] == extra &&
        ['APPROVED', 'REJECTED'].contains(r['overtime_status']);
    final otState = needsReview
        ? (previousDecision ? r['overtime_status'] : 'PENDING')
        : 'NOT_REQUIRED';
    await db.update(
      'attendance_records',
      {
        'worked_minutes': worked,
        'late_minutes': late,
        'arrival_status': inAt == null
            ? null
            : late > 0
            ? 'LATE'
            : 'ON_TIME',
        'attendance_state': inAt == null
            ? 'MISSING_CHECK_IN'
            : outAt == null
            ? 'IN_PROGRESS'
            : 'COMPLETED',
        'overtime_requested_minutes': needsReview ? extra : 0,
        'overtime_status': otState,
        'overtime_minutes': !needsReview || otState == 'APPROVED' ? extra : 0,
        if (!previousDecision) 'overtime_reviewed_by': null,
        if (!previousDecision) 'overtime_reviewed_at': null,
        if (!previousDecision) 'overtime_review_note': null,
      },
      where: 'assignment_id=?',
      whereArgs: [assignmentId],
    );
  }

  Future<RowData> attendanceManagement({
    DateTime? day,
    bool self = false,
  }) async {
    final db = await _open();
    final date = day ?? DateTime.now();
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    int? scope, employeeId;
    if (self) {
      await _require(db, 'attendance.self');
      employeeId = (await _me(db))['id'] as int;
    } else {
      scope = await _attendanceScope(db);
    }
    final where = [
      'a.status<>\'cancelled\'',
      's.status<>\'cancelled\'',
      "date(s.starts_at,'localtime')=?",
      if (scope != null) 's.branch_id=?',
      if (employeeId != null) 'a.employee_id=?',
    ];
    final args = <Object?>[dateText, ?scope, ?employeeId];
    final rows = await db.rawQuery(
      "SELECT a.id assignment_id,e.id employee_id,e.user_id,e.full_name,e.employee_code,s.id shift_id,s.branch_id,b.name branch_name,s.starts_at,s.ends_at,s.status shift_status,r.id attendance_id,r.check_in_at,r.check_out_at,r.late_minutes,r.worked_minutes,r.overtime_minutes,r.overtime_requested_minutes,r.overtime_status,r.arrival_status,r.locked_at,q.id adjustment_id,(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id=a.id AND ev.result='pending_review') pending_exceptions FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id JOIN branches b ON b.id=s.branch_id LEFT JOIN attendance_records r ON r.assignment_id=a.id LEFT JOIN attendance_adjustment_requests q ON q.attendance_id=r.id AND q.status='pending' WHERE ${where.join(' AND ')} ORDER BY s.starts_at,e.full_name",
      args,
    );
    final now = DateTime.now().toUtc();
    final entries = rows
        .map(
          (r) => <String, Object?>{
            ...r,
            'work_state': r['check_in_at'] == null
                ? (now.isAfter(utcTime(r['ends_at']))
                      ? 'MISSING_CHECK_IN'
                      : 'NOT_STARTED')
                : r['check_out_at'] == null
                ? (now.isAfter(utcTime(r['ends_at']))
                      ? 'MISSING_CHECK_OUT'
                      : 'IN_PROGRESS')
                : 'COMPLETED',
            'request_state': r['adjustment_id'] != null
                ? 'PENDING_ADJUSTMENT'
                : null,
          },
        )
        .toList();
    final employeeCount = (await db.rawQuery(
      "SELECT COUNT(*) n FROM employees WHERE status='active' ${scope == null ? '' : 'AND branch_id=?'} ${employeeId == null ? '' : 'AND id=?'}",
      [?scope, ?employeeId],
    )).single['n'];
    return {
      'date': dateText,
      'employees': employeeCount,
      'checked_in': entries
          .where((r) => r['check_in_at'] != null)
          .map((r) => r['employee_id'])
          .toSet()
          .length,
      'late': entries
          .where((r) => (r['late_minutes'] as int? ?? 0) > 0)
          .map((r) => r['employee_id'])
          .toSet()
          .length,
      'pending': entries.fold<int>(
        0,
        (n, r) =>
            n +
            (r['pending_exceptions'] as int) +
            (r['adjustment_id'] == null ? 0 : 1) +
            (r['overtime_status'] == 'PENDING' ? 1 : 0),
      ),
      'rows': entries,
    };
  }

  Future<RowData> attendanceCaseDetail(int assignmentId) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT a.id assignment_id,a.employee_id,e.user_id,e.full_name,e.employee_code,s.*,b.name branch_name FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id JOIN branches b ON b.id=s.branch_id WHERE a.id=?',
      [assignmentId],
    );
    if (rows.isEmpty) throw const AuthException('Không tìm thấy phân ca.');
    final s = rows.single;
    if (s['user_id'] == session.userId) {
      await _require(db, 'attendance.self');
    } else {
      await _requireAttendanceBranch(db, s['branch_id'] as int);
    }
    final record = (await db.query(
      'attendance_records',
      where: 'assignment_id=?',
      whereArgs: [assignmentId],
    )).firstOrNull;
    final events = await db.query(
      'attendance_events',
      where: 'assignment_id=?',
      whereArgs: [assignmentId],
      orderBy: 'id',
    );
    final adjustments = record == null
        ? <RowData>[]
        : await db.rawQuery(
            'SELECT q.*,u.username reviewer_name FROM attendance_adjustment_requests q LEFT JOIN users u ON u.id=q.reviewed_by WHERE q.attendance_id=? ORDER BY q.id DESC',
            [record['id']],
          );
    final ids = events.map((r) => r['id']).toList();
    final requestIds = adjustments.map((r) => r['id']).toList();
    final audit = await db.rawQuery(
      "SELECT l.*,u.username actor_name FROM audit_logs l LEFT JOIN users u ON u.id=l.actor_user_id WHERE (l.entity_type='attendance_events' AND l.entity_id IN (${ids.isEmpty ? 'NULL' : List.filled(ids.length, '?').join(',')})) OR (l.entity_type='attendance_adjustment_requests' AND l.entity_id IN (${requestIds.isEmpty ? 'NULL' : List.filled(requestIds.length, '?').join(',')})) OR (l.entity_type='attendance_records' AND l.entity_id=?) ORDER BY l.id DESC",
      [...ids, ...requestIds, record?['id'] ?? -1],
    );
    return {
      'shift': s,
      'record': record,
      'events': events,
      'adjustments': adjustments,
      'audit': audit,
      'can_review':
          await _can(db, 'attendance.review') && s['user_id'] != session.userId,
    };
  }

  Future<int> requestAttendanceAdjustment(
    int assignmentId, {
    DateTime? checkIn,
    DateTime? checkOut,
    required String reason,
    String? evidencePath,
  }) async {
    if (reason.trim().isEmpty || (checkIn == null && checkOut == null)) {
      throw const AuthException('Nhập giờ đề nghị và lý do điều chỉnh.');
    }
    if (evidencePath != null && !File(evidencePath).existsSync()) {
      throw const AuthException('Không đọc được ảnh minh chứng.');
    }
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'attendance.self');
      final me = await _me(tx);
      final shift = await txOwnAssignment(tx, assignmentId, me['id'] as int);
      await _ensureAttendanceEditable(tx, assignmentId);
      if (shift['status'] == 'cancelled') {
        throw const AuthException('Ca đã hủy.');
      }
      var record = (await tx.query(
        'attendance_records',
        where: 'assignment_id=?',
        whereArgs: [assignmentId],
      )).firstOrNull;
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
      final proposedIn =
          checkIn?.toUtc() ??
          (record['check_in_at'] == null
              ? null
              : utcTime(record['check_in_at']));
      final proposedOut =
          checkOut?.toUtc() ??
          (record['check_out_at'] == null
              ? null
              : utcTime(record['check_out_at']));
      final latest = DateTime.now().toUtc().add(const Duration(minutes: 1));
      if (proposedIn != null && proposedIn.isAfter(latest) ||
          proposedOut != null && proposedOut.isAfter(latest)) {
        throw const AuthException('Không đề nghị giờ công chưa xảy ra.');
      }
      if (proposedIn == null ||
          proposedOut != null && proposedOut.isBefore(proposedIn)) {
        throw const AuthException(
          'Cần giờ vào hợp lệ; giờ ra không trước giờ vào.',
        );
      }
      if ((await tx.query(
        'attendance_adjustment_requests',
        where: "attendance_id=? AND status='pending'",
        whereArgs: [record['id']],
      )).isNotEmpty) {
        throw const AuthException('Đã có yêu cầu điều chỉnh đang chờ duyệt.');
      }
      final id = await tx.insert('attendance_adjustment_requests', {
        'attendance_id': record['id'],
        'requested_by': session.userId,
        'requested_check_in': sqlTime(proposedIn),
        'requested_check_out': proposedOut == null
            ? null
            : sqlTime(proposedOut),
        'reason': reason.trim(),
        'before_json': jsonEncode(record),
        'evidence_path': evidencePath,
      });
      await _notify(
        tx,
        await _attendanceReviewers(tx, shift['branch_id'] as int),
        'Yêu cầu bổ sung / sửa công',
        '${me['full_name']} gửi yêu cầu #$id.',
        'attendance_adjustment_requests',
        id,
      );
      await _audit(
        tx,
        'attendance.adjustment.request',
        'attendance_adjustment_requests',
        id,
        {
          'before': record,
          'proposed_in': sqlTime(proposedIn),
          'proposed_out': proposedOut == null ? null : sqlTime(proposedOut),
        },
      );
      return id;
    });
  }

  Future<void> reviewAttendanceAdjustment(
    int requestId,
    bool approve, {
    required String note,
  }) async {
    if (note.trim().isEmpty) throw const AuthException('Nhập nhận xét xử lý.');
    final db = await _open();
    await db.transaction((tx) async {
      final q = (await tx.query(
        'attendance_adjustment_requests',
        where: "id=? AND status='pending'",
        whereArgs: [requestId],
      )).firstOrNull;
      if (q == null) {
        throw const AuthException('Yêu cầu đã xử lý hoặc không tồn tại.');
      }
      final r = (await tx.query(
        'attendance_records',
        where: 'id=?',
        whereArgs: [q['attendance_id']],
      )).single;
      final s = (await tx.rawQuery(
        'SELECT a.employee_id,s.branch_id FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.id=?',
        [r['assignment_id']],
      )).single;
      await _requireAttendanceBranch(tx, s['branch_id'] as int);
      if (q['requested_by'] == session.userId) {
        throw const AuthException('Không được tự duyệt yêu cầu của mình.');
      }
      if (approve) {
        await _ensureAttendanceEditable(tx, r['assignment_id'] as int);
        final owner = await tx.query(
          'employees',
          where: 'id=? AND user_id=?',
          whereArgs: [s['employee_id'], q['requested_by']],
        );
        if (owner.isEmpty) throw const AuthException('Phân ca đã đổi người.');
        if (q['before_json'] == null) {
          throw const AuthException(
            'Yêu cầu cũ thiếu dữ liệu đối chiếu. Hãy từ chối và gửi yêu cầu mới.',
          );
        }
        final original =
            jsonDecode(q['before_json'] as String) as Map<String, dynamic>;
        if (r['check_in_at'] != original['check_in_at'] ||
            r['check_out_at'] != original['check_out_at']) {
          throw const AuthException(
            'Giờ công đã thay đổi sau khi gửi; cần kiểm tra lại yêu cầu.',
          );
        }
        await tx.update(
          'attendance_records',
          {
            'check_in_at': q['requested_check_in'],
            'check_out_at': q['requested_check_out'],
            'status': 'adjusted',
            'approved_by': session.userId,
            'approved_at': sqlTime(DateTime.now()),
          },
          where: 'id=?',
          whereArgs: [r['id']],
        );
        await _refreshAttendanceMetrics(tx, r['assignment_id'] as int);
      }
      await tx.update(
        'attendance_adjustment_requests',
        {
          'status': approve ? 'approved' : 'rejected',
          'reviewed_by': session.userId,
          'reviewed_at': sqlTime(DateTime.now()),
          'review_note': note.trim(),
        },
        where: 'id=?',
        whereArgs: [requestId],
      );
      final after = (await tx.query(
        'attendance_records',
        where: 'id=?',
        whereArgs: [r['id']],
      )).single;
      await _audit(
        tx,
        approve
            ? 'attendance.adjustment.approve'
            : 'attendance.adjustment.reject',
        'attendance_adjustment_requests',
        requestId,
        {'before': r, 'after': after, 'note': note.trim()},
      );
      await _notify(
        tx,
        [q['requested_by'] as int],
        'Kết quả điều chỉnh công',
        'Yêu cầu #$requestId ${approve ? 'đã duyệt' : 'bị từ chối'}. ${note.trim()}',
        'attendance_adjustment_requests',
        requestId,
      );
    });
  }

  Future<void> reviewAttendanceOvertime(
    int assignmentId,
    bool approve, {
    required String note,
  }) async {
    if (note.trim().isEmpty) {
      throw const AuthException('Nhập lý do xác nhận tăng ca.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      final s = (await tx.rawQuery(
        'SELECT s.branch_id,e.user_id FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id WHERE a.id=?',
        [assignmentId],
      )).firstOrNull;
      if (s == null) throw const AuthException('Không tìm thấy phân ca.');
      await _requireAttendanceBranch(tx, s['branch_id'] as int);
      if (s['user_id'] == session.userId) {
        throw const AuthException('Không tự duyệt tăng ca.');
      }
      await _ensureAttendanceEditable(tx, assignmentId);
      final r = (await tx.query(
        'attendance_records',
        where: "assignment_id=? AND overtime_status='PENDING'",
        whereArgs: [assignmentId],
      )).firstOrNull;
      if (r == null) {
        throw const AuthException('Không có tăng ca đang chờ duyệt.');
      }
      await tx.update(
        'attendance_records',
        {
          'overtime_status': approve ? 'APPROVED' : 'REJECTED',
          'overtime_minutes': approve ? r['overtime_requested_minutes'] : 0,
          'overtime_reviewed_by': session.userId,
          'overtime_reviewed_at': sqlTime(DateTime.now()),
          'overtime_review_note': note.trim(),
        },
        where: 'id=?',
        whereArgs: [r['id']],
      );
      await _audit(
        tx,
        'attendance.overtime.review',
        'attendance_records',
        r['id'] as int,
        {
          'approved': approve,
          'note': note.trim(),
          'minutes': r['overtime_requested_minutes'],
        },
      );
      if (s['user_id'] != null) {
        await _notify(
          tx,
          [s['user_id'] as int],
          'Kết quả xác nhận tăng ca',
          approve
              ? 'Tăng ca đã được duyệt.'
              : 'Tăng ca bị từ chối. ${note.trim()}',
          'attendance_records',
          r['id'] as int,
        );
      }
    });
  }

  Future<void> closeAttendanceDay(DateTime day, {String note = ''}) async {
    final overview = await attendanceManagement(day: day);
    final rows = overview['rows'] as List<RowData>;
    if (rows.isEmpty) throw const AuthException('Không có ca để chốt.');
    final db = await _open();
    await db.transaction((tx) async {
      for (final row in rows) {
        final detail = (await tx.rawQuery(
          'SELECT a.id,s.branch_id,s.ends_at,r.id record_id,r.check_in_at,r.check_out_at,r.overtime_status FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id LEFT JOIN attendance_records r ON r.assignment_id=a.id WHERE a.id=?',
          [row['assignment_id']],
        )).single;
        await _requireAttendanceBranch(tx, detail['branch_id'] as int);
        if (detail['check_in_at'] == null ||
            detail['check_out_at'] == null ||
            detail['overtime_status'] == 'PENDING' ||
            utcTime(detail['ends_at']).isAfter(DateTime.now().toUtc())) {
          throw const AuthException(
            'Còn ca chưa hoàn tất hoặc tăng ca chưa xử lý.',
          );
        }
        final pending = (await tx.rawQuery(
          "SELECT 1 FROM attendance_events WHERE assignment_id=? AND result='pending_review' UNION ALL SELECT 1 FROM attendance_adjustment_requests WHERE attendance_id=? AND status='pending'",
          [row['assignment_id'], detail['record_id']],
        ));
        if (pending.isNotEmpty) {
          throw const AuthException('Còn yêu cầu ngoại lệ chưa xử lý.');
        }
        await tx.update(
          'attendance_records',
          {'locked_by': session.userId, 'locked_at': sqlTime(DateTime.now())},
          where: 'id=?',
          whereArgs: [detail['record_id']],
        );
        await _audit(
          tx,
          'attendance.close',
          'attendance_records',
          detail['record_id'] as int,
          {'date': overview['date'], 'note': note.trim()},
        );
      }
    });
  }
}
