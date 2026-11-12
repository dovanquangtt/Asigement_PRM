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

  /// Báo cáo đóng ca thật (ảnh JPEG nằm trong thư mục tạm) cho phân ca thứ [index] của [user].
  /// Dữ liệu mẫu không còn báo cáo/ảnh DEMO nên test tự dựng báo cáo cần dùng.
  Future<int> addClosure({
    String user = 'employee',
    String status = 'submitted',
    int index = 0,
  }) async {
    final userRow = (await db.query(
      'users',
      where: 'username=?',
      whereArgs: [user],
    )).single;
    final assignments = await db.rawQuery(
      'SELECT a.id FROM shift_assignments a JOIN employees e ON e.id=a.employee_id '
      "WHERE e.user_id=? AND a.id NOT IN (SELECT assignment_id FROM shift_closures) ORDER BY a.id",
      [userRow['id']],
    );
    final reviewer = (await db.query(
      'users',
      where: "username='admin'",
    )).single['id'];
    final photo = File(
      p.join(
        directory.path,
        'closure_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ),
    );
    // Không tạo file thật: Image.file giữ handle làm Windows không xóa được thư mục tạm.
    final id = await db.insert('shift_closures', {
      'assignment_id': assignments[index]['id'],
      'submitted_by': userRow['id'],
      'note': 'Đã dọn dẹp và bàn giao ca.',
      'submitted_at': '2026-10-15 16:00:00',
      'status': status,
      if (status != 'submitted') 'reviewed_by': reviewer,
      if (status != 'submitted') 'reviewed_at': '2026-10-15 16:30:00',
    });
    await db.insert('shift_closure_photos', {
      'closure_id': id,
      'file_url': photo.path,
      'captured_at': '2026-10-15 16:00:00',
    });
    return id;
  }

  Future<void> dispose() async {
    await db.close();
    await directory.delete(recursive: true);
  }
}
