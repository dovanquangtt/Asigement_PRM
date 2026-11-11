part of 'workforce_repository.dart';

/// M02 Bảng lương – phần của Quản lý/Admin: sửa/xóa kỳ lương, sửa/xóa khoản cộng trừ và xử lý báo sai.
/// Nhân viên chỉ xem lương và gửi báo sai (payroll_self.dart).
extension PayrollManage on WorkforceRepository {
  /// Sửa kỳ lương chưa chốt. Đổi ngày hoặc hệ số làm các phiếu đã tính trở nên lỗi thời nên phải tính lại.
  Future<void> updatePeriod(
    int id, {
    required String code,
    required DateTime start,
    required DateTime end,
    required double multiplier,
    int insuranceRateBp = 800,
  }) async {
    if (code.trim().isEmpty ||
        end.isBefore(start) ||
        !multiplier.isFinite ||
        multiplier < 1 ||
        insuranceRateBp < 0 ||
        insuranceRateBp > 10000) {
      throw const AuthException('Kỳ lương hoặc hệ số tăng ca không hợp lệ.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final p = (await tx.query(
        'payroll_periods',
        where: 'id=?',
        whereArgs: [id],
      )).firstOrNull;
      if (p == null) throw const AuthException('Không tìm thấy kỳ lương.');
      if (['approved', 'paid'].contains(p['status'])) {
        throw const AuthException('Kỳ lương đã chốt, không thể sửa.');
      }
      final starts = sqlTime(start).substring(0, 10);
      final ends = sqlTime(end).substring(0, 10);
      await tx.update(
        'payroll_periods',
        {
          'code': code.trim(),
          'starts_on': starts,
          'ends_on': ends,
          'status': 'draft',
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await tx.update(
        'payroll_policies',
        {
          'overtime_multiplier': multiplier,
          'insurance_rate_bp': insuranceRateBp,
        },
        where: 'period_id=?',
        whereArgs: [id],
      );
      // Số liệu đã tính không còn khớp: xóa dấu vết 6 bước để buộc tính lại trước khi duyệt.
      await tx.delete(
        'payroll_calculation_steps',
        where: 'period_id=?',
        whereArgs: [id],
      );
      await tx.delete(
        'employee_payroll_checks',
        where: 'period_id=?',
        whereArgs: [id],
      );
      await _audit(tx, 'payroll.period_update', 'payroll_periods', id, {
        'code': code.trim(),
        'starts_on': starts,
        'ends_on': ends,
      });
    });
  }

  /// Xóa kỳ lương chưa có phiếu nào.
  Future<void> deletePeriod(int id) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final p = (await tx.query(
        'payroll_periods',
        where: 'id=?',
        whereArgs: [id],
      )).firstOrNull;
      if (p == null) throw const AuthException('Không tìm thấy kỳ lương.');
      if ((await tx.query(
        'payslips',
        columns: ['id'],
        where: 'period_id=?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty) {
        throw const AuthException('Kỳ lương đã có phiếu, không thể xóa.');
      }
      await tx.delete(
        'payroll_calculation_steps',
        where: 'period_id=?',
        whereArgs: [id],
      );
      await tx.delete(
        'payroll_policies',
        where: 'period_id=?',
        whereArgs: [id],
      );
      await tx.delete('payroll_periods', where: 'id=?', whereArgs: [id]);
      await _audit(tx, 'payroll.period_delete', 'payroll_periods', id, {
        'code': p['code'],
      });
    });
  }

  /// Xóa một khoản cộng/trừ khỏi phiếu nháp; buộc tính lại 6 bước như khi thêm khoản.
  Future<void> removePayItem(int payslipId, String code) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final pay = (await tx.query(
        'payslips',
        where: 'id=?',
        whereArgs: [payslipId],
      )).firstOrNull;
      if (pay == null) throw const AuthException('Không tìm thấy phiếu lương.');
      if (pay['status'] != 'draft') {
        throw const AuthException('Phiếu đã chốt không thể thay đổi.');
      }
      final removed = await tx.delete(
        'payslip_items',
        where: 'payslip_id=? AND code=?',
        whereArgs: [payslipId, code],
      );
      if (removed == 0) throw const AuthException('Không tìm thấy khoản này.');
      await tx.delete(
        'employee_payroll_checks',
        where: 'period_id=? AND employee_id=?',
        whereArgs: [pay['period_id'], pay['employee_id']],
      );
      await tx.delete(
        'payroll_calculation_steps',
        where: 'period_id=?',
        whereArgs: [pay['period_id']],
      );
      await _audit(tx, 'payroll.item_remove', 'payslips', payslipId, {
        'code': code,
      });
    });
  }

  /// Báo sai của nhân viên (mới nhất trước), lọc theo trạng thái nếu có.
  Future<List<RowData>> payrollDisputes({String? status}) async {
    final db = await _open();
    await _require(db, 'payroll.manage');
    return db.rawQuery(
      'SELECT d.*,e.full_name,e.employee_code,pp.code period_code,p.status payslip_status,'
      '(SELECT group_concat(item_key) FROM payroll_dispute_items WHERE dispute_id=d.id) item_keys '
      'FROM payroll_disputes d JOIN employees e ON e.id=d.employee_id '
      'JOIN payslips p ON p.id=d.payslip_id JOIN payroll_periods pp ON pp.id=p.period_id '
      "${status == null ? '' : 'WHERE d.status=? '}ORDER BY d.id DESC",
      [?status],
    );
  }

  /// Xử lý báo sai: `resolved` (đã kiểm tra/điều chỉnh) hoặc `rejected` (số liệu đúng). Bắt buộc có ghi chú.
  Future<void> resolvePayrollDispute(
    int id, {
    required bool accept,
    required String note,
  }) async {
    if (note.trim().isEmpty) {
      throw const AuthException('Nhập nội dung phản hồi cho nhân viên.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final d = (await tx.rawQuery(
        'SELECT d.*,e.user_id,pp.code period_code FROM payroll_disputes d JOIN employees e ON e.id=d.employee_id '
        'JOIN payslips p ON p.id=d.payslip_id JOIN payroll_periods pp ON pp.id=p.period_id WHERE d.id=?',
        [id],
      )).firstOrNull;
      if (d == null) throw const AuthException('Không tìm thấy báo sai.');
      if (d['status'] != 'pending') {
        throw const AuthException('Báo sai này đã được xử lý.');
      }
      await tx.update(
        'payroll_disputes',
        {
          'status': accept ? 'resolved' : 'rejected',
          'resolved_by': session.userId,
          'resolved_at': sqlTime(DateTime.now()),
          'resolution_note': note.trim(),
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await _audit(tx, 'payroll.dispute_resolve', 'payroll_disputes', id, {
        'accepted': accept,
      });
      final user = d['user_id'];
      if (user is int) {
        await _notify(
          tx,
          [user],
          accept ? 'Báo sai lương đã được xử lý' : 'Báo sai lương bị từ chối',
          'Kỳ ${d['period_code']}: ${note.trim()}',
          'payroll_disputes',
          id,
        );
      }
    });
  }
}
