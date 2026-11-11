part of 'workforce_repository.dart';

/// M06 Nghỉ phép: số ngày phép của nhân viên, quản lý duyệt/từ chối yêu cầu nghỉ phép.
/// Nhân viên gửi yêu cầu và xem lịch sử ở `createLeaveRequest` / `employeeLeaveRequests`.
extension LeaveManagement on WorkforceRepository {
  /// Số ngày phép của chính mình trong [year] (mặc định năm hiện tại), theo từng loại nghỉ.
  /// Một ngày phép = 480 phút. `remaining_minutes` đã trừ các yêu cầu đang chờ duyệt.
  Future<List<RowData>> leaveBalances({int? year}) async {
    final db = await _open();
    await _require(db, 'schedule.self');
    final me = await _me(db);
    final y = year ?? DateTime.now().year;
    final rows = await db.rawQuery(
      '''
      SELECT t.id leave_type_id,t.code,t.name,t.is_paid,
        COALESCE(b.granted_minutes,0) granted_minutes,
        COALESCE(b.used_minutes,0) used_minutes,
        COALESCE((SELECT SUM(l.requested_minutes) FROM leave_requests l
          WHERE l.employee_id=? AND l.leave_type_id=t.id AND l.status='pending'
          AND CAST(strftime('%Y',l.starts_at,'localtime') AS INTEGER)=?),0) pending_minutes
      FROM leave_types t
      LEFT JOIN leave_balances b ON b.leave_type_id=t.id AND b.employee_id=? AND b.year=?
      ORDER BY t.name
      ''',
      [me['id'], y, me['id'], y],
    );
    return [
      for (final r in rows)
        {
          ...r,
          'remaining_minutes':
              (r['granted_minutes'] as int) -
              (r['used_minutes'] as int) -
              (r['pending_minutes'] as int),
        },
    ];
  }

  /// Yêu cầu nghỉ phép cần quản lý xử lý: Admin thấy tất cả, quản lý theo chi nhánh.
  /// Yêu cầu đang chờ được xếp lên đầu.
  Future<List<RowData>> leaveRequestsForReview() async {
    final db = await _open();
    final scope = await _shiftScope(db);
    return db.rawQuery(
      '''
      SELECT l.*,t.name leave_type_name,t.is_paid,e.full_name,e.employee_code,b.name branch_name,
        COALESCE(lb.granted_minutes,0)-COALESCE(lb.used_minutes,0) remaining_minutes
      FROM leave_requests l
      JOIN leave_types t ON t.id=l.leave_type_id
      JOIN employees e ON e.id=l.employee_id
      JOIN branches b ON b.id=e.branch_id
      LEFT JOIN leave_balances lb ON lb.employee_id=l.employee_id AND lb.leave_type_id=l.leave_type_id
        AND lb.year=CAST(strftime('%Y',l.starts_at,'localtime') AS INTEGER)
      ${scope == null ? '' : 'WHERE e.branch_id=?'}
      ORDER BY CASE l.status WHEN 'pending' THEN 0 ELSE 1 END,l.starts_at DESC
      ''',
      [?scope],
    );
  }

  /// Duyệt hoặc từ chối một yêu cầu nghỉ phép đang chờ. Từ chối bắt buộc có lý do.
  /// Duyệt: loại nghỉ có lương phải còn đủ số ngày phép, nhân viên không còn ca trong thời gian
  /// nghỉ, và số phút nghỉ được trừ vào số dư. Nhân viên được thông báo kết quả.
  Future<void> reviewLeaveRequest(
    int requestId,
    bool approve, {
    String note = '',
  }) async {
    final reason = note.trim();
    if (!approve && reason.isEmpty) {
      throw const AuthException('Nhập lý do từ chối nghỉ phép.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      final scope = await _shiftScope(tx);
      final rows = await tx.rawQuery(
        'SELECT l.*,t.is_paid,t.name leave_type_name,e.user_id,e.branch_id,e.full_name FROM leave_requests l JOIN leave_types t ON t.id=l.leave_type_id JOIN employees e ON e.id=l.employee_id WHERE l.id=?',
        [requestId],
      );
      if (rows.isEmpty) {
        throw const AuthException('Không tìm thấy yêu cầu nghỉ phép.');
      }
      final leave = rows.single;
      if (scope != null && scope != leave['branch_id']) {
        throw const AuthException(
          'Chỉ được xử lý nghỉ phép trong chi nhánh của mình.',
        );
      }
      if (leave['user_id'] == session.userId) {
        throw const AuthException('Không thể tự duyệt nghỉ phép của mình.');
      }
      if (leave['status'] != 'pending') {
        throw const AuthException('Yêu cầu đã được xử lý.');
      }
      final minutes = leave['requested_minutes'] as int;
      final year = utcTime(leave['starts_at']).toLocal().year;
      if (approve) {
        final balance = (await tx.query(
          'leave_balances',
          where: 'employee_id=? AND leave_type_id=? AND year=?',
          whereArgs: [leave['employee_id'], leave['leave_type_id'], year],
        )).firstOrNull;
        if (leave['is_paid'] == 1 &&
            (balance == null ||
                (balance['granted_minutes'] as int) -
                        (balance['used_minutes'] as int) <
                    minutes)) {
          throw const AuthException('Không đủ số ngày phép còn lại.');
        }
        final overlapping = await tx.rawQuery(
          "SELECT 1 FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.employee_id=? AND a.status='assigned' AND s.status<>'cancelled' AND s.starts_at<? AND s.ends_at>? LIMIT 1",
          [leave['employee_id'], leave['ends_at'], leave['starts_at']],
        );
        if (overlapping.isNotEmpty) {
          throw const AuthException(
            'Nhân viên đang có ca trong thời gian nghỉ. Hãy gỡ hoặc đổi ca trước khi duyệt.',
          );
        }
        if (balance != null) {
          await tx.rawUpdate(
            'UPDATE leave_balances SET used_minutes=used_minutes+? WHERE employee_id=? AND leave_type_id=? AND year=?',
            [minutes, leave['employee_id'], leave['leave_type_id'], year],
          );
        }
      }
      await tx.update(
        'leave_requests',
        {
          'status': approve ? 'approved' : 'rejected',
          'reviewed_by': session.userId,
          'reviewed_at': sqlTime(DateTime.now()),
          'review_note': reason,
        },
        where: 'id=?',
        whereArgs: [requestId],
      );
      await _audit(
        tx,
        approve ? 'leave.approve' : 'leave.reject',
        'leave_requests',
        requestId,
      );
      final userId = leave['user_id'] as int?;
      await _notify(
        tx,
        userId == null ? const <int>[] : [userId],
        'Kết quả duyệt nghỉ phép',
        'Yêu cầu nghỉ phép ${leave['leave_type_name']} của bạn ${approve ? 'đã được duyệt' : 'bị từ chối'}.${reason.isEmpty ? '' : ' $reason'}',
        'leave_requests',
        requestId,
      );
    });
  }
}
