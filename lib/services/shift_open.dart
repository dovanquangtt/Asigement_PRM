part of 'workforce_repository.dart';

/// Ca còn trống: khi quản lý tạo ca, nhân viên cùng chi nhánh được báo "Có ca làm mới" nhưng ca chưa
/// thuộc về ai nên không nằm trong lịch cá nhân. Nhân viên xem các ca còn chỗ ở đây và tự đăng ký.
extension OpenShifts on WorkforceRepository {
  /// Ca sắp tới của chi nhánh tôi còn chỗ và tôi chưa được phân vào, sớm nhất trước.
  Future<List<RowData>> openShifts() async {
    final db = await _open();
    await _require(db, 'schedule.self');
    final me = await _me(db);
    final rows = await db.rawQuery(
      'SELECT s.*,b.name branch_name,'
      "(SELECT COUNT(*) FROM shift_assignments x WHERE x.shift_id=s.id AND x.status<>'cancelled') assigned_count "
      'FROM shifts s JOIN branches b ON b.id=s.branch_id '
      "WHERE s.branch_id=? AND s.status='scheduled' AND s.starts_at>? "
      "AND NOT EXISTS (SELECT 1 FROM shift_assignments x WHERE x.shift_id=s.id AND x.employee_id=? AND x.status<>'cancelled') "
      'ORDER BY s.starts_at',
      [me['branch_id'], sqlTime(DateTime.now()), me['id']],
    );
    return [
      for (final s in rows)
        if ((s['assigned_count'] as int) < (s['required_staff'] as int)) s,
    ];
  }

  /// Nhân viên tự đăng ký một ca còn trống: có hiệu lực ngay (đã chấp nhận), quản lý được báo và vẫn
  /// có thể gỡ phân công. Từ chối khi ca đã đủ người, đã bắt đầu, khác chi nhánh hoặc trùng giờ.
  Future<void> registerForShift(int shiftId) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'schedule.self');
      final me = await _me(tx);
      final shift = (await tx.query(
        'shifts',
        where: 'id=?',
        whereArgs: [shiftId],
      )).firstOrNull;
      if (shift == null) throw const AuthException('Không tìm thấy ca.');
      if (shift['branch_id'] != me['branch_id']) {
        throw const AuthException('Ca này thuộc chi nhánh khác.');
      }
      if (shift['status'] != 'scheduled' ||
          !utcTime(shift['starts_at']).isAfter(DateTime.now().toUtc())) {
        throw const AuthException(
          'Ca đã bắt đầu hoặc đã đóng, không đăng ký được.',
        );
      }
      await _available(tx, me['id'] as int, shift);
      final count =
          (await tx.rawQuery(
                "SELECT COUNT(*) n FROM shift_assignments WHERE shift_id=? AND status<>'cancelled'",
                [shiftId],
              )).single['n']
              as int;
      if (count >= (shift['required_staff'] as int)) {
        throw const AuthException('Ca đã đủ nhân viên.');
      }
      final old = await tx.query(
        'shift_assignments',
        where: 'shift_id=? AND employee_id=?',
        whereArgs: [shiftId, me['id']],
      );
      final now = sqlTime(DateTime.now());
      final data = {
        'shift_id': shiftId,
        'employee_id': me['id'],
        'assigned_by': session.userId,
        'status': 'assigned',
        'response_status': 'accepted',
        'responded_at': now,
        'response_note': 'Nhân viên tự đăng ký',
      };
      final id = old.isEmpty
          ? await tx.insert('shift_assignments', data)
          : old.single['id'] as int;
      if (old.isNotEmpty) {
        await tx.update(
          'shift_assignments',
          data,
          where: 'id=?',
          whereArgs: [id],
        );
      }
      await _audit(tx, 'shift.self_register', 'shift_assignments', id);
      await _notify(
        tx,
        await _reviewers(tx, 'shifts.manage', excluding: [session.userId]),
        'Nhân viên đăng ký ca',
        '${me['full_name']} đăng ký ca ${_shiftLabel(shift)}.',
        'shifts',
        shiftId,
      );
    });
  }

  /// Ca còn trống mà ca [assignmentId] của tôi có thể đổi sang: không trùng giờ với ca khác của tôi
  /// (bỏ qua chính ca đang đổi). Rỗng nếu ca của tôi chưa đổi được (đã điểm danh, đang chờ đổi…).
  Future<List<RowData>> openSwapTargets(int assignmentId) async {
    final db = await _open();
    await _require(db, 'swaps.self');
    final me = await _me(db);
    final mine = await _swapAssignment(db, assignmentId);
    if (mine == null || mine['employee_id'] != me['id']) {
      throw const AuthException('Phân ca không thuộc bạn.');
    }
    if (await _swapBlocker(db, mine) != null) return [];
    final result = <RowData>[];
    for (final s in await openShifts()) {
      if (s['id'] == mine['shift_id']) continue;
      try {
        await _available(db, me['id'] as int, s, ignoring: [assignmentId]);
        result.add(s);
      } on AuthException {
        continue;
      }
    }
    return result;
  }

  /// Đổi ca của tôi sang một ca còn trống: bỏ ca cũ và nhận ca mới trong một giao dịch (có hiệu lực
  /// ngay như đăng ký ca), quản lý được báo. Ca cũ phải chưa bắt đầu, chưa điểm danh, chưa có yêu cầu đổi.
  Future<void> swapToOpenShift(int assignmentId, int shiftId) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'swaps.self');
      final me = await _me(tx);
      final mine = await _swapAssignment(tx, assignmentId);
      if (mine == null || mine['employee_id'] != me['id']) {
        throw const AuthException('Phân ca không thuộc bạn.');
      }
      final block = await _swapBlocker(tx, mine);
      if (block != null) throw AuthException('Ca của bạn: $block');
      final target = (await tx.query(
        'shifts',
        where: 'id=?',
        whereArgs: [shiftId],
      )).firstOrNull;
      if (target == null || target['id'] == mine['shift_id']) {
        throw const AuthException('Chọn một ca còn trống khác.');
      }
      if (target['branch_id'] != me['branch_id']) {
        throw const AuthException('Ca này thuộc chi nhánh khác.');
      }
      if (target['status'] != 'scheduled' ||
          !utcTime(target['starts_at']).isAfter(DateTime.now().toUtc())) {
        throw const AuthException('Ca đã bắt đầu hoặc đã đóng.');
      }
      await _available(tx, me['id'] as int, target, ignoring: [assignmentId]);
      final count =
          (await tx.rawQuery(
                "SELECT COUNT(*) n FROM shift_assignments WHERE shift_id=? AND status<>'cancelled'",
                [shiftId],
              )).single['n']
              as int;
      if (count >= (target['required_staff'] as int)) {
        throw const AuthException('Ca đã đủ nhân viên.');
      }
      await tx.update(
        'shift_assignments',
        {'status': 'cancelled'},
        where: 'id=?',
        whereArgs: [assignmentId],
      );
      final old = await tx.query(
        'shift_assignments',
        where: 'shift_id=? AND employee_id=?',
        whereArgs: [shiftId, me['id']],
      );
      final data = {
        'shift_id': shiftId,
        'employee_id': me['id'],
        'assigned_by': session.userId,
        'status': 'assigned',
        'response_status': 'accepted',
        'responded_at': sqlTime(DateTime.now()),
        'response_note': 'Đổi sang ca còn trống',
      };
      final id = old.isEmpty
          ? await tx.insert('shift_assignments', data)
          : old.single['id'] as int;
      if (old.isNotEmpty) {
        await tx.update(
          'shift_assignments',
          data,
          where: 'id=?',
          whereArgs: [id],
        );
      }
      await _audit(tx, 'shift.swap_open', 'shift_assignments', id, {
        'from_assignment': assignmentId,
      });
      await _notify(
        tx,
        await _reviewers(tx, 'shifts.manage', excluding: [session.userId]),
        'Nhân viên đổi sang ca còn trống',
        '${me['full_name']} bỏ ca ${_shiftLabel(_swapShiftOf(mine))} để nhận ca ${_shiftLabel(target)}.',
        'shifts',
        shiftId,
      );
    });
  }
}
