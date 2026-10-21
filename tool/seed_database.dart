import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quanlinhansunhahang/services/sample_data.dart';
import 'package:quanlinhansunhahang/services/feature_migrations.dart';
import 'package:quanlinhansunhahang/services/feature_sample_data.dart';

import 'create_demo_image.dart';

String sqlLiteral(Object? value) {
  if (value == null) return 'NULL';
  if (value is num) return value.toString();
  return "'${value.toString().replaceAll("'", "''")}'";
}

/// Snapshot SQL để đọc trong IDE và khôi phục trên schema v4 đang trống.
/// Không dùng REPLACE/DELETE: chạy nhầm trên database có dữ liệu sẽ báo trùng.
Future<void> exportDemoSql(Database db) async {
  const order = [
    'roles',
    'permissions',
    'role_permissions',
    'users',
    'user_roles',
    'branches',
    'branch_wifi',
    'departments',
    'positions',
    'employees',
    'employee_devices',
    'contracts',
    'shift_templates',
    'shifts',
    'shift_assignments',
    'attendance_events',
    'attendance_records',
    'attendance_adjustment_requests',
    'leave_types',
    'leave_balances',
    'leave_requests',
    'shift_swap_requests',
    'payroll_periods',
    'payroll_policies',
    'payslips',
    'payslip_items',
    'payroll_calculation_steps',
    'employee_payroll_checks',
    'star_events',
    'shift_closures',
    'shift_closure_photos',
    'notifications',
    'notification_recipients',
    'audit_logs',
  ];
  final text = StringBuffer(
    '-- DU LIEU MAU DAY DU CHO 3 ROLE / 34 BANG.\n-- Snapshot cua prm_database.db; anh dung asset URI, khong co duong dan may.\n-- CHI CHAY TREN SCHEMA v4 TRONG; KHONG CHAY SAU prm_seed.sql.\n-- Tai khoan: admin/Admin@12345, manager/Manager@12345, employee/Employee@12345.\nPRAGMA foreign_keys=ON;\nBEGIN;\n',
  );
  for (final table in order) {
    final rows = await db.query(table);
    text.writeln('\n-- $table: ${rows.length} rows');
    for (final row in rows) {
      text.writeln(
        'INSERT INTO "$table" (${row.keys.map((key) => '"$key"').join(',')}) VALUES (${row.values.map(sqlLiteral).join(',')});',
      );
    }
  }
  text.writeln('PRAGMA user_version=4;\nCOMMIT;');
  await File('database/prm_demo_seed.sql')
      .writeAsString(text.toString(), flush: true);
}

Future<void> main() async {
  sqfliteFfiInit();
  final filename = File('database/prm_database.db').absolute.path;
  if (!File(filename).existsSync()) throw StateError('Không tìm thấy database');
  final db = await databaseFactoryFfi.openDatabase(filename);
  try {
    await db.execute('PRAGMA foreign_keys = ON');
    await installSampleData(db);
    await migrateFeatures(db);
    await createDemoClosureImage();
    final installed = await installFeatureSamples(db);
    await exportDemoSql(db);
    stdout.writeln(
      installed
          ? 'Đã nạp dữ liệu DEMO cho toàn bộ chức năng.'
          : 'Bộ DEMO đã có; không ghi đè hay nhân đôi.',
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    for (final table in tables) {
      final name = table['name'] as String;
      final count = (await db.rawQuery('SELECT COUNT(*) AS total FROM "$name"'))
          .single['total'];
      stdout.writeln('$name: $count');
    }
    stdout.writeln(
      await db.rawQuery(
        'SELECT u.username, r.code AS role, e.full_name FROM users u JOIN user_roles ur ON ur.user_id=u.id JOIN roles r ON r.id=ur.role_id LEFT JOIN employees e ON e.user_id=u.id',
      ),
    );
    stdout.writeln(await db.rawQuery('PRAGMA integrity_check'));
    stdout.writeln(await db.rawQuery('PRAGMA foreign_key_check'));
  } finally {
    await db.close();
  }
}
