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
      "SELECT u.id,u.username,u.email,u.is_active,GROUP_CONCAT(r.name, ', ') AS roles "
      'FROM users u LEFT JOIN user_roles ur ON ur.user_id=u.id '
      'LEFT JOIN roles r ON r.id=ur.role_id GROUP BY u.id ORDER BY u.id',
    );
  }

  Future<List<RowData>> employees() async {
    final db = await _open();
    await _require(db, 'employees.manage');
    return db.rawQuery(
      'SELECT e.*,b.name AS branch_name,d.name AS department_name '
      'FROM employees e JOIN branches b ON b.id=e.branch_id '
      'LEFT JOIN departments d ON d.id=e.department_id ORDER BY e.full_name',
    );
  }

  Future<List<RowData>> shifts() async {
    final db = await _open();
    final managing = await _can(db, 'shifts.manage');
    if (!managing) await _require(db, 'schedule.self');
    return db.rawQuery(
      'SELECT v.*,b.name AS branch_name FROM v_shift_roster v '
      'JOIN branches b ON b.id=v.branch_id JOIN employees e ON e.id=v.employee_id '
      '${managing ? '' : 'WHERE e.user_id=? '}ORDER BY v.starts_at DESC',
      managing ? [] : [session.userId],
    );
  }

  Future<List<RowData>> payslips() async {
    final db = await _open();
    final managing = await _can(db, 'payroll.manage');
    if (!managing) await _require(db, 'payslips.self');
    return db.rawQuery(
      'SELECT p.*,e.full_name,pp.code AS period_code FROM v_payslip_totals p '
      'JOIN employees e ON e.id=p.employee_id JOIN payroll_periods pp ON pp.id=p.period_id '
      '${managing ? '' : 'WHERE e.user_id=? '}ORDER BY pp.starts_on DESC,e.full_name',
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

  Future<void> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    final db = await _open();
    await _require(db, 'users.manage');
    // Dùng cùng quy tắc bcrypt và validation như thiết lập tài khoản ban đầu.
    final hash = await AuthService.hashPassword(password);
    final name = username.trim();
    if (name.isEmpty || name.length > 100) {
      throw const AuthException('Tên đăng nhập phải có từ 1 đến 100 ký tự.');
    }
    await db.transaction((tx) async {
      await _require(tx, 'users.manage');
      final roles = await tx.query('roles', where: 'code=?', whereArgs: [role]);
      if (!['admin', 'manager', 'employee'].contains(role) || roles.isEmpty) {
        throw const AuthException('Vai trò không hợp lệ.');
      }
      if ((await tx.query(
        'users',
        where: 'username=?',
        whereArgs: [name],
      )).isNotEmpty) {
        throw const AuthException('Tên đăng nhập đã tồn tại.');
      }
      final id = await tx.insert('users', {
        'username': name,
        'password_hash': hash,
      });
      await tx.insert('user_roles', {
        'user_id': id,
        'role_id': roles.single['id'],
      });
    });
  }

  Future<void> createEmployee({
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
      final branches = await tx.query('branches', orderBy: 'id', limit: 1);
      if (branches.isEmpty) {
        throw const AuthException(
          'Cần tạo chi nhánh trước khi thêm nhân viên.',
        );
      }
      if ((await tx.query(
        'employees',
        where: 'employee_code=?',
        whereArgs: [code.trim()],
      )).isNotEmpty) {
        throw const AuthException('Mã nhân viên đã tồn tại.');
      }
      final now = DateTime.now().toUtc().add(const Duration(hours: 7));
      await tx.insert('employees', {
        'employee_code': code.trim(),
        'full_name': name.trim(),
        'phone': phone.trim(),
        'branch_id': branches.single['id'],
        'hire_date':
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      });
    });
  }
}
