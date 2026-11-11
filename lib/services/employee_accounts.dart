part of 'workforce_repository.dart';

/// Bước 2 của luồng thêm người: Admin cấp tài khoản đăng nhập cho một **hồ sơ nhân viên đã có**.
/// Vì hồ sơ có từ trước nên tài khoản vừa tạo đã dùng được mọi chức năng của vai trò.
extension EmployeeAccounts on WorkforceRepository {
  /// Hồ sơ đang làm việc nhưng chưa có tài khoản (để chọn khi tạo tài khoản).
  Future<List<RowData>> employeesWithoutAccount() async {
    final db = await _open();
    await _require(db, 'users.manage');
    return db.rawQuery(
      'SELECT e.id,e.employee_code,e.full_name,e.phone,b.name branch_name FROM employees e '
      'JOIN branches b ON b.id=e.branch_id '
      "WHERE e.user_id IS NULL AND e.status='active' ORDER BY e.full_name",
    );
  }

  /// Tạo tài khoản Quản lý hoặc Nhân viên (không tạo được Admin) và liên kết ngay với hồ sơ
  /// [employeeId]. Trả về id tài khoản mới.
  Future<int> createAccountForEmployee({
    required int employeeId,
    required String username,
    required String password,
    required String role,
  }) async {
    final db = await _open();
    await _require(db, 'users.manage');
    if (!['manager', 'employee'].contains(role)) {
      throw const AuthException(
        'Chỉ tạo được tài khoản Quản lý hoặc Nhân viên.',
      );
    }
    final name = username.trim();
    if (name.isEmpty || name.length > 100) {
      throw const AuthException('Tên đăng nhập phải có từ 1 đến 100 ký tự.');
    }
    final hash = await AuthService.hashPassword(password);
    return db.transaction((tx) async {
      await _require(tx, 'users.manage');
      final profile = (await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [employeeId],
      )).firstOrNull;
      if (profile == null || profile['status'] != 'active') {
        throw const AuthException(
          'Chọn một nhân viên đang làm việc. Hãy thêm nhân viên ở mục Nhân sự trước.',
        );
      }
      if (profile['user_id'] != null) {
        throw const AuthException('Nhân viên này đã có tài khoản.');
      }
      final roles = await tx.query('roles', where: 'code=?', whereArgs: [role]);
      if (roles.isEmpty) throw const AuthException('Vai trò không hợp lệ.');
      if ((await tx.query(
        'users',
        where: 'LOWER(username)=LOWER(?)',
        whereArgs: [name],
      )).isNotEmpty) {
        throw const AuthException('Tên đăng nhập đã tồn tại.');
      }
      final userId = await tx.insert('users', {
        'username': name,
        'password_hash': hash,
      });
      await tx.insert('user_roles', {
        'user_id': userId,
        'role_id': roles.single['id'],
      });
      final position = (await tx.query(
        'positions',
        columns: ['id'],
        where: 'code=?',
        whereArgs: [role == 'manager' ? 'MANAGER' : 'WAITER'],
      )).firstOrNull;
      await tx.update(
        'employees',
        {'user_id': userId, 'position_id': ?position?['id']},
        where: 'id=?',
        whereArgs: [employeeId],
      );
      await _audit(tx, 'user.create', 'users', userId, {
        'employee_id': employeeId,
        'role': role,
      });
      return userId;
    });
  }
}
