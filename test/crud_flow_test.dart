import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture fixture;

  Future<WorkforceRepository> repository(String u, String p) async =>
      WorkforceRepository(
        await fixture.auth.signIn(u, p),
        openDatabase: () async => fixture.db,
      );

  setUp(
    () async => fixture = await DatabaseFixture.open(keepSampleUsers: true),
  );
  tearDown(() => fixture.dispose());

  test('Shift update changes time, asks employee to confirm again and notifies', () async {
    final manager = await repository('manager', 'Manager@12345');
    final employee = await repository('employee', 'Employee@12345');
    final branch = (await fixture.db.query('branches')).first['id'] as int;
    final shiftId = await manager.createShift(
      branchId: branch,
      start: DateTime.now().toUtc().add(const Duration(days: 3)),
      end: DateTime.now().toUtc().add(const Duration(days: 3, hours: 8)),
      requiredStaff: 2,
    );
    await manager.assignShift(shiftId, employee.session.profile['id'] as int);
    final newStart = DateTime.now().toUtc().add(const Duration(days: 4));
    await manager.updateShift(
      shiftId,
      start: newStart,
      end: newStart.add(const Duration(hours: 6)),
      requiredStaff: 3,
      note: 'đổi giờ',
    );
    final shift = (await fixture.db.query('shifts', where: 'id=?', whereArgs: [shiftId])).single;
    expect(shift['required_staff'], 3);
    expect(shift['note'], 'đổi giờ');
    final a = (await fixture.db.query('shift_assignments', where: 'shift_id=?', whereArgs: [shiftId])).single;
    expect(a['response_status'], 'pending');
    expect(
      (await employee.notifications()).any((n) => n['title'] == 'Ca làm đã được cập nhật'),
      isTrue,
    );
    // Không thể giảm số người cần xuống dưới số đã phân.
    await expectLater(
      manager.updateShift(shiftId, start: newStart, end: newStart.add(const Duration(hours: 6)), requiredStaff: 0),
      throwsA(isA<AuthException>()),
    );
  });

  test('Employee update and delete keep history, lock account and unassign future shifts', () async {
    final manager = await repository('manager', 'Manager@12345');
    final admin = await repository('admin', 'Admin@12345');
    final employee = await repository('employee', 'Employee@12345');
    final empId = employee.session.profile['id'] as int;
    final branch = (await fixture.db.query('branches')).first['id'] as int;
    final shiftId = await manager.createShift(
      branchId: branch,
      start: DateTime.now().toUtc().add(const Duration(days: 3)),
      end: DateTime.now().toUtc().add(const Duration(days: 3, hours: 8)),
    );
    await manager.assignShift(shiftId, empId);

    await admin.updateEmployee(empId, code: 'NV-SUA', name: 'Tên đã sửa', phone: '0900000000');
    expect((await admin.employees()).firstWhere((e) => e['id'] == empId)['full_name'], 'Tên đã sửa');

    await admin.deleteEmployee(empId);
    expect((await admin.employees()).any((e) => e['id'] == empId), isFalse);
    final row = (await fixture.db.query('employees', where: 'id=?', whereArgs: [empId])).single;
    expect(row['status'], 'terminated');
    final user = (await fixture.db.query('users', where: 'id=?', whereArgs: [row['user_id']])).single;
    expect(user['is_active'], 0);
    final a = (await fixture.db.query('shift_assignments', where: 'employee_id=?', whereArgs: [empId])).single;
    expect(a['status'], 'cancelled');
  });
}
