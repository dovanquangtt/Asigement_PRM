import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/feature_sample_data.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/screens/operations_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quanlinhansunhahang/services/feature_migrations.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<WorkforceRepository> repo(
    DatabaseFixture f,
    String name,
    String pass,
  ) async => WorkforceRepository(
    await f.auth.signIn(name, pass),
    openDatabase: () async => f.db,
  );
  test(
    'Admin imports into old local database without resetting account or GPS',
    () async {
      final f = await DatabaseFixture.open(keepSampleUsers: true);
      try {
        await f.db.update('branches', {'latitude': 20.0, 'longitude': 105.0});
        await f.db.update(
          'users',
          {'password_hash': 'keep_custom_hash', 'is_active': 0},
          where: 'username=?',
          whereArgs: ['employee'],
        );
        final admin = await repo(f, 'admin', 'Admin@12345');
        final managerProfile = (await f.db.rawQuery(
          "SELECT e.id FROM employees e JOIN users u ON u.id=e.user_id WHERE u.username='manager'",
        )).single['id'];
        final annualType = (await f.db.query(
          'leave_types',
          where: 'code=?',
          whereArgs: ['ANNUAL'],
        )).single['id'];
        await f.db.insert('leave_balances', {
          'employee_id': managerProfile,
          'leave_type_id': annualType,
          'year': DateTime.now().toUtc().add(const Duration(hours: 7)).year,
          'granted_minutes': 6000,
          'used_minutes': 120,
        });
        expect(await admin.installDemoData(), isTrue);
        expect(await admin.installDemoData(), isFalse);
        final user = (await f.db.query(
          'users',
          where: 'username=?',
          whereArgs: ['employee'],
        )).single;
        expect(user['password_hash'], 'keep_custom_hash');
        expect(user['is_active'], 0);
        expect((await f.db.query('branches')).single['latitude'], 20.0);
        final balance = (await f.db.query(
          'leave_balances',
          where: 'employee_id=? AND leave_type_id=?',
          whereArgs: [managerProfile, annualType],
        )).single;
        expect(balance['granted_minutes'], 6000);
        expect(balance['used_minutes'], 120);
        expect(await f.db.query('shifts'), hasLength(13));
        expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'Import conflict rolls back completely instead of changing existing data',
    () async {
      final f = await DatabaseFixture.open(keepSampleUsers: true);
      try {
        await f.db.insert('shift_templates', {
          'code': 'DEMO_MORNING',
          'name': 'Giữ nguyên ca đã nhập',
          'start_time': '08:00',
          'end_time': '16:00',
        });
        await expectLater(
          installFeatureSamples(f.db),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await f.db.query('shift_templates')).single['name'],
          'Giữ nguyên ca đã nhập',
        );
        expect((await f.db.query('branches')).single['latitude'], isNull);
        expect(await f.db.query('branch_wifi'), isEmpty);
        expect(await f.db.query('contracts'), isEmpty);
        expect(await f.db.query('shifts'), isEmpty);
        expect(await f.db.query('audit_logs'), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'All 34 bundled tables have data and all five views are readable',
    () async {
      final f = await DatabaseFixture.open(
        keepSampleUsers: true,
        bundledData: true,
      );
      try {
        final tables = await f.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        expect(tables, hasLength(34));
        for (final table in tables) {
          final name = table['name'];
          final count =
              (await f.db.rawQuery('SELECT COUNT(*) n FROM "$name"'))
                      .single['n']
                  as int;
          expect(
            count,
            greaterThan(0),
            reason: 'Bảng $name phải có dữ liệu mẫu',
          );
        }
        final views = await f.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='view'",
        );
        expect(views, hasLength(5));
        for (final view in views) {
          expect(
            await f.db.rawQuery('SELECT * FROM "${view['name']}"'),
            isNotEmpty,
          );
        }
        expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await f.db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
        expect(await f.db.query('users'), hasLength(3));
        expect(await f.db.query('payslips'), hasLength(6));
        expect(await f.db.query('shifts'), hasLength(13));
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'Seed is idempotent and preserves edited password, GPS and payroll data',
    () async {
      final f = await DatabaseFixture.open(
        keepSampleUsers: true,
        bundledData: true,
      );
      try {
        await f.db.update('branches', {'latitude': 20.0, 'longitude': 105.0});
        await f.db.update(
          'users',
          {'password_hash': 'edited_value'},
          where: 'username=?',
          whereArgs: ['employee'],
        );
        final rows = await f.db.query('payslips');
        final counts = await f.db.query('shift_assignments');
        expect(await installFeatureSamples(f.db), isFalse);
        expect(await f.db.query('payslips'), rows);
        expect(await f.db.query('shift_assignments'), counts);
        expect((await f.db.query('branches')).single['latitude'], 20.0);
        expect(
          (await f.db.query(
            'users',
            where: 'username=?',
            whereArgs: ['employee'],
          )).single['password_hash'],
          'edited_value',
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test('Seeded payroll can be recalculated and approved without touching paid period', () async {
    final f = await DatabaseFixture.open(
      keepSampleUsers: true,
      bundledData: true,
    );
    try {
      final manager = await repo(f, 'manager', 'Manager@12345');
      final employee = await repo(f, 'employee', 'Employee@12345');
      expect(await manager.payslips(), hasLength(6));
      expect(await employee.payslips(), hasLength(2));
      final open =
          (await f.db.query(
                'payroll_periods',
                where: 'code=?',
                whereArgs: ['DEMO_OPEN'],
              )).single['id']
              as int;
      final paid =
          (await f.db.query(
                'payroll_periods',
                where: 'code=?',
                whereArgs: ['DEMO_PAID'],
              )).single['id']
              as int;
      final paidRows = await f.db.query(
        'payslips',
        where: 'period_id=?',
        whereArgs: [paid],
      );
      final before = await f.db.query(
        'v_payslip_totals',
        where: 'period_id=?',
        whereArgs: [open],
      );
      await manager.calculatePay(open);
      final after = await f.db.query(
        'v_payslip_totals',
        where: 'period_id=?',
        whereArgs: [open],
      );
      expect(
        after.map((r) => r['net_pay_vnd']).toList(),
        before.map((r) => r['net_pay_vnd']).toList(),
      );
      await manager.approvePayroll(open);
      expect(
        await f.db.query('payslips', where: 'period_id=?', whereArgs: [paid]),
        paidRows,
      );
      await expectLater(
        employee.calculatePay(paid),
        throwsA(isA<AuthException>()),
      );
    } finally {
      await f.dispose();
    }
  });
  test(
    'Seeded swap ready for Admin approval works; other roles cannot import',
    () async {
      final f = await DatabaseFixture.open(keepSampleUsers: true);
      try {
        // Seed future shifts now; the bundled snapshot eventually expires.
        await installFeatureSamples(f.db);
        final admin = await repo(f, 'admin', 'Admin@12345');
        final manager = await repo(f, 'manager', 'Manager@12345');
        final employee = await repo(f, 'employee', 'Employee@12345');
        await expectLater(
          employee.installDemoData(),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          manager.installDemoData(),
          throwsA(isA<AuthException>()),
        );
        final request = (await f.db.query(
          'shift_swap_requests',
          where: "status='pending' AND counterpart_status='accepted'",
        )).single;
        await admin.respondSwap(request['id'] as int, true, review: true);
        expect(
          (await f.db.query(
            'shift_assignments',
            where: 'id=?',
            whereArgs: [request['from_assignment_id']],
          )).single['employee_id'],
          request['to_employee_id'],
        );
        expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  test('SQL snapshot restores full database on empty migrated schema', () async {
    sqfliteFfiInit();
    final folder = await Directory.systemTemp.createTemp('prm_snapshot_');
    final db = await databaseFactoryFfi.openDatabase(
      '${folder.path}/snapshot.db',
    );
    try {
      for (final s in (await File(
        'database/prm_schema.sql',
      ).readAsString()).split(';')) {
        if (s.trim().isNotEmpty) await db.execute(s);
      }
      await migrateFeatures(db);
      // Không tách bằng dấu ; ở đây vì chuỗi SQL có thể chứa dấu ; trong text.
      final dump = await File('database/prm_demo_seed.sql').readAsLines();
      for (final line in dump) {
        if (line.trim().isNotEmpty && !line.trimLeft().startsWith('--')) {
          await db.execute(line);
        }
      }
      expect(await db.query('users'), hasLength(3));
      expect(await db.query('payslips'), hasLength(6));
      expect(await db.query('shift_assignments'), hasLength(18));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await installFeatureSamples(db), isFalse);
    } finally {
      await db.close();
      await folder.delete(recursive: true);
    }
  });
  test('Demo photo is a valid portable asset', () async {
    final bytes = await rootBundle.load(closureSampleAsset);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 384);
    expect(frame.image.height, 216);
    frame.image.dispose();
    codec.dispose();
  });
  testWidgets('Closure photo preview renders asset instead of machine path', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: closurePhotoPreview({
            'file_url': 'asset:$closureSampleAsset',
            'caption': 'Ảnh minh họa DEMO',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Ảnh minh họa DEMO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
