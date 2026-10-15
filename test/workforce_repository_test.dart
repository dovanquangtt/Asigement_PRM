import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture fixture;
  Future<WorkforceRepository> repository(
    String username,
    String password,
  ) async => WorkforceRepository(
    await fixture.auth.signIn(username, password),
    openDatabase: () async => fixture.db,
  );
  setUp(
    () async => fixture = await DatabaseFixture.open(keepSampleUsers: true),
  );
  tearDown(() => fixture.dispose());

  test(
    'Admin can create a real account; manager and employee cannot access users',
    () async {
      final admin = await repository('admin', 'Admin@12345');
      final manager = await repository('manager', 'Manager@12345');
      final employee = await repository('employee', 'Employee@12345');
      await admin.createUser(
        username: 'new_staff',
        password: 'NewStaff123!',
        role: 'employee',
      );
      expect(
        (await fixture.auth.signIn('new_staff', 'NewStaff123!')).role,
        'Nhân viên',
      );
      expect(await admin.users(), hasLength(4));
      await expectLater(manager.users(), throwsA(isA<AuthException>()));
      await expectLater(employee.users(), throwsA(isA<AuthException>()));
      await expectLater(
        manager.createUser(
          username: 'illegal',
          password: 'ValidPass123!',
          role: 'admin',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(
        await fixture.db.query(
          'users',
          where: 'username=?',
          whereArgs: ['illegal'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'Manager can save an employee and employee role cannot read personnel',
    () async {
      final manager = await repository('manager', 'Manager@12345');
      await manager.createEmployee(
        code: 'NV_TEST',
        name: 'Nhân viên kiểm thử',
        phone: '0901234567',
      );
      expect(
        (await fixture.db.query(
          'employees',
          where: 'employee_code=?',
          whereArgs: ['NV_TEST'],
        )).single['full_name'],
        'Nhân viên kiểm thử',
      );
      expect(await manager.employees(), hasLength(4));
      final employee = await repository('employee', 'Employee@12345');
      await expectLater(employee.employees(), throwsA(isA<AuthException>()));
      await expectLater(
        employee.createEmployee(code: 'ILLEGAL', name: 'Không được tạo'),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test('Employee only sees own shifts and payslips; manager sees all saved records', () async {
    final employee = await repository('employee', 'Employee@12345');
    final manager = await repository('manager', 'Manager@12345');
    final branch = (await fixture.db.query('branches')).first['id'];
    final shift = await fixture.db.insert('shifts', {
      'branch_id': branch,
      'starts_at': '2026-10-15 01:00:00',
      'ends_at': '2026-10-15 09:00:00',
      'required_staff': 2,
      'created_by': manager.session.userId,
    });
    final period = await fixture.db.insert('payroll_periods', {
      'code': 'TEST_2026_10',
      'starts_on': '2026-10-01',
      'ends_on': '2026-10-31',
    });
    for (final session in [employee.session, manager.session]) {
      final id = session.profile['id'];
      await fixture.db.insert('shift_assignments', {
        'shift_id': shift,
        'employee_id': id,
        'assigned_by': manager.session.userId,
      });
      final contract = await fixture.db.insert('contracts', {
        'employee_id': id,
        'contract_number': 'TEST_$id',
        'contract_type': 'fixed_term',
        'start_date': '2026-10-01',
        'salary_basis': 'monthly',
        'base_salary_vnd': 10000000,
      });
      await fixture.db.insert('payslips', {
        'period_id': period,
        'employee_id': id,
        'contract_id': contract,
        'base_pay_vnd': 10000000,
      });
    }
    final ownShifts = await employee.shifts();
    final ownPay = await employee.payslips();
    expect(ownShifts, hasLength(1));
    expect(ownShifts.single['employee_id'], employee.session.profile['id']);
    expect(ownPay, hasLength(1));
    expect(ownPay.single['employee_id'], employee.session.profile['id']);
    expect(await manager.shifts(), hasLength(2));
    expect(await manager.payslips(), hasLength(2));
  });

  test('Permission checks use current database even after login', () async {
    final admin = await repository('admin', 'Admin@12345');
    await fixture.db.update(
      'users',
      {'is_active': 0},
      where: 'id=?',
      whereArgs: [admin.session.userId],
    );
    await expectLater(admin.users(), throwsA(isA<AuthException>()));
    await expectLater(admin.profile(), throwsA(isA<AuthException>()));
  });
}
