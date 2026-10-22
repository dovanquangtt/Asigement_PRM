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

  test('Manager can view shift overview with metrics and staffing counts', () async {
    final manager = await repository('manager', 'Manager@12345');
    final employee = await repository('employee', 'Employee@12345');
    final branch = (await fixture.db.query('branches')).first['id'] as int;

    final shiftId = await manager.createShift(
      branchId: branch,
      start: DateTime.parse('2026-11-10T08:00:00Z'),
      end: DateTime.parse('2026-11-10T16:00:00Z'),
      requiredStaff: 2,
      note: 'Ca quản lý kiểm thử',
    );

    final empId = employee.session.profile['id'] as int;
    await manager.assignShift(shiftId, empId);

    final overview = await manager.managerShiftOverview();
    expect(overview, isNotEmpty);

    final createdShift = overview.firstWhere((s) => s['id'] == shiftId);
    expect(createdShift['branch_name'], isNotEmpty);
    expect(createdShift['assigned_count'], 1);
    expect(createdShift['required_staff'], 2);
    expect(createdShift['assigned_staff_names'], contains(employee.session.profile['full_name']));
  });

  test('Manager can query eligible employees with availability and conflict reasons', () async {
    final manager = await repository('manager', 'Manager@12345');
    final employee = await repository('employee', 'Employee@12345');
    final branch = (await fixture.db.query('branches')).first['id'] as int;

    final start = DateTime.parse('2026-11-12T08:00:00Z');
    final end = DateTime.parse('2026-11-12T16:00:00Z');

    final shiftId = await manager.createShift(
      branchId: branch,
      start: start,
      end: end,
      requiredStaff: 2,
    );

    final empId = employee.session.profile['id'] as int;

    // Trước khi phân: nhân viên phải khả dụng
    var eligible = await manager.eligibleEmployeesForShift(shiftId);
    var targetEmp = eligible.firstWhere((e) => e['id'] == empId);
    expect(targetEmp['is_available'], isTrue);
    expect(targetEmp['conflict_reason'], isNull);

    // Phân nhân viên vào ca
    await manager.assignShift(shiftId, empId);

    // Sau khi phân: nhân viên báo 'Đã phân vào ca này'
    eligible = await manager.eligibleEmployeesForShift(shiftId);
    targetEmp = eligible.firstWhere((e) => e['id'] == empId);
    expect(targetEmp['is_available'], isFalse);
    expect(targetEmp['conflict_reason'], 'Đã phân vào ca này');
  });

  test('Manager can unassign employee and cancel shift', () async {
    final manager = await repository('manager', 'Manager@12345');
    final employee = await repository('employee', 'Employee@12345');
    final branch = (await fixture.db.query('branches')).first['id'] as int;

    final shiftId = await manager.createShift(
      branchId: branch,
      start: DateTime.parse('2026-11-15T08:00:00Z'),
      end: DateTime.parse('2026-11-15T16:00:00Z'),
      requiredStaff: 2,
    );

    final empId = employee.session.profile['id'] as int;
    await manager.assignShift(shiftId, empId);

    // Unassign
    await manager.unassignShift(shiftId, empId);
    final overviewAfterUnassign = await manager.managerShiftOverview();
    final shiftAfter = overviewAfterUnassign.firstWhere((s) => s['id'] == shiftId);
    expect(shiftAfter['assigned_count'], 0);

    // Cancel shift
    await manager.cancelShift(shiftId);
    final shiftRow = (await fixture.db.query('shifts', where: 'id=?', whereArgs: [shiftId])).single;
    expect(shiftRow['status'], 'cancelled');
  });

  test('Employee cannot access manager shift overview or assign staff', () async {
    final employee = await repository('employee', 'Employee@12345');
    await expectLater(employee.managerShiftOverview(), throwsA(isA<AuthException>()));
    await expectLater(employee.eligibleEmployeesForShift(1), throwsA(isA<AuthException>()));
    await expectLater(employee.unassignShift(1, 1), throwsA(isA<AuthException>()));
    await expectLater(employee.cancelShift(1), throwsA(isA<AuthException>()));
  });
}
