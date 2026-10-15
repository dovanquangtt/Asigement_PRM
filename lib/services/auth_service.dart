import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}

class UserSession {
  const UserSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.permissions,
    required this.profile,
  });
  final int userId;
  final String username;
  final String role;
  final Set<String> permissions;
  final Map<String, Object?> profile;
  String get displayName => profile['full_name'] as String? ?? username;
}

String _hashPassword(String password) =>
    BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));

bool _verifyPassword((String, String) input) {
  try {
    return BCrypt.checkpw(input.$1, input.$2);
  } catch (_) {
    return false;
  }
}

/// Mọi lần đăng nhập đều đọc users, user_roles và quyền từ SQLite.
class AuthService {
  AuthService({Future<Database> Function()? openDatabase})
    : _openDatabase = openDatabase ?? (() => LocalDatabase.instance.database);

  final Future<Database> Function() _openDatabase;
  static const invalidCredentials = 'Tên đăng nhập hoặc mật khẩu không đúng.';
  Future<Database> get database => _openDatabase();

  static Future<String> hashPassword(String password) async {
    if (password.length < 8 || utf8.encode(password).length > 72) {
      throw const AuthException(
        'Mật khẩu cần ít nhất 8 ký tự và tối đa 72 byte UTF-8.',
      );
    }
    return compute(_hashPassword, password);
  }

  Future<bool> hasUsers() async => (await (await _openDatabase()).query(
    'users',
    columns: ['id'],
    limit: 1,
  )).isNotEmpty;

  Future<UserSession> signIn(String username, String password) async {
    final db = await _openDatabase();
    final users = await db.query(
      'users',
      where: 'username = ? AND is_active = 1',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (users.isEmpty || utf8.encode(password).length > 72) {
      throw const AuthException(invalidCredentials);
    }
    final user = users.single;
    final valid = await compute(_verifyPassword, (
      password,
      user['password_hash'] as String,
    ));
    if (!valid) throw const AuthException(invalidCredentials);
    // Đọc lại trạng thái sau khi xác minh mật khẩu.
    final current = await db.query(
      'users',
      where: 'id = ? AND is_active = 1',
      whereArgs: [user['id']],
    );
    if (current.isEmpty ||
        current.single['password_hash'] != user['password_hash']) {
      throw const AuthException(invalidCredentials);
    }
    final roles = await db.rawQuery(
      'SELECT r.code FROM roles r JOIN user_roles ur ON ur.role_id = r.id WHERE ur.user_id = ?',
      [user['id']],
    );
    final codes = roles.map((row) => row['code']).toSet();
    final role = codes.contains('admin')
        ? 'Admin'
        : codes.contains('manager')
        ? 'Quản lý'
        : codes.contains('employee')
        ? 'Nhân viên'
        : null;
    if (role == null) {
      throw const AuthException('Tài khoản chưa được cấp vai trò hợp lệ.');
    }
    final permissions = await db.rawQuery(
      'SELECT DISTINCT p.code FROM permissions p '
      'JOIN role_permissions rp ON rp.permission_id = p.id '
      'JOIN user_roles ur ON ur.role_id = rp.role_id WHERE ur.user_id = ?',
      [user['id']],
    );
    final profiles = await db.rawQuery(
      'SELECT e.*, d.name AS department_name, b.name AS branch_name, u.email '
      'FROM employees e JOIN users u ON u.id = e.user_id '
      'JOIN branches b ON b.id = e.branch_id '
      'LEFT JOIN departments d ON d.id = e.department_id WHERE e.user_id = ?',
      [user['id']],
    );
    return UserSession(
      userId: user['id'] as int,
      username: user['username'] as String,
      role: role,
      permissions: Set.unmodifiable(
        permissions.map((row) => row['code'] as String),
      ),
      profile: Map.unmodifiable(
        profiles.isEmpty ? {'email': user['email']} : profiles.single,
      ),
    );
  }

  /// Chỉ cho phép khởi tạo admin khi database chưa có bất kỳ tài khoản nào.
  Future<void> createFirstAdmin(String username, String password) async {
    final name = username.trim();
    if (name.isEmpty || name.length > 100) {
      throw const AuthException('Tên đăng nhập phải có từ 1 đến 100 ký tự.');
    }
    if (password.length < 8 || utf8.encode(password).length > 72) {
      throw const AuthException(
        'Mật khẩu cần ít nhất 8 ký tự và tối đa 72 byte UTF-8.',
      );
    }
    final hash = await compute(_hashPassword, password);
    final db = await _openDatabase();
    await db.transaction((tx) async {
      if ((await tx.query('users', columns: ['id'], limit: 1)).isNotEmpty) {
        throw const AuthException(
          'Database đã có tài khoản. Hãy đăng nhập bằng tài khoản được cấp.',
        );
      }
      final roles = await tx.query(
        'roles',
        where: 'code = ?',
        whereArgs: ['admin'],
      );
      if (roles.isEmpty) {
        throw const AuthException('Database thiếu vai trò admin.');
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
}
