import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_service.dart';
import 'local_database.dart';
import 'attendance_evidence.dart';

import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'payroll_source.dart';
import 'feature_sample_data.dart';

part 'workforce_operations.dart';
part 'attendance_review.dart';
part 'attendance_management.dart';
part 'attendance_sheet.dart';
part 'shift_response.dart';
part 'leave_management.dart';
part 'dashboard_summary.dart';
part 'shift_swap.dart';
part 'payroll_self.dart';
part 'payroll_manage.dart';
part 'employee_accounts.dart';
part 'shift_open.dart';

typedef RowData = Map<String, Object?>;

class WorkforceRepository {
  WorkforceRepository(this.session, {Future<Database> Function()? openDatabase})
    : _open = openDatabase ?? (() => LocalDatabase.instance.database);
  final UserSession session;
  final Future<Database> Function() _open;

  /// Ghi thông báo cùng transaction nghiệp vụ: thành công hoặc rollback cùng nhau.
  Future<void> _notify(
    DatabaseExecutor tx,
    Iterable<int> users,
    String title,
    String body,
    String entity,
    int entityId,
  ) async {
    final recipients = users.toSet()..remove(session.userId);
    if (recipients.isEmpty) return;
    final id = await tx.insert('notifications', {
      'title': title,
      'body': body,
      'notification_type': 'workflow',
      'created_by': session.userId,
      'related_entity': entity,
      'related_id': entityId,
    });
    for (final user in recipients) {
      await tx.insert('notification_recipients', {
        'notification_id': id,
        'user_id': user,
      });
    }
  }

  Future<List<int>> _employeeUsers(
    DatabaseExecutor tx,
    Iterable<int> employees,
  ) async {
    final result = <int>[];
    for (final id in employees.toSet()) {
      final rows = await tx.query(
        'employees',
        columns: ['user_id'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty && rows.single['user_id'] != null) {
        result.add(rows.single['user_id'] as int);
      }
    }
    return result;
  }

  Future<List<RowData>> notifications() async {
    final db = await _open();
    await _require(db, 'profile.self');
    return db.rawQuery(
      'SELECT n.*,r.read_at FROM notifications n JOIN notification_recipients r ON r.notification_id=n.id WHERE r.user_id=? ORDER BY n.id DESC',
      [session.userId],
    );
  }

  Future<List<int>> _reviewers(
    DatabaseExecutor tx,
    String permission, {
    Iterable<int> excluding = const [],
  }) async {
    final rows = await tx.rawQuery(
      'SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN role_permissions rp ON rp.role_id=ur.role_id JOIN permissions p ON p.id=rp.permission_id WHERE u.is_active=1 AND p.code=?',
      [permission],
    );
    return rows
        .map((r) => r['id'] as int)
        .where((id) => !excluding.contains(id))
        .toList();
  }

  Future<void> markNotificationRead(int id) async {
    final db = await _open();
    await _require(db, 'profile.self');
    await db.update(
      'notification_recipients',
      {'read_at': DateTime.now().toUtc().toIso8601String()},
      where: 'notification_id=? AND user_id=? AND read_at IS NULL',
      whereArgs: [id, session.userId],
    );
  }

  /// Chỉ Admin được chủ động nạp mẫu vào bản database đã tồn tại trên thiết bị.
  /// Seeder có marker riêng nên không xóa, ghi đè hoặc nhân đôi dữ liệu.
  Future<bool> installDemoData() async {
    final db = await _open();
    await _require(db, 'users.manage');
    try {
      return await installFeatureSamples(db);
    } on SampleDataException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<bool> _can(DatabaseExecutor db, String permission) async =>
      (await db.rawQuery(
        'SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id=u.id '
        'JOIN role_permissions rp ON rp.role_id=ur.role_id '
        'JOIN permissions p ON p.id=rp.permission_id '
        'WHERE u.id=? AND u.is_active=1 AND p.code=? LIMIT 1',
        [session.userId, permission],
      )).isNotEmpty;

  Future<void> _require(DatabaseExecutor db, String permission) async {
    if (!await _can(db, permission)) {
      throw const AuthException(
        'Tài khoản không có quyền thực hiện thao tác này.',
      );
    }
  }

  Future<List<RowData>> users() async {
    final db = await _open();
    await _require(db, 'users.manage');
    return db.rawQuery(
      "SELECT u.id,u.username,u.email,u.is_active,GROUP_CONCAT(r.name, ', ') AS roles,e.id AS employee_id,e.full_name AS employee_name "
      'FROM users u LEFT JOIN user_roles ur ON ur.user_id=u.id '
      'LEFT JOIN roles r ON r.id=ur.role_id LEFT JOIN employees e ON e.user_id=u.id GROUP BY u.id ORDER BY u.id',
    );
  }

  Future<List<RowData>> employees() async {
    final db = await _open();
    await _require(db, 'employees.manage');
    return db.rawQuery(
      'SELECT e.*,b.name AS branch_name,d.name AS department_name '
      'FROM employees e JOIN branches b ON b.id=e.branch_id '
      "LEFT JOIN departments d ON d.id=e.department_id WHERE e.status<>'terminated' ORDER BY e.full_name",
    );
  }

  /// Sửa mã, họ tên, điện thoại của hồ sơ nhân viên.
  Future<void> updateEmployee(
    int employeeId, {
    required String code,
    required String name,
    String phone = '',
  }) async {
    if (code.trim().isEmpty || name.trim().isEmpty) {
      throw const AuthException('Nhập mã và tên nhân viên.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'employees.manage');
      final rows = await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [employeeId],
      );
      if (rows.isEmpty) throw const AuthException('Không tìm thấy nhân viên.');
      if ((await tx.query(
        'employees',
        where: 'employee_code=? AND id<>?',
        whereArgs: [code.trim(), employeeId],
      )).isNotEmpty) {
        throw const AuthException('Mã nhân viên đã tồn tại.');
      }
      await tx.update(
        'employees',
        {
          'employee_code': code.trim(),
          'full_name': name.trim(),
          'phone': phone.trim(),
        },
        where: 'id=?',
        whereArgs: [employeeId],
      );
    });
  }

  /// Xóa nhân viên: đánh dấu đã nghỉ việc (giữ lịch sử chấm công/lương), khóa tài khoản
  /// liên kết và gỡ khỏi các ca chưa bắt đầu.
  Future<void> deleteEmployee(int employeeId) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'employees.manage');
      final employee = (await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [employeeId],
      )).firstOrNull;
      if (employee == null)
        throw const AuthException('Không tìm thấy nhân viên.');
      if (employee['status'] == 'terminated') return;
      final userId = employee['user_id'] as int?;
      if (userId == session.userId) {
        throw const AuthException('Không thể xóa hồ sơ của chính bạn.');
      }
      if (userId != null &&
          (await tx.rawQuery(
            "SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=? AND r.code='admin'",
            [userId],
          )).isNotEmpty) {
        throw const AuthException(
          'Không thể xóa hồ sơ gắn với tài khoản Admin.',
        );
      }
      // Gỡ khỏi các ca chưa bắt đầu và chưa có chấm công.
      await tx.rawUpdate(
        "UPDATE shift_assignments SET status='cancelled' WHERE employee_id=? AND status='assigned' "
        "AND shift_id IN (SELECT id FROM shifts WHERE status='scheduled' AND starts_at>?) "
        'AND id NOT IN (SELECT assignment_id FROM attendance_events)',
        [employeeId, sqlTime(DateTime.now())],
      );
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hired = '${employee['hire_date']}';
      await tx.update(
        'employees',
        {
          'status': 'terminated',
          'termination_date': today.compareTo(hired) < 0 ? hired : today,
        },
        where: 'id=?',
        whereArgs: [employeeId],
      );
      if (userId != null) {
        await tx.update(
          'users',
          {'is_active': 0},
          where: 'id=?',
          whereArgs: [userId],
        );
      }
      await tx.insert('audit_logs', {
        'actor_user_id': session.userId,
        'action': 'employee.delete',
        'entity_type': 'employees',
        'entity_id': employeeId,
        'after_json': '{}',
      });
    });
  }

  Future<List<RowData>> shifts() async {
    final db = await _open();
    final managing = await _can(db, 'shifts.manage');
    if (!managing) await _require(db, 'schedule.self');
    return db.rawQuery(
      'SELECT v.*,b.name AS branch_name FROM v_shift_roster v '
      'JOIN branches b ON b.id=v.branch_id JOIN employees e ON e.id=v.employee_id '
      'JOIN shifts sh ON sh.id=v.shift_id '
      "WHERE v.status<>'cancelled' AND sh.status<>'cancelled' "
      // Nhân viên: ngày bé đến lớn để dễ tìm ca sắp tới; quản lý giữ ca mới nhất trước.
      '${managing ? '' : 'AND e.user_id=? '}ORDER BY v.starts_at ${managing ? 'DESC' : 'ASC'}',
      managing ? [] : [session.userId],
    );
  }

  Future<List<RowData>> payslips() async {
    final db = await _open();
    final managing = await _can(db, 'payroll.manage');
    if (!managing) await _require(db, 'payslips.self');
    return db.rawQuery(
      'SELECT p.*,e.full_name,pp.code AS period_code,pp.starts_on,pp.ends_on FROM v_payslip_totals p '
      'JOIN employees e ON e.id=p.employee_id JOIN payroll_periods pp ON pp.id=p.period_id '
      '${managing ? '' : "WHERE e.user_id=? AND p.status IN ('approved','paid') "}ORDER BY pp.starts_on DESC,e.full_name',
      managing ? [] : [session.userId],
    );
  }

  Future<RowData> profile() async {
    final db = await _open();
    await _require(db, 'profile.self');
    final rows = await db.rawQuery(
      'SELECT u.username,u.email,e.employee_code,e.full_name,e.phone,e.hire_date,e.status,b.name AS branch_name '
      'FROM users u LEFT JOIN employees e ON e.user_id=u.id '
      'LEFT JOIN branches b ON b.id=e.branch_id WHERE u.id=? AND u.is_active=1',
      [session.userId],
    );
    return rows.single;
  }

  Future<RowData> overview() async {
    final db = await _open();
    await _require(db, 'profile.self');
    final managing = await _can(db, 'reports.view');
    final employeeCount = managing
        ? (await db.rawQuery(
            "SELECT COUNT(*) AS n FROM employees WHERE status='active'",
          )).single['n']
        : null;
    return {
      'employees': employeeCount,
      'shifts': (await shifts()).length,
      'payslips': (await payslips()).length,
    };
  }

  /// Tạo tài khoản Quản lý hoặc Nhân viên (không tạo được Admin) **kèm hồ sơ nhân viên đã liên kết**
  /// để đăng nhập là dùng được ngay mọi chức năng của vai trò đó: hồ sơ ở chi nhánh [branchId]
  /// (mặc định chi nhánh đầu tiên), bộ phận Phục vụ, chức danh theo vai trò, số ngày phép năm
  /// mặc định (12 ngày như hồ sơ mẫu) và hợp đồng nếu nhập [monthlySalary]. Trả về id hồ sơ nhân viên.
  Future<int> createUser({
    required String username,
    required String password,
    required String role,
    String fullName = '',
    int? branchId,
    String phone = '',
    int? monthlySalary,
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
    if (fullName.trim().isEmpty) {
      throw const AuthException('Nhập họ tên nhân viên.');
    }
    if (monthlySalary != null && monthlySalary < 0) {
      throw const AuthException('Lương tháng không hợp lệ.');
    }
    // Dùng cùng quy tắc bcrypt và validation như thiết lập tài khoản ban đầu.
    final hash = await AuthService.hashPassword(password);
    return db.transaction((tx) async {
      await _require(tx, 'users.manage');
      final roles = await tx.query('roles', where: 'code=?', whereArgs: [role]);
      if (roles.isEmpty) throw const AuthException('Vai trò không hợp lệ.');
      if ((await tx.query(
        'users',
        where: 'username=?',
        whereArgs: [name],
      )).isNotEmpty) {
        throw const AuthException('Tên đăng nhập đã tồn tại.');
      }
      final branches = branchId == null
          ? await tx.query('branches', orderBy: 'id', limit: 1)
          : await tx.query('branches', where: 'id=?', whereArgs: [branchId]);
      if (branches.isEmpty) {
        throw AuthException(
          branchId == null
              ? 'Cần tạo chi nhánh trước khi tạo tài khoản.'
              : 'Chi nhánh không hợp lệ.',
        );
      }
      final userId = await tx.insert('users', {
        'username': name,
        'password_hash': hash,
      });
      await tx.insert('user_roles', {
        'user_id': userId,
        'role_id': roles.single['id'],
      });
      // Mã nhân viên tự sinh, bảo đảm không trùng.
      var code = 'NV${userId.toString().padLeft(3, '0')}';
      var n = 1;
      while ((await tx.query(
        'employees',
        columns: ['id'],
        where: 'employee_code=?',
        whereArgs: [code],
      )).isNotEmpty) {
        code = 'NV${userId.toString().padLeft(3, '0')}_${n++}';
      }
      Future<int?> idOf(String table, String code) async =>
          (await tx.query(
                table,
                columns: ['id'],
                where: 'code=?',
                whereArgs: [code],
              )).firstOrNull?['id']
              as int?;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final employeeId = await tx.insert('employees', {
        'user_id': userId,
        'employee_code': code,
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'branch_id': branches.single['id'],
        'department_id': await idOf('departments', 'SERVICE'),
        'position_id': await idOf(
          'positions',
          role == 'manager' ? 'MANAGER' : 'WAITER',
        ),
        'hire_date': today,
        'status': 'active',
      });
      // Số ngày phép năm mặc định như hồ sơ mẫu (12 ngày = 5760 phút).
      final annual = await idOf('leave_types', 'ANNUAL');
      if (annual != null) {
        await tx.insert('leave_balances', {
          'employee_id': employeeId,
          'leave_type_id': annual,
          'year': now.year,
          'granted_minutes': 5760,
          'used_minutes': 0,
        });
      }
      if (monthlySalary != null && monthlySalary > 0) {
        await tx.insert('contracts', {
          'employee_id': employeeId,
          'contract_number': 'HD-$code',
          'contract_type': 'indefinite',
          'start_date': today,
          'salary_basis': 'monthly',
          'base_salary_vnd': monthlySalary,
          'standard_minutes_per_month': 12480,
          'status': 'active',
        });
      }
      await tx.insert('audit_logs', {
        'actor_user_id': session.userId,
        'action': 'user.create',
        'entity_type': 'users',
        'entity_id': userId,
        'after_json': '{}',
      });
      return employeeId;
    });
  }

  /// Bước 1 của luồng thêm người: tạo **hồ sơ nhân viên** đầy đủ (chưa có tài khoản): chi nhánh
  /// [branchId] (mặc định chi nhánh đầu tiên), bộ phận Phục vụ, chức danh Nhân viên phục vụ, số ngày
  /// phép năm mặc định và hợp đồng nếu nhập [monthlySalary]. Để trống [code] thì mã được tự sinh.
  /// Bước 2 là `createAccountForEmployee`. Trả về id hồ sơ.
  Future<int> createEmployee({
    String code = '',
    required String name,
    String phone = '',
    int? branchId,
    int? monthlySalary,
  }) async {
    if (name.trim().isEmpty) {
      throw const AuthException('Nhập họ tên nhân viên.');
    }
    if (monthlySalary != null && monthlySalary < 0) {
      throw const AuthException('Lương tháng không hợp lệ.');
    }
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'employees.manage');
      final branches = branchId == null
          ? await tx.query('branches', orderBy: 'id', limit: 1)
          : await tx.query('branches', where: 'id=?', whereArgs: [branchId]);
      if (branches.isEmpty) {
        throw AuthException(
          branchId == null
              ? 'Cần tạo chi nhánh trước khi thêm nhân viên.'
              : 'Chi nhánh không hợp lệ.',
        );
      }
      var employeeCode = code.trim();
      if (employeeCode.isEmpty) {
        final next =
            ((await tx.rawQuery(
                  'SELECT COALESCE(MAX(id),0)+1 n FROM employees',
                )).single['n']
                as int);
        employeeCode = 'NV${next.toString().padLeft(3, '0')}';
        var n = 1;
        while ((await tx.query(
          'employees',
          columns: ['id'],
          where: 'employee_code=?',
          whereArgs: [employeeCode],
        )).isNotEmpty) {
          employeeCode = 'NV${next.toString().padLeft(3, '0')}_${n++}';
        }
      } else if ((await tx.query(
        'employees',
        where: 'employee_code=?',
        whereArgs: [employeeCode],
      )).isNotEmpty) {
        throw const AuthException('Mã nhân viên đã tồn tại.');
      }
      Future<int?> idOf(String table, String code) async =>
          (await tx.query(
                table,
                columns: ['id'],
                where: 'code=?',
                whereArgs: [code],
              )).firstOrNull?['id']
              as int?;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final employeeId = await tx.insert('employees', {
        'employee_code': employeeCode,
        'full_name': name.trim(),
        'phone': phone.trim(),
        'branch_id': branches.single['id'],
        'department_id': await idOf('departments', 'SERVICE'),
        'position_id': await idOf('positions', 'WAITER'),
        'hire_date': today,
        'status': 'active',
      });
      final annual = await idOf('leave_types', 'ANNUAL');
      if (annual != null) {
        await tx.insert('leave_balances', {
          'employee_id': employeeId,
          'leave_type_id': annual,
          'year': now.year,
          'granted_minutes': 5760,
          'used_minutes': 0,
        });
      }
      if (monthlySalary != null && monthlySalary > 0) {
        await tx.insert('contracts', {
          'employee_id': employeeId,
          'contract_number': 'HD-$employeeCode',
          'contract_type': 'indefinite',
          'start_date': today,
          'salary_basis': 'monthly',
          'base_salary_vnd': monthlySalary,
          'standard_minutes_per_month': 12480,
          'status': 'active',
        });
      }
      await _audit(tx, 'employee.create', 'employees', employeeId);
      return employeeId;
    });
  }
}
