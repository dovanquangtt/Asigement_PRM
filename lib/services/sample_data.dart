import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Dữ liệu mẫu được cài đúng một lần cho database mới và bản local đã tồn tại.
/// Không thay mật khẩu, vai trò hoặc hồ sơ của tài khoản đã tồn tại.
Future<void> installSampleData(Database db) async {
  await db.transaction((tx) async {
    final version =
        (await tx.rawQuery('PRAGMA user_version')).single.values.single as int;
    if (version >= 2) return;
    for (final role in [
      ('admin', 'Quản trị viên'),
      ('manager', 'Quản lý'),
      ('employee', 'Nhân viên'),
    ]) {
      await tx.rawInsert(
        'INSERT OR IGNORE INTO roles(code,name) VALUES (?,?)',
        [role.$1, role.$2],
      );
    }
    final existingBranch = await tx.query(
      'branches',
      where: 'code = ?',
      whereArgs: ['MOC_DEMO'],
    );
    final branchId = existingBranch.isEmpty
        ? await tx.insert('branches', {
            'code': 'MOC_DEMO',
            'name': 'ANH EM QUÁN',
            'address': 'TP. Hồ Chí Minh',
          })
        : existingBranch.single['id'] as int;
    final department = (await tx.query(
      'departments',
      where: 'code = ?',
      whereArgs: ['SERVICE'],
    )).firstOrNull;
    for (final account in [
      (
        'admin',
        'Nguyễn Xuân Bắc',
        'admin',
        'DEMO_ADMIN',
        r'$2a$12$ZqUZJ.zCISUQKfsPLESceupoKSZyeAuOAZF7l5bSzkmqzPGsW178G',
        'MANAGER',
      ),
      (
        'manager',
        'Nguyễn Văn Trường',
        'manager',
        'DEMO_MANAGER',
        r'$2a$12$EcfTvYmQlGC2wntz/pNoBezQlPGRDu6E8823yVJ0dNpcIc4jR6SJS',
        'MANAGER',
      ),
      (
        'employee',
        'Đỗ Văn Quang',
        'employee',
        'DEMO_EMPLOYEE',
        r'$2a$12$NEDYhkcpBRpA4mwoZ2c34.KOX7GtUsDzaVgqpPIpWnVvcrMLd4ela',
        'WAITER',
      ),
    ]) {
      final existing = await tx.query(
        'users',
        where: 'username = ?',
        whereArgs: [account.$1],
      );
      if (existing.isNotEmpty) continue;
      final id = await tx.insert('users', {
        'username': account.$1,
        'password_hash': account.$5,
        'email': '${account.$1}@moc.example',
      });
      final role = (await tx.query(
        'roles',
        where: 'code = ?',
        whereArgs: [account.$3],
      )).single;
      await tx.insert('user_roles', {'user_id': id, 'role_id': role['id']});
      final position = (await tx.query(
        'positions',
        where: 'code = ?',
        whereArgs: [account.$6],
      )).firstOrNull;
      final existingProfile = await tx.query(
        'employees',
        where: 'employee_code = ?',
        whereArgs: [account.$4],
      );
      if (existingProfile.isEmpty) {
        await tx.insert('employees', {
          'user_id': id,
          'employee_code': account.$4,
          'full_name': account.$2,
          'branch_id': branchId,
          'department_id': department?['id'],
          'position_id': position?['id'],
          'hire_date': '2026-10-01',
        });
      }
    }
    await tx.execute('PRAGMA user_version = 2');
  });
}
