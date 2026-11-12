part of 'workforce_repository.dart';

/// M05 Đổi ca giữa hai nhân viên: người gửi chọn ca của mình và ca muốn đổi của người khác, người
/// nhận đồng ý hoặc từ chối, và chỉ khi cả hai đồng ý quản lý (không tham gia) mới duyệt.
/// Duyệt/phản hồi nằm ở `respondSwap` (workforce_operations.dart).
extension ShiftSwap on WorkforceRepository {
  Future<RowData?> _swapAssignment(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery(
      'SELECT a.id,a.employee_id,a.shift_id,a.status,s.starts_at,s.ends_at,s.branch_id,s.status shift_status,b.name branch_name,e.full_name,e.employee_code '
      'FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id JOIN employees e ON e.id=a.employee_id WHERE a.id=?',
      [id],
    );
    return rows.firstOrNull;
  }

  /// Lý do một phân ca không thể đem đi đổi (null = đổi được): ca phải còn hiệu lực, chưa bắt đầu,
  /// chưa có điểm danh và chưa nằm trong yêu cầu đổi nào đang chờ.
  Future<String?> _swapBlocker(DatabaseExecutor db, RowData a) async {
    if (a['status'] != 'assigned' || a['shift_status'] != 'scheduled') {
      return 'Ca đã đóng hoặc đã hủy.';
    }
    if (!utcTime(a['starts_at']).isAfter(DateTime.now().toUtc())) {
      return 'Ca đã bắt đầu hoặc đã kết thúc.';
    }
    if ((await db.query(
      'attendance_events',
      columns: ['id'],
      where: 'assignment_id=?',
      whereArgs: [a['id']],
      limit: 1,
    )).isNotEmpty) {
      return 'Ca đã có điểm danh.';
    }
    if ((await db.rawQuery(
      "SELECT id FROM shift_swap_requests WHERE status='pending' AND (from_assignment_id=? OR to_assignment_id=?) LIMIT 1",
      [a['id'], a['id']],
    )).isNotEmpty) {
      return 'Ca đang có yêu cầu đổi chờ xử lý.';
    }
    return null;
  }

  RowData _swapShiftOf(RowData a) => {
    'branch_id': a['branch_id'],
    'status': a['shift_status'],
    'starts_at': a['starts_at'],
    'ends_at': a['ends_at'],
  };

  /// Lý do hai phân ca không đổi cho nhau được (null = đổi được): khác ca, và sau khi đổi mỗi
  /// người không bị trùng giờ với ca khác hay đợt nghỉ phép đã duyệt của mình.
  Future<String?> _swapConflict(
    DatabaseExecutor db,
    RowData mine,
    RowData theirs,
  ) async {
    if (mine['shift_id'] == theirs['shift_id']) {
      return 'Hai phân ca phải thuộc hai ca khác nhau.';
    }
    final ignoring = [mine['id'] as int, theirs['id'] as int];
    try {
      await _available(
        db,
        theirs['employee_id'] as int,
        _swapShiftOf(mine),
        ignoring: ignoring,
      );
    } on AuthException catch (e) {
      return '${theirs['full_name']}: ${e.message}';
    }
    try {
      await _available(
        db,
        mine['employee_id'] as int,
        _swapShiftOf(theirs),
        ignoring: ignoring,
      );
    } on AuthException catch (e) {
      return 'Bạn: ${e.message}';
    }
    return null;
  }

  /// Các ca của nhân viên khác (cùng chi nhánh) mà [assignmentId] của mình có thể đổi được ngay:
  /// ca tương lai, chưa điểm danh, chưa có yêu cầu đổi chờ, và hai bên không bị trùng giờ/nghỉ phép.
  /// Xếp theo ngày từ bé đến lớn.
  Future<List<RowData>> swapOptions(int assignmentId) async {
    final db = await _open();
    await _require(db, 'swaps.self');
    final me = await _me(db);
    final mine = await _swapAssignment(db, assignmentId);
    if (mine == null || mine['employee_id'] != me['id']) {
      throw const AuthException('Phân ca không thuộc bạn.');
    }
    if (await _swapBlocker(db, mine) != null) return [];
    final candidates = await db.rawQuery(
      'SELECT a.id,a.employee_id,a.shift_id,a.status,s.starts_at,s.ends_at,s.branch_id,s.status shift_status,b.name branch_name,e.full_name,e.employee_code '
      'FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id '
      'JOIN employees e ON e.id=a.employee_id JOIN users u ON u.id=e.user_id AND u.is_active=1 '
      "WHERE e.status='active' AND a.employee_id<>? AND a.status='assigned' AND s.status='scheduled' "
      'AND s.branch_id=? AND s.starts_at>? ORDER BY s.starts_at,e.full_name',
      [me['id'], mine['branch_id'], sqlTime(DateTime.now())],
    );
    final result = <RowData>[];
    for (final t in candidates) {
      if (await _swapBlocker(db, t) != null) continue;
      if (await _swapConflict(db, mine, t) != null) continue;
      result.add(t);
    }
    return result;
  }

  /// Các ca sắp tới của chính mình, mỗi ca kèm số ca có thể đổi (`options_count`) hoặc lý do chưa
  /// đổi được (`blocker`). Dùng cho màn "Ca có thể đổi".
  Future<List<RowData>> swappableShifts() async {
    final db = await _open();
    await _require(db, 'swaps.self');
    final me = await _me(db);
    final rows = await db.rawQuery(
      'SELECT a.id,a.id assignment_id,a.employee_id,a.shift_id,a.status,s.starts_at,s.ends_at,s.branch_id,s.status shift_status,b.name branch_name '
      'FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id '
      "WHERE a.employee_id=? AND a.status='assigned' AND s.status='scheduled' AND s.starts_at>? ORDER BY s.starts_at",
      [me['id'], sqlTime(DateTime.now())],
    );
    final result = <RowData>[];
    for (final a in rows) {
      final blocker = await _swapBlocker(db, a);
      final options = blocker == null
          ? (await swapOptions(a['id'] as int)).length
          : 0;
      final open = blocker == null
          ? (await openSwapTargets(a['id'] as int)).length
          : 0;
      result.add({
        ...a,
        'blocker': blocker,
        'options_count': options,
        'open_count': open,
      });
    }
    return result;
  }

  /// Gửi yêu cầu đổi ca [from] (của mình) lấy ca [to] (của người khác). Người nhận được báo ngay.
  Future<void> requestSwap(int from, int to, String reason) async {
    if (reason.trim().isEmpty || from == to) {
      throw const AuthException('Chọn ca khác và nhập lý do.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'swaps.self');
      final me = await _me(tx);
      final own = await _swapAssignment(tx, from);
      if (own == null || own['employee_id'] != me['id']) {
        throw const AuthException('Phân ca không thuộc bạn.');
      }
      final target = await _swapAssignment(tx, to);
      final now = DateTime.now().toUtc();
      if (target == null ||
          target['status'] != 'assigned' ||
          target['shift_status'] != 'scheduled' ||
          target['employee_id'] == me['id'] ||
          target['branch_id'] != own['branch_id'] ||
          !utcTime(target['starts_at']).isAfter(now) ||
          !utcTime(own['starts_at']).isAfter(now)) {
        throw const AuthException(
          'Chỉ đổi ca tương lai với nhân viên khác cùng chi nhánh.',
        );
      }
      await _requireAccount(tx, target['employee_id'] as int);
      final ownBlock = await _swapBlocker(tx, own);
      if (ownBlock != null) throw AuthException('Ca của bạn: $ownBlock');
      final targetBlock = await _swapBlocker(tx, target);
      if (targetBlock != null) {
        throw AuthException('Ca của ${target['full_name']}: $targetBlock');
      }
      final conflict = await _swapConflict(tx, own, target);
      if (conflict != null) throw AuthException(conflict);
      final requestId = await tx.insert('shift_swap_requests', {
        'from_assignment_id': from,
        'to_assignment_id': to,
        'requested_by': session.userId,
        'from_employee_id': own['employee_id'],
        'to_employee_id': target['employee_id'],
        'reason': reason.trim(),
      });
      await _audit(tx, 'swap.request', 'shift_swap_requests', requestId);
      await _notify(
        tx,
        await _employeeUsers(tx, [target['employee_id'] as int]),
        'Yêu cầu đổi ca mới',
        '${me['full_name']} muốn đổi ca ${_shiftLabel(own)} lấy ca ${_shiftLabel(target)} của bạn. '
            'Lý do: ${reason.trim()}. Hãy đồng ý hoặc từ chối.',
        'shift_swap_requests',
        requestId,
      );
    });
  }

  /// Người gửi rút lại yêu cầu đang chờ (cả khi người nhận đã đồng ý nhưng quản lý chưa duyệt).
  Future<void> cancelSwap(int id) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'swaps.self');
      final r = (await tx.query(
        'shift_swap_requests',
        where: 'id=?',
        whereArgs: [id],
      )).firstOrNull;
      if (r == null) throw const AuthException('Không tìm thấy yêu cầu.');
      if (r['requested_by'] != session.userId) {
        throw const AuthException('Chỉ người gửi mới hủy được yêu cầu.');
      }
      if (r['status'] != 'pending') {
        throw const AuthException('Yêu cầu đã được xử lý.');
      }
      await tx.update(
        'shift_swap_requests',
        {'status': 'cancelled'},
        where: 'id=?',
        whereArgs: [id],
      );
      await _audit(tx, 'swap.cancel', 'shift_swap_requests', id);
      final counterpart = await _employeeUsers(tx, [
        r['to_employee_id'] as int,
      ]);
      await _notify(
        tx,
        [
          ...counterpart,
          if (r['counterpart_status'] == 'accepted')
            ...await _reviewers(tx, 'swaps.review', excluding: counterpart),
        ],
        'Yêu cầu đổi ca đã bị hủy',
        'Người gửi đã rút lại yêu cầu đổi ca. Lịch ca được giữ nguyên.',
        'shift_swap_requests',
        id,
      );
    });
  }

  /// Yêu cầu đổi ca: Admin/quản lý thấy tất cả, nhân viên thấy yêu cầu mình gửi hoặc nhận.
  /// Yêu cầu còn chờ xếp lên đầu, rồi mới nhất trước.
  Future<List<RowData>> swaps() async {
    final db = await _open();
    final managing = await _can(db, 'swaps.review');
    if (!managing) await _require(db, 'swaps.self');
    return db.rawQuery(
      'SELECT r.*,f.full_name AS from_name,f.employee_code AS from_code,t.full_name AS to_name,t.employee_code AS to_code,'
      't.user_id AS target_user_id,f.user_id AS from_user_id,sf.starts_at AS from_start,sf.ends_at AS from_end,'
      'st.starts_at AS to_start,st.ends_at AS to_end,b.name AS branch_name,ru.username AS reviewer_name '
      'FROM shift_swap_requests r JOIN shift_assignments af ON af.id=r.from_assignment_id '
      'JOIN shift_assignments ato ON ato.id=r.to_assignment_id JOIN employees f ON f.id=r.from_employee_id '
      'JOIN employees t ON t.id=r.to_employee_id JOIN shifts sf ON sf.id=af.shift_id JOIN shifts st ON st.id=ato.shift_id '
      'JOIN branches b ON b.id=sf.branch_id LEFT JOIN users ru ON ru.id=r.reviewed_by '
      '${managing ? '' : 'WHERE r.requested_by=? OR t.user_id=? '}'
      "ORDER BY CASE r.status WHEN 'pending' THEN 0 ELSE 1 END,r.id DESC",
      managing ? [] : [session.userId, session.userId],
    );
  }
}
