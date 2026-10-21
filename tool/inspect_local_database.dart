import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Chỉ đọc số lượng nghiệp vụ và hồ sơ, không xuất mật khẩu hoặc token.
Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    File(args.single).absolute.path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    for (final table in [
      'users',
      'employees',
      'employee_devices',
      'branch_wifi',
      'contracts',
      'shift_templates',
      'shifts',
      'shift_assignments',
      'shift_swap_requests',
      'payslips',
      'star_events',
      'shift_closures',
      'audit_logs',
    ]) {
      stdout.writeln(
        '$table: ${await db.rawQuery('SELECT count(*) AS n FROM $table')}',
      );
    }
    stdout.writeln(
      jsonEncode(
        await db.rawQuery(
          'SELECT u.id,u.username,e.employee_code,e.branch_id FROM users u LEFT JOIN employees e ON e.user_id=u.id',
        ),
      ),
    );
    stdout.writeln(
      jsonEncode(await db.rawQuery('SELECT action FROM audit_logs')),
    );
  } finally {
    await db.close();
  }
}
