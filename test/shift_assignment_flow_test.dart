import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Luồng: quản lý tạo ca -> phân công -> nhân viên thấy ca và nhận thông báo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager, admin;
  late int branchId, employeeId;
  final start = DateTime.now().toUtc().add(const Duration(days: 2));

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    Future<WorkforceRepository> repo(String name, String pass) async =>
        WorkforceRepository(
          await f.auth.signIn(name, pass),
          openDatabase: () async => f.db,
        );
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    admin = await repo('admin', 'Admin@12345');
    branchId = employee.session.profile['branch_id'] as int;
    employeeId = employee.session.profile['id'] as int;
  });
  tearDown(() => f.dispose());

  Future<int> newShift(WorkforceRepository by) => by.createShift(
    branchId: branchId,
    start: start,
    end: start.add(const Duration(hours: 8)),
  );

  test(
    'A new shift is invisible to employees until they are assigned',
    () async {
      final shift = await newShift(admin);
      expect(await employee.employeeSchedule(), isEmpty);
      expect(
        (await admin.eligibleEmployeesForShift(shift))
            .where((e) => e['id'] == employeeId && e['is_available'] == true),
        hasLength(1),
      );
      await admin.assignShift(shift, employeeId);
      final mine = await employee.employeeSchedule();
      expect(mine, hasLength(1));
      expect(mine.single['shift_id'], shift);
    },
  );

  test('Assigning notifies the employee; the actor is not notified', () async {
    final shift = await newShift(admin);
    await admin.assignShift(shift, employeeId);
    final notes = await employee.notifications();
    final note = notes.singleWhere((n) => n['title'] == 'Bạn có ca làm mới');
    expect(note['related_entity'], 'shifts');
    expect(note['related_id'], shift);
    expect(note['body'], contains('Bạn được phân vào ca'));
    expect(
      (await admin.notifications()).where(
        (n) => n['title'] == 'Bạn có ca làm mới',
      ),
      isEmpty,
    );
  });

  test('Unassign and cancel notify the employee and hide the shift', () async {
    final a = await newShift(manager);
    await manager.assignShift(a, employeeId);
    await manager.unassignShift(a, employeeId);
    expect(await employee.employeeSchedule(), isEmpty);
    final b = await newShift(manager);
    await manager.assignShift(b, employeeId);
    await manager.cancelShift(b);
    final titles = (await employee.notifications())
        .map((n) => n['title'])
        .toList();
    expect(titles, containsAll(['Ca làm đã bị gỡ', 'Ca làm đã bị hủy']));
    expect(
      (await employee.employeeSchedule()).where(
        (s) =>
            s['shift_status'] != 'cancelled' &&
            s['assignment_status'] != 'cancelled',
      ),
      isEmpty,
    );
  });

  test('Employee in another branch is not eligible', () async {
    final other = await f.db.insert('branches', {
      'code': 'B2',
      'name': 'Chi nhánh 2',
    });
    final shift = await admin.createShift(
      branchId: other,
      start: start,
      end: start.add(const Duration(hours: 8)),
    );
    final eligible = await admin.eligibleEmployeesForShift(shift);
    expect(eligible.any((e) => e['id'] == employeeId), isFalse);
    await expectLater(
      admin.assignShift(shift, employeeId),
      throwsA(isA<AuthException>()),
    );
  });

  test('Employees cannot create or assign shifts', () async {
    await expectLater(
      employee.createShift(
        branchId: branchId,
        start: start,
        end: start.add(const Duration(hours: 4)),
      ),
      throwsA(isA<AuthException>()),
    );
  });
  Future<int> assignment(int shift) async =>
      (await f.db.query(
            'shift_assignments',
            where: 'shift_id=? AND employee_id=?',
            whereArgs: [shift, employeeId],
          )).single['id']
          as int;

  test(
    'New assignment is pending; employee accepts and the manager is told',
    () async {
      final shift = await newShift(admin);
      await admin.assignShift(shift, employeeId);
      final mine = (await employee.employeeSchedule()).single;
      expect(mine['response_status'], 'pending');
      await employee.respondAssignment(mine['assignment_id'] as int, true);
      expect(
        (await employee.employeeSchedule()).single['response_status'],
        'accepted',
      );
      final notes = await admin.notifications();
      expect(notes.any((n) => n['title'] == 'Nhân viên chấp nhận ca'), isTrue);
      await expectLater(
        employee.respondAssignment(mine['assignment_id'] as int, true),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'Rejecting needs a reason, frees the slot and stays visible in the table',
    () async {
      final shift = await newShift(admin);
      await admin.assignShift(shift, employeeId);
      final id = await assignment(shift);
      await expectLater(
        employee.respondAssignment(id, false),
        throwsA(isA<AuthException>()),
      );
      await employee.respondAssignment(id, false, note: 'Bận việc gia đình');
      expect(await employee.employeeSchedule(), isEmpty);
      // The slot is free again: the same employee can be offered the shift once more.
      final eligible = await admin.eligibleEmployeesForShift(shift);
      expect(
        eligible.singleWhere((e) => e['id'] == employeeId)['is_available'],
        isTrue,
      );
      final table = await admin.employeeShiftTable(
        employeeId,
        from: DateTime.now().subtract(const Duration(days: 1)),
        to: DateTime.now().add(const Duration(days: 30)),
      );
      final rows = table['rows'] as List<RowData>;
      expect(rows.single['response_status'], 'rejected');
      expect(rows.single['response_note'], 'Bận việc gia đình');
      expect((table['summary'] as RowData)['rejected'], 1);
      final titles = (await admin.notifications()).map((n) => n['title']);
      expect(titles, contains('Nhân viên từ chối ca'));
    },
  );

  test(
    'Cannot respond to a started shift or to someone else’s assignment',
    () async {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final shift = await manager.createShift(
        branchId: branchId,
        start: past,
        end: past.add(const Duration(hours: 8)),
      );
      await manager.assignShift(shift, employeeId);
      final id = await assignment(shift);
      await expectLater(
        employee.respondAssignment(id, true),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        manager.respondAssignment(id, true),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'Shift table lists every shift of an employee and respects roles',
    () async {
      final a = await newShift(admin);
      final b = await admin.createShift(
        branchId: branchId,
        start: start.add(const Duration(days: 1)),
        end: start.add(const Duration(days: 1, hours: 8)),
      );
      await admin.assignShift(a, employeeId);
      await admin.assignShift(b, employeeId);
      final table = await manager.employeeShiftTable(
        employeeId,
        from: DateTime.now().subtract(const Duration(days: 1)),
        to: DateTime.now().add(const Duration(days: 30)),
      );
      expect((table['rows'] as List).length, 2);
      expect((table['summary'] as RowData)['pending'], 2);
      final first = (table['rows'] as List).first as RowData;
      expect(first['pending_check_in_id'], isNull);
      expect(first['sheet_status'], 'NOT_STARTED');
      expect(
        (await manager.shiftTableEmployees()).any((e) => e['id'] == employeeId),
        isTrue,
      );
      await expectLater(
        employee.employeeShiftTable(
          employeeId,
          from: DateTime.now(),
          to: DateTime.now(),
        ),
        throwsA(isA<AuthException>()),
      );
    },
  );
}
