import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Nâng schema tại chỗ: chỉ thêm dữ liệu cấu trúc, không xóa database cũ.
/// Toàn bộ migration rollback nếu một câu lệnh thất bại; ghi version sau cùng.
Future<void> migrateFeatures(Database db) async {
  await db.transaction((tx) async {
    final version =
        (await tx.rawQuery('PRAGMA user_version')).single.values.single as int;
    await tx.rawUpdate(
      'UPDATE branches SET name=?,address=CASE WHEN address=? THEN ? ELSE address END WHERE code=? AND name IN (?,?,?)',
      [
        'ANH EM QUÁN',
        'TP. Hồ Chí Minh (dữ liệu mẫu)',
        'TP. Hồ Chí Minh',
        'MOC_DEMO',
        'ANH EM QUÁN - Chi nhánh mẫu',
        'Mộc - Chi nhánh mẫu',
        'ANH EM QUÁN',
      ],
    );
    for (final shift in [
      ('DEMO_MORNING', 'Ca sáng'),
      ('DEMO_EVENING', 'Ca chiều'),
      ('DEMO_SHORT', 'Ca ngắn'),
      ('DEMO_NIGHT', 'Ca qua đêm'),
    ]) {
      await tx.rawUpdate(
        'UPDATE shift_templates SET name=? WHERE code=? AND name=?',
        [shift.$2, shift.$1, '${shift.$2} DEMO'],
      );
    }
    const identityUpdate = 'configure_team_identity_20261022';
    if ((await tx.query(
      'audit_logs',
      where: 'action=?',
      whereArgs: [identityUpdate],
    )).isEmpty) {
      for (final person in [
        ('admin', 'DEMO_ADMIN', 'Nguyễn Xuân Bắc'),
        ('manager', 'DEMO_MANAGER', 'Nguyễn Văn Trường'),
        ('employee', 'DEMO_EMPLOYEE', 'Đỗ Văn Quang'),
      ]) {
        final profiles = await tx.rawQuery(
          'SELECT e.id,e.user_id,e.full_name FROM employees e JOIN users u ON u.id=e.user_id WHERE u.username=? AND e.employee_code=?',
          [person.$1, person.$2],
        );
        if (profiles.isEmpty) continue;
        final profile = profiles.single;
        final roles = await tx.query(
          'roles',
          where: 'code=?',
          whereArgs: [person.$1],
        );
        if (roles.isEmpty) throw StateError('Missing role ${person.$1}');
        final beforeRoles = await tx.query(
          'user_roles',
          where: 'user_id=?',
          whereArgs: [profile['user_id']],
        );
        await tx.update(
          'employees',
          {'full_name': person.$3},
          where: 'id=?',
          whereArgs: [profile['id']],
        );
        await tx.delete(
          'user_roles',
          where: 'user_id=?',
          whereArgs: [profile['user_id']],
        );
        await tx.insert('user_roles', {
          'user_id': profile['user_id'],
          'role_id': roles.single['id'],
        });
        await tx.insert('audit_logs', {
          'action': identityUpdate,
          'entity_type': 'employees',
          'entity_id': profile['id'],
          'before_json': jsonEncode({'profile': profile, 'roles': beforeRoles}),
          'after_json': jsonEncode({'full_name': person.$3, 'role': person.$1}),
        });
      }
    }
    await tx.execute(
      "UPDATE branches SET name=replace(replace(replace(name,'Mộc','ANH EM QUÁN'),'mộc','ANH EM QUÁN'),'MỘC','ANH EM QUÁN') WHERE name LIKE '%Mộc%' OR name LIKE '%mộc%' OR name LIKE '%MỘC%'",
    );
    await tx.execute("""
      UPDATE shifts SET note='Phân công cho: ' || COALESCE(
        (SELECT group_concat(e.full_name, ', ') FROM shift_assignments a
         JOIN employees e ON e.id=a.employee_id
         WHERE a.shift_id=shifts.id AND a.status<>'cancelled'),
        'Chưa phân công nhân viên')
      WHERE note LIKE '[DEMO %] Dữ liệu mẫu để thử chức năng;%'
    """);
    if (version >= 8) return;
    if (version < 3) {
      // v3: duyệt thiết bị, liên kết Google và lưu kết quả kiểm tra lương.
      await tx.execute(
        'ALTER TABLE employee_devices ADD COLUMN approved_by INTEGER REFERENCES users(id)',
      );
      await tx.execute('ALTER TABLE users ADD COLUMN google_subject TEXT');
      await tx.execute(
        'CREATE UNIQUE INDEX uq_google_subject ON users(google_subject) WHERE google_subject IS NOT NULL',
      );
      await tx.execute(
        'CREATE TABLE payroll_policies (period_id INTEGER PRIMARY KEY REFERENCES payroll_periods(id), overtime_multiplier REAL NOT NULL CHECK(overtime_multiplier>=1), created_by INTEGER NOT NULL REFERENCES users(id))',
      );
      await tx.execute(
        'CREATE TABLE employee_payroll_checks (period_id INTEGER NOT NULL REFERENCES payroll_periods(id), employee_id INTEGER NOT NULL REFERENCES employees(id), step_number INTEGER NOT NULL CHECK(step_number BETWEEN 1 AND 6), name TEXT NOT NULL, detail TEXT NOT NULL, checked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(period_id,employee_id,step_number))',
      );
    }
    if (version < 4) {
      // v4: giữ nguyên danh tính hai bên khi phân ca được chuyển cho người khác.
      await tx.execute(
        'ALTER TABLE shift_swap_requests ADD COLUMN from_employee_id INTEGER REFERENCES employees(id)',
      );
      await tx.execute(
        'ALTER TABLE shift_swap_requests ADD COLUMN to_employee_id INTEGER REFERENCES employees(id)',
      );
      await tx.execute(
        'UPDATE shift_swap_requests SET from_employee_id=(SELECT employee_id FROM shift_assignments WHERE id=from_assignment_id),to_employee_id=(SELECT employee_id FROM shift_assignments WHERE id=to_assignment_id)',
      );
      await tx.execute(
        "ALTER TABLE employee_payroll_checks ADD COLUMN source_hash TEXT NOT NULL DEFAULT ''",
      );
    }
    if (version < 5) {
      // v5: employee submissions and immutable evidence for Admin review.
      for (final column in [
        'submitted_by INTEGER REFERENCES users(id)',
        'actual_device_identifier TEXT',
        'selected_device_identifier TEXT',
        'device_platform TEXT',
        'evidence_collected_at TEXT',
        'evidence_mocked INTEGER NOT NULL DEFAULT 0',
        'checks_snapshot TEXT',
        'reviewed_by INTEGER REFERENCES users(id)',
        'reviewed_at TEXT',
        'review_note TEXT',
      ]) {
        await tx.execute('ALTER TABLE attendance_events ADD COLUMN $column');
      }
      await tx.execute(
        "CREATE UNIQUE INDEX ux_attendance_pending ON attendance_events(assignment_id,event_type) WHERE result='pending_review'",
      );
    }
    if (version < 6) {
      // v6: attendance exceptions, adjustments, overtime approval and closing.
      for (final column in [
        "arrival_status TEXT CHECK(arrival_status IN ('ON_TIME','LATE'))",
        "attendance_state TEXT NOT NULL DEFAULT 'IN_PROGRESS'",
        'overtime_requested_minutes INTEGER NOT NULL DEFAULT 0 CHECK(overtime_requested_minutes>=0)',
        "overtime_status TEXT NOT NULL DEFAULT 'NOT_REQUIRED'",
        'overtime_reviewed_by INTEGER REFERENCES users(id)',
        'overtime_reviewed_at TEXT',
        'overtime_review_note TEXT',
        'locked_by INTEGER REFERENCES users(id)',
        'locked_at TEXT',
      ]) {
        await tx.execute('ALTER TABLE attendance_records ADD COLUMN $column');
      }
      for (final column in ['before_json TEXT', 'evidence_path TEXT']) {
        await tx.execute(
          'ALTER TABLE attendance_adjustment_requests ADD COLUMN $column',
        );
      }
      await tx.execute(
        'ALTER TABLE branches ADD COLUMN require_overtime_approval INTEGER NOT NULL DEFAULT 0 CHECK(require_overtime_approval IN (0,1))',
      );
      await tx.execute(
        "CREATE UNIQUE INDEX ux_pending_attendance_adjustment ON attendance_adjustment_requests(attendance_id) WHERE status='pending'",
      );
      await tx.execute(
        "UPDATE attendance_records SET arrival_status=CASE WHEN check_in_at IS NULL THEN NULL WHEN late_minutes>0 THEN 'LATE' ELSE 'ON_TIME' END,attendance_state=CASE WHEN check_in_at IS NULL THEN 'MISSING_CHECK_IN' WHEN check_out_at IS NULL THEN 'IN_PROGRESS' ELSE 'COMPLETED' END",
      );
    }
    if (version < 7) {
      // v7: employees accept or reject assigned shifts. Existing assignments count as accepted.
      for (final column in [
        "response_status TEXT NOT NULL DEFAULT 'accepted' CHECK(response_status IN ('pending','accepted','rejected'))",
        'responded_at TEXT',
        'response_note TEXT',
      ]) {
        await tx.execute('ALTER TABLE shift_assignments ADD COLUMN $column');
      }
    }
    if (version < 8) {
      // v8: khiếu nại phiếu lương của nhân viên và tỷ lệ bảo hiểm (điểm cơ bản, 800 = 8%).
      await tx.execute(
        'ALTER TABLE payroll_policies ADD COLUMN insurance_rate_bp INTEGER NOT NULL DEFAULT 800 CHECK(insurance_rate_bp BETWEEN 0 AND 10000)',
      );
      await tx.execute(
        "CREATE TABLE payroll_disputes (id INTEGER PRIMARY KEY AUTOINCREMENT, payslip_id INTEGER NOT NULL REFERENCES payslips(id), employee_id INTEGER NOT NULL REFERENCES employees(id), message TEXT NOT NULL CHECK(length(trim(message))>0), status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','resolved','rejected')), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, resolved_by INTEGER REFERENCES users(id), resolved_at TEXT, resolution_note TEXT)",
      );
      await tx.execute(
        "CREATE TABLE payroll_dispute_items (dispute_id INTEGER NOT NULL REFERENCES payroll_disputes(id), item_key TEXT NOT NULL CHECK(item_key IN ('base_salary','overtime','allowance','bonus','insurance','deduction')), PRIMARY KEY(dispute_id,item_key))",
      );
      await tx.execute(
        "CREATE UNIQUE INDEX ux_payroll_dispute_pending ON payroll_disputes(payslip_id) WHERE status='pending'",
      );
      // Bản demo cũ: thêm một báo sai đã xử lý cho nhân viên mẫu (nếu có kỳ DEMO_PAID).
      await tx.execute(
        "INSERT INTO payroll_disputes (payslip_id,employee_id,message,status,created_at,resolved_by,resolved_at,resolution_note) "
        "SELECT p.id,p.employee_id,'[DEMO] Phụ cấp ăn tháng này chưa đủ số ngày công.','resolved',pp.ends_on||' 13:00:00',"
        "(SELECT id FROM users WHERE username='manager'),pp.ends_on||' 14:00:00','[DEMO] Đã kiểm tra lại, số liệu đúng.' "
        "FROM payslips p JOIN payroll_periods pp ON pp.id=p.period_id "
        "WHERE pp.code='DEMO_PAID' AND p.employee_id=(SELECT e.id FROM employees e JOIN users u ON u.id=e.user_id WHERE u.username='employee') LIMIT 1",
      );
      await tx.execute(
        "INSERT INTO payroll_dispute_items (dispute_id,item_key) SELECT id,'allowance' FROM payroll_disputes WHERE message LIKE '[DEMO]%'",
      );
    }
    await tx.execute('PRAGMA user_version=8');
  });
}
