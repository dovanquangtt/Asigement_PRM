import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:path/path.dart' as p;
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quanlinhansunhahang/services/sample_data.dart';
import 'package:quanlinhansunhahang/services/feature_migrations.dart';

/// Các script schema/danh mục này không có dấu ; trong literal.
/// Bỏ comment nguyên dòng trước khi tách để comment có dấu ; vẫn hợp lệ.
Future<List<String>> fixtureSqlStatements(String path) async {
  final lines = await File(path).readAsLines();
  return lines
      .where((line) => !line.trimLeft().startsWith('--'))
      .join('\n')
      .split(';')
      .where((statement) => statement.trim().isNotEmpty)
      .toList();
}

class DatabaseFixture {
  DatabaseFixture(this.directory, this.db);
  final Directory directory;
  final Database db;
  AuthService get auth => AuthService(openDatabase: () async => db);
  static Future<DatabaseFixture> open({
    bool keepSampleUsers = false,
    bool bundledData = false,
  }) async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('prm_auth_test_');
    final filename = p.join(directory.path, 'prm_database.db');
    final db = bundledData
        ? await LocalDatabase.openBundledDatabase(databaseFactoryFfi, filename)
        : await databaseFactoryFfi.openDatabase(filename);
    if (!bundledData) {
      // Test nghiệp vụ tự tạo bản ghi của nó, độc lập số lượng dữ liệu DEMO.
      for (final script in [
        'database/prm_schema.sql',
        'database/prm_seed.sql',
      ]) {
        for (final statement in await fixtureSqlStatements(script)) {
          await db.execute(statement);
        }
      }
      await installSampleData(db);
      await migrateFeatures(db);
    }
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
