import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/feature_sample_data.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Payroll approval and payment are separate and payment is tracked per employee', () async {
    final f = await DatabaseFixture.open(keepSampleUsers: true);
    try {
      await installFeatureSamples(f.db);
      Future<WorkforceRepository> repo(String user, String password) async =>
          WorkforceRepository(
            await f.auth.signIn(user, password),
            openDatabase: () async => f.db,
          );
      final admin = await repo('admin', 'Admin@12345');
      final manager = await repo('manager', 'Manager@12345');
      final employee = await repo('employee', 'Employee@12345');
      final period =
          (await f.db.query(
                'payroll_periods',
                where: "code='DEMO_OPEN'",
              )).single['id']
              as int;

      await manager.calculatePay(period);
      await manager.approvePayroll(period);
      final payslips = await f.db.query(
        'payslips',
        where: 'period_id=?',
        whereArgs: [period],
        orderBy: 'employee_id',
      );
      expect(payslips.every((pay) => pay['status'] == 'approved'), isTrue);
      expect(
        (await f.db.query(
          'payroll_periods',
          where: 'id=?',
          whereArgs: [period],
        )).single['status'],
        'approved',
      );
      expect(
        (await employee.notifications()).where(
          (message) => message['related_entity'] == 'payslips',
        ),
        isEmpty,
      );

      final employeeId =
          (await f.db.rawQuery(
                "SELECT e.id FROM employees e JOIN users u ON u.id=e.user_id WHERE u.username='employee'",
              )).single['id']
              as int;
      final employeePayslip = payslips.singleWhere(
        (pay) => pay['employee_id'] == employeeId,
      );
      await admin.confirmPayslipPaid(employeePayslip['id'] as int);

      expect(
        (await f.db.query(
          'payslips',
          where: 'id=?',
          whereArgs: [employeePayslip['id']],
        )).single['status'],
        'paid',
      );
      expect(
        (await employee.notifications()).singleWhere(
          (message) =>
              message['related_entity'] == 'payslips' &&
              message['related_id'] == employeePayslip['id'],
        )['title'],
        'Lương đã được xác nhận thanh toán',
      );
      expect(
        (await f.db.query(
          'payroll_periods',
          where: 'id=?',
          whereArgs: [period],
        )).single['status'],
        'approved',
      );
      await expectLater(
        employee.confirmPayslipPaid(employeePayslip['id'] as int),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        admin.confirmPayslipPaid(employeePayslip['id'] as int),
        throwsA(isA<AuthException>()),
      );

      final unpaid = payslips
          .where((pay) => pay['id'] != employeePayslip['id'])
          .toList();
      for (final pay in unpaid) {
        await manager.confirmPayslipPaid(pay['id'] as int);
      }
      expect(
        (await f.db.query(
          'payroll_periods',
          where: 'id=?',
          whereArgs: [period],
        )).single['status'],
        'paid',
      );
      expect(
        (await admin.periodPayslips(period))
            .where((pay) => pay['status'] == 'paid'),
        hasLength(payslips.length),
      );
      expect(
        (await f.db.query(
          'audit_logs',
          where: "action='payroll.payment_confirmed'",
        )),
        hasLength(payslips.length),
      );
    } finally {
      await f.dispose();
    }
  });
  test(
    'Payroll approval and device review notify only affected employee',
    () async {
      final f = await DatabaseFixture.open(keepSampleUsers: true);
      try {
        await installFeatureSamples(f.db);
        final admin = WorkforceRepository(
          await f.auth.signIn('admin', 'Admin@12345'),
          openDatabase: () async => f.db,
        );
        final employee = WorkforceRepository(
          await f.auth.signIn('employee', 'Employee@12345'),
          openDatabase: () async => f.db,
        );
        final manager = WorkforceRepository(
          await f.auth.signIn('manager', 'Manager@12345'),
          openDatabase: () async => f.db,
        );
        final period =
            (await f.db.query(
                  'payroll_periods',
                  where: "code='DEMO_OPEN'",
                )).single['id']
                as int;
        await admin.calculatePay(period);
        expect(
          (await employee.notifications()).where(
            (r) =>
                r['related_entity'] == 'payroll_periods' &&
                r['related_id'] == period,
          ),
          isEmpty,
        );
        await admin.approvePayroll(period);
        expect(
          (await employee.notifications()).where(
            (r) =>
                r['related_entity'] == 'payroll_periods' &&
                r['related_id'] == period,
          ),
          hasLength(1),
        );
        final devices = await f.db.rawQuery(
          "SELECT d.id FROM employee_devices d JOIN employees e ON e.id=d.employee_id JOIN users u ON u.id=e.user_id WHERE u.username='employee' LIMIT 1",
        );
        final device = devices.single['id'] as int;
        await admin.approveDevice(device, revoke: true);
        final message = (await employee.notifications()).singleWhere(
          (r) =>
              r['related_entity'] == 'employee_devices' &&
              r['related_id'] == device,
        );
        expect(message['read_at'], isNull);
        // Một tài khoản khác không thể đánh dấu thông báo của nhân viên đã đọc.
        await manager.markNotificationRead(message['id'] as int);
        expect(
          (await employee.notifications()).singleWhere(
            (r) => r['id'] == message['id'],
          )['read_at'],
          isNull,
        );
        expect(
          (await manager.notifications()).where(
            (r) =>
                r['related_entity'] == 'employee_devices' &&
                r['related_id'] == device,
          ),
          isEmpty,
        );
        await admin.approveDevice(device);
        expect(
          (await employee.notifications()).where(
            (r) =>
                r['related_entity'] == 'employee_devices' &&
                r['related_id'] == device,
          ),
          hasLength(2),
        );
        expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  for (final accept in [true, false]) {
    test(
      'Admin swap decision $accept reaches both participants only once',
      () async {
        final f = await DatabaseFixture.open(keepSampleUsers: true);
        try {
          await installFeatureSamples(f.db);
          Future<WorkforceRepository> repo(
            String user,
            String password,
          ) async => WorkforceRepository(
            await f.auth.signIn(user, password),
            openDatabase: () async => f.db,
          );
          final admin = await repo('admin', 'Admin@12345');
          final employee = await repo('employee', 'Employee@12345');
          final manager = await repo('manager', 'Manager@12345');
          final request = (await f.db.query(
            'shift_swap_requests',
            where: "status='pending' AND counterpart_status='accepted'",
          )).single;
          final id = request['id'] as int;
          final before = await f.db.query('shift_assignments');
          await admin.respondSwap(id, accept, review: true);
          expect(
            (await employee.swaps()).singleWhere(
              (r) => r['id'] == id,
            )['status'],
            accept ? 'approved' : 'rejected',
          );
          for (final recipient in [employee, manager]) {
            final messages = (await recipient.notifications())
                .where(
                  (r) =>
                      r['related_entity'] == 'shift_swap_requests' &&
                      r['related_id'] == id,
                )
                .toList();
            expect(messages, hasLength(1));
            expect(messages.single['read_at'], isNull);
            await recipient.markNotificationRead(messages.single['id'] as int);
            expect(
              (await recipient.notifications()).singleWhere(
                (r) => r['id'] == messages.single['id'],
              )['read_at'],
              isNotNull,
            );
          }
          final employeeMessage = (await employee.notifications()).first;
          await admin.markNotificationRead(employeeMessage['id'] as int);
          expect(
            (await admin.notifications()).where(
              (r) =>
                  r['related_id'] == id &&
                  r['related_entity'] == 'shift_swap_requests',
            ),
            isEmpty,
          );
          if (!accept) expect(await f.db.query('shift_assignments'), before);
          final count = (await f.db.query('notifications')).length;
          await expectLater(
            admin.respondSwap(id, accept, review: true),
            throwsA(isA<AuthException>()),
          );
          expect(await f.db.query('notifications'), hasLength(count));
        } finally {
          await f.dispose();
        }
      },
    );
    test(
      'Closure decision $accept is visible to employee with notification',
      () async {
        final f = await DatabaseFixture.open(keepSampleUsers: true);
        try {
          await installFeatureSamples(f.db);
          final admin = WorkforceRepository(
            await f.auth.signIn('admin', 'Admin@12345'),
            openDatabase: () async => f.db,
          );
          final employee = WorkforceRepository(
            await f.auth.signIn('employee', 'Employee@12345'),
            openDatabase: () async => f.db,
          );
          final row = (await employee.closures()).firstWhere(
            (r) => r['status'] == 'submitted',
          );
          final id = row['id'] as int;
          await admin.reviewClosure(id, accept);
          expect(
            (await employee.closures()).singleWhere(
              (r) => r['id'] == id,
            )['status'],
            accept ? 'approved' : 'rejected',
          );
          expect(
            (await employee.notifications()).where(
              (r) =>
                  r['related_entity'] == 'shift_closures' &&
                  r['related_id'] == id,
            ),
            hasLength(1),
          );
        } finally {
          await f.dispose();
        }
      },
    );
  }
}
