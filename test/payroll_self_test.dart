import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// M02 Bảng lương (Nhân viên): phiếu đã chốt, lương tạm tính chỉ đọc, chi tiết và báo sai.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository manager, quang;
  late int quangId;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    manager = await repo('manager', 'Manager@12345');
    quang = await repo('employee', 'Employee@12345');
    quangId = quang.session.profile['id'] as int;
  });
  tearDown(() => f.dispose());

  Future<int> newStranger() async =>
      (await repo('admin', 'Admin@12345')).createUser(
        username: 'khac',
        password: 'Khac@12345',
        role: 'employee',
        fullName: 'Khac Nhan Vien',
      );

  /// Kỳ đã chốt kèm phiếu có đủ các loại khoản, ghi thẳng vào DB.
  Future<int> paidSlip({
    String code = 'T09',
    String start = '2026-09-01',
  }) async {
    final period = await f.db.insert('payroll_periods', {
      'code': code,
      'starts_on': start,
      'ends_on': '${start.substring(0, 8)}28',
      'status': 'paid',
    });
    await f.db.insert('payroll_policies', {
      'period_id': period,
      'overtime_multiplier': 1.5,
      'created_by': manager.session.userId,
    });
    final contracts = await f.db.query(
      'contracts',
      where: 'employee_id=?',
      whereArgs: [quangId],
    );
    final contract = contracts.isNotEmpty
        ? contracts.first['id'] as int
        : await f.db.insert('contracts', {
            'employee_id': quangId,
            'contract_number': 'HD-$code',
            'contract_type': 'indefinite',
            'start_date': '2026-01-01',
            'salary_basis': 'monthly',
            'base_salary_vnd': 12480000,
            'standard_minutes_per_month': 12480,
            'status': 'active',
          });
    final slip = await f.db.insert('payslips', {
      'period_id': period,
      'employee_id': quangId,
      'contract_id': contract,
      'regular_minutes': 6000,
      'overtime_minutes': 120,
      'base_pay_vnd': 6000000,
      'overtime_pay_vnd': 300000,
      'status': 'paid',
      'approved_by': manager.session.userId,
      'approved_at': '2026-10-01 00:00:00',
      'paid_at': '2026-10-02 00:00:00',
    });
    for (final i in [
      ('MEAL', 'Phụ cấp ăn', 'allowance', 500000),
      ('BONUS', 'Thưởng', 'bonus', 200000),
      ('BHXH', 'Bảo hiểm', 'insurance', 480000),
      ('LATE', 'Phạt đi trễ', 'deduction', 50000),
    ]) {
      await f.db.insert('payslip_items', {
        'payslip_id': slip,
        'code': i.$1,
        'name': i.$2,
        'item_type': i.$3,
        'amount_vnd': i.$4,
      });
    }
    return slip;
  }

  test('PayAmounts uses integer VND arithmetic with half-up rounding', () {
    final monthly = {
      'salary_basis': 'monthly',
      'base_salary_vnd': 12480000,
      'standard_minutes_per_month': 12480,
    };
    final a = PayAmounts.of(
      contract: monthly,
      regularMinutes: 6000,
      overtimeMinutes: 120,
      overtimeMultiplier: 1.5,
    );
    expect(a.base, 6000000);
    expect(a.overtime, 180000);
    final hourly = {'salary_basis': 'hourly', 'hourly_rate_vnd': 30000};
    final b = PayAmounts.of(
      contract: hourly,
      regularMinutes: 90,
      overtimeMinutes: 30,
      overtimeMultiplier: 2,
    );
    expect(b.base, 45000);
    expect(b.overtime, 30000);
    // 1 phút × 12.345.678 / 12480 = 989,2… → làm tròn 989
    expect(
      PayAmounts.of(
        contract: {...monthly, 'base_salary_vnd': 12345678},
        regularMinutes: 1,
        overtimeMinutes: 0,
        overtimeMultiplier: 1.5,
      ).base,
      989,
    );
  });

  test(
    'myPayrolls lists only my approved or paid payslips, filtered by year',
    () async {
      final slip = await paidSlip();
      final other = await newStranger();
      await f.db.insert('payslips', {
        'period_id': (await f.db.query(
          'payslips',
          where: 'id=?',
          whereArgs: [slip],
        )).single['period_id'],
        'employee_id': other,
        'contract_id': (await f.db.query(
          'payslips',
          where: 'id=?',
          whereArgs: [slip],
        )).single['contract_id'],
        'status': 'paid',
        'approved_by': manager.session.userId,
        'approved_at': '2026-10-01 00:00:00',
        'paid_at': '2026-10-02 00:00:00',
      });
      final rows = await quang.myPayrolls();
      expect(rows, hasLength(1));
      expect(rows.single['id'], slip);
      expect(rows.single['allowance_vnd'], 500000);
      expect(rows.single['bonus_vnd'], 200000);
      // 6.000.000 + 300.000 + 500.000 + 200.000 − (480.000 + 50.000)
      expect(rows.single['net_pay_vnd'], 6470000);
      expect(await quang.payrollYears(), [2026]);
      expect(await quang.myPayrolls(year: 2025), isEmpty);
      expect(await quang.myPayrolls(year: 2026), hasLength(1));
      // Phiếu nháp chưa chốt thì không hiện.
      await f.db.update(
        'payslips',
        {'status': 'draft'},
        where: 'id=?',
        whereArgs: [slip],
      );
      expect(await quang.myPayrolls(), isEmpty);
    },
  );

  test(
    'payrollBreakdown groups items and refuses other people payslips',
    () async {
      final slip = await paidSlip();
      final d = await quang.payrollBreakdown(slip);
      expect(d['allowance_vnd'], 500000);
      expect(d['bonus_vnd'], 200000);
      expect(d['insurance_vnd'], 480000);
      expect(d['other_deduction_vnd'], 50000);
      expect(d['net_pay_vnd'], 6470000);
      expect(d['pending_dispute'], isFalse);
      final other = await repo('admin', 'Admin@12345');
      // Admin xem được qua quyền quản lý, còn nhân viên khác thì không.
      expect((await other.payslipDetail(slip))['id'], slip);
      await newStranger();
      final stranger = await repo('khac', 'Khac@12345');
      await expectLater(
        stranger.payrollBreakdown(slip),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'submitPayrollDispute validates, stores items and blocks duplicates',
    () async {
      final slip = await paidSlip();
      Future<void> rejects(Future<int> call, String part) => expectLater(
        call,
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains(part),
          ),
        ),
      );
      await rejects(
        quang.submitPayrollDispute(slip, {}, 'Sai'),
        'ít nhất một khoản',
      );
      await rejects(
        quang.submitPayrollDispute(slip, {'nope'}, 'Sai'),
        'ít nhất một khoản',
      );
      await rejects(
        quang.submitPayrollDispute(slip, {'overtime'}, '  '),
        'mô tả',
      );
      final id = await quang.submitPayrollDispute(slip, {
        'overtime',
        'bonus',
      }, ' Thiếu 2 giờ tăng ca ');
      final row = (await f.db.query(
        'payroll_disputes',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(row['status'], 'pending');
      expect(row['message'], 'Thiếu 2 giờ tăng ca');
      expect(row['employee_id'], quangId);
      expect(
        (await f.db.query(
          'payroll_dispute_items',
          where: 'dispute_id=?',
          whereArgs: [id],
        )).map((r) => r['item_key']).toSet(),
        {'overtime', 'bonus'},
      );
      await rejects(
        quang.submitPayrollDispute(slip, {'base_salary'}, 'Sai lương'),
        'đang chờ xử lý',
      );
      expect((await quang.payrollBreakdown(slip))['pending_dispute'], isTrue);
      expect((await quang.myPayrolls()).single['pending_disputes'], 1);
      // Báo sai xong được xử lý thì báo lại được.
      await f.db.update(
        'payroll_disputes',
        {'status': 'resolved'},
        where: 'id=?',
        whereArgs: [id],
      );
      await quang.submitPayrollDispute(slip, {'base_salary'}, 'Sai lương');
      // Không báo sai được phiếu nháp hoặc phiếu của người khác.
      await f.db.update(
        'payslips',
        {'status': 'draft'},
        where: 'id=?',
        whereArgs: [slip],
      );
      await f.db.update('payroll_disputes', {'status': 'rejected'});
      await rejects(
        quang.submitPayrollDispute(slip, {'bonus'}, 'x'),
        'đã chốt',
      );
      await newStranger();
      final stranger = await repo('khac', 'Khac@12345');
      await f.db.update(
        'payslips',
        {'status': 'paid'},
        where: 'id=?',
        whereArgs: [slip],
      );
      await rejects(
        stranger.submitPayrollDispute(slip, {'bonus'}, 'x'),
        'Không có quyền',
      );
    },
  );

  test(
    'estimatePay is read only and handles missing period or contract',
    () async {
      expect((await quang.estimatePay())['has_period'], isFalse);
      final now = DateTime.now();
      final period = await manager.createPeriod(
        'NOW',
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0),
        1.5,
      );
      final before = (await f.db.query('payslips')).length;
      var e = await quang.estimatePay();
      if (e['has_contract'] == false) {
        await manager.saveContract(
          quangId,
          'CT_NOW',
          12480000,
          12480,
          DateTime(now.year - 1),
        );
        e = await quang.estimatePay();
      }
      expect(e['has_contract'], isTrue);
      expect((e['period'] as Map)['id'], period);
      expect(e['regular_minutes'], 0);
      expect(e['base_pay_vnd'], 0);
      expect(e['net_vnd'], 0);
      expect(e['insurance_estimated'], isTrue);
      expect(
        (await f.db.query('payslips')).length,
        before,
        reason: 'estimate must not write payslips',
      );
      expect(await f.db.query('employee_payroll_checks'), isEmpty);
    },
  );

  test(
    'migration 8 adds dispute tables and a default insurance rate of 8%',
    () async {
      final policy = await f.db.rawQuery('PRAGMA table_info(payroll_policies)');
      final col = policy.firstWhere((c) => c['name'] == 'insurance_rate_bp');
      expect(col['dflt_value'], '800');
      expect(
        (await f.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name IN ('payroll_disputes','payroll_dispute_items')",
        )),
        hasLength(2),
      );
    },
  );
}
