import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Nâng schema tại chỗ: chỉ thêm dữ liệu cấu trúc, không xóa database cũ.
/// Toàn bộ migration rollback nếu một câu lệnh thất bại; ghi version sau cùng.
Future<void> migrateFeatures(Database db) async {
  await db.transaction((tx) async {
    final version =
        (await tx.rawQuery('PRAGMA user_version')).single.values.single as int;
    if (version >= 4) return;
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
    await tx.execute('PRAGMA user_version=4');
  });
}
