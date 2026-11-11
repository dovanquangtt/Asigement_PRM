import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository employee, manager, admin;
  late int annual;
  final year = DateTime.now().year;
  // Một ngày nghỉ 8 tiếng (480 phút) sau hôm nay.
  final from = DateTime.now().toUtc().add(const Duration(days: 10));
  final to = from.add(const Duration(hours: 8));

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  Future<int> request({int? type, DateTime? start, DateTime? end}) async {
    await employee.createLeaveRequest(
      leaveTypeId: type ?? annual,
      start: start ?? from,
      end: end ?? to,
      reason: 'Việc gia đình',
    );
    return (await f.db.query(
          'leave_requests',
          orderBy: 'id DESC',
          limit: 1,
        )).single['id']
        as int;
  }

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    employee = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    admin = await repo('admin', 'Admin@12345');
    annual =
        (await f.db.query('leave_types', where: "code='ANNUAL'")).single['id']
            as int;
    await f.db.insert('leave_balances', {
      'employee_id': employee.session.profile['id'],
      'leave_type_id': annual,
      'year': year,
      'granted_minutes': 960, // 2 ngày
      'used_minutes': 0,
    });
  });
  tearDown(() => f.dispose());

  test(
    'Employee sees leave balance, pending requests reduce what is left',
    () async {
      var b = (await employee.leaveBalances()).firstWhere(
        (r) => r['leave_type_id'] == annual,
      );
      expect(b['granted_minutes'], 960);
      expect(b['remaining_minutes'], 960);
      await request();
      b = (await employee.leaveBalances()).firstWhere(
        (r) => r['leave_type_id'] == annual,
      );
      expect(b['pending_minutes'], 480);
      expect(b['remaining_minutes'], 480);
    },
  );

  test('Submitting a request notifies reviewers; manager approves, balance is used and employee is told', () async {
    final id = await request();
    expect(
      (await manager.notifications()).any(
        (n) => n['title'] == 'Yêu cầu nghỉ phép mới',
      ),
      isTrue,
    );
    final listed = await manager.leaveRequestsForReview();
    expect(listed.first['id'], id);
    expect(listed.first['status'], 'pending');
    expect(listed.first['remaining_minutes'], 960);

    await manager.reviewLeaveRequest(id, true, note: 'OK');
    final row = (await f.db.query(
      'leave_requests',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    expect(row['status'], 'approved');
    expect(row['reviewed_by'], manager.session.userId);
    final balance = (await f.db.query(
      'leave_balances',
      where: 'leave_type_id=?',
      whereArgs: [annual],
    )).single;
    expect(balance['used_minutes'], 480);
    final toEmployee = (await employee.notifications()).firstWhere(
      (n) => n['title'] == 'Kết quả duyệt nghỉ phép',
    );
    expect(toEmployee['body'], contains('đã được duyệt'));
    // Không duyệt lại lần nữa.
    await expectLater(
      manager.reviewLeaveRequest(id, true),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Yêu cầu đã được xử lý.',
        ),
      ),
    );
  });

  test('Rejection needs a reason and leaves the balance untouched', () async {
    final id = await request();
    await expectLater(
      manager.reviewLeaveRequest(id, false),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Nhập lý do từ chối nghỉ phép.',
        ),
      ),
    );
    await manager.reviewLeaveRequest(id, false, note: 'Thiếu người');
    expect(
      (await f.db.query(
        'leave_requests',
        where: 'id=?',
        whereArgs: [id],
      )).single['status'],
      'rejected',
    );
    expect((await f.db.query('leave_balances')).single['used_minutes'], 0);
    expect(
      (await employee.notifications()).any(
        (n) => '${n['body']}'.contains('bị từ chối'),
      ),
      isTrue,
    );
  });

  test('Not enough days left, overlapping shift, self review and role limits are enforced', () async {
    // 3 ngày > 2 ngày được cấp.
    final big = await request(
      start: from,
      end: from.add(const Duration(days: 2, hours: 8)),
    );
    await expectLater(
      manager.reviewLeaveRequest(big, true),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Không đủ số ngày phép còn lại.',
        ),
      ),
    );
    expect((await f.db.query('leave_balances')).single['used_minutes'], 0);

    // Có ca làm trùng thời gian nghỉ => phải gỡ ca trước.
    final shift = await manager.createShift(
      branchId: employee.session.profile['branch_id'] as int,
      start: from.add(const Duration(days: 20)),
      end: from.add(const Duration(days: 20, hours: 4)),
    );
    await manager.assignShift(shift, employee.session.profile['id'] as int);
    final clash = await request(
      start: from.add(const Duration(days: 20)),
      end: from.add(const Duration(days: 20, hours: 8)),
    );
    await expectLater(
      manager.reviewLeaveRequest(clash, true),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('đang có ca'),
        ),
      ),
    );
    await manager.unassignShift(shift, employee.session.profile['id'] as int);
    await manager.reviewLeaveRequest(clash, true);

    // Nhân viên không có quyền xem/duyệt danh sách của quản lý.
    await expectLater(
      employee.leaveRequestsForReview(),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      employee.reviewLeaveRequest(big, false, note: 'x'),
      throwsA(isA<AuthException>()),
    );
    // Quản lý không tự duyệt yêu cầu của chính mình.
    await manager.createLeaveRequest(
      leaveTypeId: annual,
      start: from,
      end: to,
      reason: 'Tôi nghỉ',
    );
    final own =
        (await f.db.query(
              'leave_requests',
              orderBy: 'id DESC',
              limit: 1,
            )).single['id']
            as int;
    await expectLater(
      manager.reviewLeaveRequest(own, true),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Không thể tự duyệt nghỉ phép của mình.',
        ),
      ),
    );
    // Admin duyệt được yêu cầu của quản lý.
    await f.db.insert('leave_balances', {
      'employee_id': manager.session.profile['id'],
      'leave_type_id': annual,
      'year': year,
      'granted_minutes': 960,
      'used_minutes': 0,
    });
    await admin.reviewLeaveRequest(own, true);
    expect(
      (await f.db.query(
        'leave_requests',
        where: 'id=?',
        whereArgs: [own],
      )).single['status'],
      'approved',
    );
  });

  test('Invalid leave type and empty reason are rejected', () async {
    await expectLater(
      employee.createLeaveRequest(
        leaveTypeId: 99999,
        start: from,
        end: to,
        reason: 'x',
      ),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      employee.createLeaveRequest(
        leaveTypeId: annual,
        start: from,
        end: to,
        reason: '  ',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(await f.db.query('leave_requests'), isEmpty);
  });
}
