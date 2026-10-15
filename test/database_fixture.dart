import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:path/path.dart' as p;
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseFixture {
  DatabaseFixture(this.directory, this.db);
  final Directory directory;
  final Database db;
  AuthService get auth => AuthService(openDatabase: () async => db);
  static Future<DatabaseFixture> open({bool keepSampleUsers = false}) async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('prm_auth_test_');
    final db = await LocalDatabase.openBundledDatabase(
      databaseFactoryFfi,
      p.join(directory.path, 'prm_database.db'),
    );
    // Mỗi bài kiểm thử auth tự tạo tài khoản riêng trong SQLite thật.
    if (!keepSampleUsers) {
      await db.update('employees', {'manager_id': null});
      await db.delete('employees');
      await db.delete('user_roles');
      await db.delete('users');
    }
    return DatabaseFixture(directory, db);
  }

  Future<int> addUser({
    String username = 'linh',
    String? role = 'employee',
    int active = 1,
  }) async {
    final id = await db.insert('users', {
      'username': username,
      'password_hash': BCrypt.hashpw(
        'TestPass123!',
        BCrypt.gensalt(logRounds: 4),
      ),
      'is_active': active,
    });
    if (role != null) {
      final roles = await db.query(
        'roles',
        where: 'code = ?',
        whereArgs: [role],
      );
      await db.insert('user_roles', {
        'user_id': id,
        'role_id': roles.single['id'],
      });
    }
    return id;
  }

  Future<void> dispose() async {
    await db.close();
    await directory.delete(recursive: true);
  }
}
