import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// M02 Bảng lương – quyền khác nhau giữa Quản lý (tạo/sửa/xóa/tính/duyệt/xử lý báo sai)
/// và Nhân viên (chỉ xem, tạm tính, báo sai).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager, quang;
  late int quangId;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    admin = await repo('admin', 'Admin@12345');
    manager = await repo('manager', 'Manager@12345');
    quang = await repo('employee', 'Employee@12345');
    quangId = quang.session.profile['id'] as int;
  });
  tearDown(() => f.dispose());

  Future<int> period([String code = 'T11']) => manager.createPeriod(
    code,
    DateTime.utc(2026, 11, 1),
    DateTime.utc(2026, 11, 30),
    1.5,
  );

  Future<int> draftSlip(int periodId) async {
    await manager.saveContract(
      quangId,
      'CT_$periodId',
      12480000,
      12480,
      DateTime.utc(2026, 1, 1),
    );
    await manager.calculatePay(periodId, employeeId: quangId);
    return (await f.db.query(
          'payslips',
          where: 'period_id=? AND employee_id=?',
          whereArgs: [periodId, quangId],
        )).single['id']
        as int;
  }

  Future<void> rejects(Future<Object?> call, [String? part]) => expectLater(
    call,
    throwsA(
      isA<AuthException>().having(
        (e) => e.message,
        'message',
        part == null ? isNotEmpty : contains(part),
      ),
    ),
  );

  test(
    'only managers can create, edit, delete and calculate periods',
    () async {
      await rejects(
        quang.createPeriod(
          'X',
          DateTime.utc(2026, 11, 1),
          DateTime.utc(2026, 11, 30),
          1.5,
        ),
      );
      final id = await period();
      await rejects(
        quang.updatePeriod(
          id,
          code: 'Y',
          start: DateTime.utc(2026, 11, 1),
          end: DateTime.utc(2026, 11, 30),
          multiplier: 1.5,
        ),
      );
      await rejects(quang.deletePeriod(id));
      await rejects(quang.calculatePay(id), 'Chỉ quản lý');
      await rejects(quang.periodPayslips(id));
      await rejects(quang.payrollDisputes());
      // Admin cũng quản lý được.
      await admin.updatePeriod(
        id,
        code: 'T11A',
        start: DateTime.utc(2026, 11, 1),
        end: DateTime.utc(2026, 11, 30),
        multiplier: 2,
        insuranceRateBp: 1050,
      );
      final row = (await f.db.rawQuery(
        'SELECT p.code,pol.overtime_multiplier m,pol.insurance_rate_bp b FROM payroll_periods p JOIN payroll_policies pol ON pol.period_id=p.id WHERE p.id=?',
        [id],
      )).single;
      expect(row['code'], 'T11A');
      expect(row['m'], 2);
      expect(row['b'], 1050);
    },
  );

  test('period validation and deleting only empty periods', () async {
    final id = await period();
    await rejects(
      manager.updatePeriod(
        id,
        code: ' ',
        start: DateTime.utc(2026, 11, 1),
        end: DateTime.utc(2026, 11, 30),
        multiplier: 1.5,
      ),
      'không hợp lệ',
    );
    await rejects(
      manager.updatePeriod(
        id,
        code: 'A',
        start: DateTime.utc(2026, 11, 30),
        end: DateTime.utc(2026, 11, 1),
        multiplier: 1.5,
      ),
      'không hợp lệ',
    );
    await rejects(
      manager.updatePeriod(
        id,
        code: 'A',
        start: DateTime.utc(2026, 11, 1),
        end: DateTime.utc(2026, 11, 30),
        multiplier: 0.5,
      ),
      'không hợp lệ',
    );
    await rejects(
      manager.createPeriod(
        'B',
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 11, 30),
        1.5,
        insuranceRateBp: 20000,
      ),
      'không hợp lệ',
    );
    final withSlip = await period('T12');
    await draftSlip(withSlip);
    await rejects(manager.deletePeriod(withSlip), 'đã có phiếu');
    await manager.deletePeriod(id);
    expect(
      await f.db.query('payroll_periods', where: 'id=?', whereArgs: [id]),
      isEmpty,
    );
    expect(
      await f.db.query(
        'payroll_policies',
        where: 'period_id=?',
        whereArgs: [id],
      ),
      isEmpty,
    );
    await rejects(manager.deletePeriod(id), 'Không tìm thấy');
  });

  test('calculatePay adds an automatic insurance item once and editing the period forces recalculation', () async {
    final id = await period();
    final slip = await draftSlip(id);
    var items = await f.db.query(
      'payslip_items',
      where: 'payslip_id=?',
      whereArgs: [slip],
    );
    expect(items.where((i) => i['item_type'] == 'insurance'), hasLength(1));
    await manager.calculatePay(id, employeeId: quangId);
    items = await f.db.query(
      'payslip_items',
      where: 'payslip_id=?',
      whereArgs: [slip],
    );
    expect(
      items.where((i) => i['item_type'] == 'insurance'),
      hasLength(1),
      reason: 'not duplicated',
    );
    expect(
      await f.db.query(
        'employee_payroll_checks',
        where: 'period_id=?',
        whereArgs: [id],
      ),
      hasLength(6),
    );
    await manager.updatePeriod(
      id,
      code: 'T11',
      start: DateTime.utc(2026, 11, 1),
      end: DateTime.utc(2026, 11, 30),
      multiplier: 1.5,
    );
    expect(
      await f.db.query(
        'employee_payroll_checks',
        where: 'period_id=?',
        whereArgs: [id],
      ),
      isEmpty,
    );
    expect(
      (await f.db.query(
        'payroll_periods',
        where: 'id=?',
        whereArgs: [id],
      )).single['status'],
      'draft',
    );
  });

  test(
    'items can be edited and removed while draft, never after approval',
    () async {
      final id = await period();
      final slip = await draftSlip(id);
      await manager.addPayItem(slip, 'BONUS', 'Thưởng', 'bonus', 10000);
      await manager.addPayItem(
        slip,
        'BONUS',
        'Thưởng chuyên cần',
        'bonus',
        20000,
      );
      var items = await f.db.query(
        'payslip_items',
        where: "payslip_id=? AND code='BONUS'",
        whereArgs: [slip],
      );
      expect(items, hasLength(1));
      expect(items.single['amount_vnd'], 20000);
      await rejects(quang.removePayItem(slip, 'BONUS'));
      await manager.removePayItem(slip, 'BONUS');
      items = await f.db.query(
        'payslip_items',
        where: "payslip_id=? AND code='BONUS'",
        whereArgs: [slip],
      );
      expect(items, isEmpty);
      await rejects(manager.removePayItem(slip, 'BONUS'), 'Không tìm thấy');
      await f.db.update(
        'payslips',
        {
          'status': 'approved',
          'approved_by': manager.session.userId,
          'approved_at': '2026-12-01 00:00:00',
        },
        where: 'id=?',
        whereArgs: [slip],
      );
      await rejects(manager.removePayItem(slip, 'BHXH'), 'đã chốt');
    },
  );

  test(
    'employee disputes reach managers and the answer reaches the employee',
    () async {
      final id = await period();
      final slip = await draftSlip(id);
      await f.db.update(
        'payslips',
        {
          'status': 'approved',
          'approved_by': manager.session.userId,
          'approved_at': '2026-12-01 00:00:00',
        },
        where: 'id=?',
        whereArgs: [slip],
      );
      final dispute = await quang.submitPayrollDispute(slip, {
        'overtime',
        'insurance',
      }, 'Thiếu giờ tăng ca');
      expect(
        (await manager.notifications()).any(
          (n) => n['title'] == 'Nhân viên báo sai lương',
        ),
        isTrue,
      );
      expect(
        (await admin.notifications()).any(
          (n) => n['title'] == 'Nhân viên báo sai lương',
        ),
        isTrue,
      );
      final pending = await manager.payrollDisputes(status: 'pending');
      expect(pending.single['full_name'], 'Đỗ Văn Quang');
      expect(pending.single['item_keys'], contains('overtime'));
      expect(await manager.payrollDisputes(status: 'resolved'), isEmpty);

      await rejects(
        manager.resolvePayrollDispute(dispute, accept: true, note: '  '),
        'phản hồi',
      );
      await rejects(
        quang.resolvePayrollDispute(dispute, accept: true, note: 'tự duyệt'),
      );
      await manager.resolvePayrollDispute(
        dispute,
        accept: false,
        note: 'Số liệu đúng theo bảng công',
      );
      final row = (await f.db.query(
        'payroll_disputes',
        where: 'id=?',
        whereArgs: [dispute],
      )).single;
      expect(row['status'], 'rejected');
      expect(row['resolved_by'], manager.session.userId);
      expect(row['resolution_note'], 'Số liệu đúng theo bảng công');
      expect(
        (await quang.notifications()).any(
          (n) =>
              n['title'] == 'Báo sai lương bị từ chối' &&
              '${n['body']}'.contains('bảng công'),
        ),
        isTrue,
      );
      await rejects(
        manager.resolvePayrollDispute(dispute, accept: true, note: 'đổi ý'),
        'đã được xử lý',
      );
      // Sau khi xử lý nhân viên được báo sai lại.
      final again = await quang.submitPayrollDispute(slip, {
        'base_salary',
      }, 'Sai lương cơ bản');
      await manager.resolvePayrollDispute(
        again,
        accept: true,
        note: 'Đã điều chỉnh',
      );
      expect(
        (await quang.notifications()).any(
          (n) => n['title'] == 'Báo sai lương đã được xử lý',
        ),
        isTrue,
      );
    },
  );

  test('employees never see draft payslips in lists', () async {
    final id = await period();
    final slip = await draftSlip(id);
    expect(await quang.payslips(), isEmpty);
    expect(await quang.myPayrolls(), isEmpty);
    expect(await manager.payslips(), isNotEmpty);
    await f.db.update(
      'payslips',
      {
        'status': 'approved',
        'approved_by': manager.session.userId,
        'approved_at': '2026-12-01 00:00:00',
      },
      where: 'id=?',
      whereArgs: [slip],
    );
    expect(await quang.payslips(), hasLength(1));
    expect(await quang.myPayrolls(), hasLength(1));
  });
}
