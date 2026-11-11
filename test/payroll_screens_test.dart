import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/payroll/my_payroll_screen.dart';
import 'package:quanlinhansunhahang/screens/payroll/payroll_detail_screen.dart';
import 'package:quanlinhansunhahang/screens/payroll/payroll_disputes_screen.dart';
import 'package:quanlinhansunhahang/screens/payroll/payroll_estimate_screen.dart';
import 'package:quanlinhansunhahang/screens/payroll/payroll_verify_screen.dart';
import 'package:quanlinhansunhahang/services/payslip_pdf.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';
import 'package:quanlinhansunhahang/widgets/money.dart';

import 'database_fixture.dart';

/// 4 màn Bảng lương của nhân viên (danh sách, tạm tính, kiểm tra 6 khoản, chi tiết/PDF)
/// và màn xử lý báo sai của quản lý.
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

  /// Phiếu đã trả: 6.000.000 + 300.000 + phụ cấp 500.000 + thưởng 200.000 − bảo hiểm 480.000 − phạt 50.000.
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
    final existing = await f.db.query(
      'contracts',
      where: 'employee_id=?',
      whereArgs: [quangId],
    );
    final contract = existing.isNotEmpty
        ? existing.first['id'] as int
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

  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 60 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  }

  Future<void> tall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  test('money formatting follows Vietnamese style', () {
    expect(formatVnd(7657000), '7.657.000đ');
    expect(formatVnd(0), '0đ');
    expect(formatVnd(-50000), '-50.000đ');
    expect(formatVnd(null), '0đ');
    expect(formatMinutes(125), '2 giờ 05 phút');
    expect(formatDay('2026-09-01'), '01/09/2026');
  });

  testWidgets('Screen 1 lists approved payslips by year with totals', (
    tester,
  ) async {
    await tall(tester);
    await tester.runAsync(() async {
      await paidSlip();
      await paidSlip(code: 'T10', start: '2026-10-01');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MyPayrollScreen(repository: quang)),
      ),
    );
    await settle(tester, find.byKey(const Key('latest-card')));
    expect(find.text('Bảng lương của tôi'), findsOneWidget);
    expect(find.text('Năm 2026'), findsOneWidget);
    // Thực lĩnh mỗi phiếu: 6.470.000đ.
    expect(find.text('6.470.000đ'), findsWidgets);
    expect(
      find.text('Tổng thực lĩnh năm 2026: 12.940.000đ (2 kỳ)'),
      findsOneWidget,
    );
    expect(find.text('Kỳ T10'), findsOneWidget);
    expect(find.text('Kỳ T09'), findsOneWidget);
    // Nhân viên chỉ xem: không có nút tạo/sửa/tính.
    expect(find.text('Tạo kỳ lương'), findsNothing);
    expect(find.textContaining('Tính lương'), findsNothing);
    await close(tester);
  });

  testWidgets('Screen 1 shows an empty state when nothing is approved yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MyPayrollScreen(repository: quang)),
      ),
    );
    await settle(
      tester,
      find.textContaining('Chưa có phiếu lương nào được duyệt'),
    );
    expect(
      find.textContaining('Chưa có phiếu lương nào được duyệt'),
      findsOneWidget,
    );
    final verify = tester.widget<OutlinedButton>(
      find.byKey(const Key('open-verify')),
    );
    expect(verify.onPressed, isNull);
    await close(tester);
  });

  testWidgets('Screen 1 uses the dark teal palette when the system is dark', (
    tester,
  ) async {
    await tall(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.runAsync(paidSlip);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MyPayrollScreen(repository: quang)),
      ),
    );
    await settle(tester, find.byKey(const Key('latest-card')));
    final card = tester.widget<Container>(find.byKey(const Key('latest-card')));
    expect((card.decoration! as BoxDecoration).color, const Color(0xFF2DD4BF));
    await close(tester);
  });

  testWidgets(
    'Screen 1 opens detail from a card and the estimate from the button',
    (tester) async {
      await tall(tester);
      final slip = (await tester.runAsync(paidSlip))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MyPayrollScreen(repository: quang)),
        ),
      );
      await settle(tester, find.byKey(Key('payslip-$slip')));
      await tester.tap(find.byKey(Key('payslip-$slip')));
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, find.byKey(const Key('detail-net')));
      expect(find.text('6.470.000đ'), findsWidgets);
      expect(find.text('Phụ cấp ăn'), findsOneWidget);
      expect(find.text('-480.000đ'), findsOneWidget);
      expect(find.byKey(const Key('export-pdf')), findsOneWidget);
      expect(find.byKey(const Key('print-pdf')), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-estimate')));
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, find.text('Chưa có kỳ lương'));
      expect(find.text('Chưa có kỳ lương'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('Screen 2 estimates the current period read-only', (
    tester,
  ) async {
    await tall(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await manager.createPeriod(
        'NOW',
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0),
        1.5,
      );
      await manager.saveContract(
        quangId,
        'CT_NOW',
        12480000,
        12480,
        DateTime(now.year - 1),
      );
    });
    final before = (await tester.runAsync(() => f.db.query('payslips')))!
        .length;
    await tester.pumpWidget(
      MaterialApp(home: PayrollEstimateScreen(repository: quang)),
    );
    await settle(tester, find.byKey(const Key('estimate-net')));
    expect(find.text('0đ'), findsWidgets);
    expect(
      find.textContaining('chưa phải phiếu lương chính thức'),
      findsOneWidget,
    );
    expect(find.textContaining('Ước tính 8.0% lương cơ bản'), findsOneWidget);
    final after = (await tester.runAsync(() => f.db.query('payslips')))!.length;
    expect(after, before, reason: 'estimating never writes payslips');
    await close(tester);
  });

  testWidgets('Screen 2 explains a missing contract', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      await f.db.delete(
        'contracts',
        where: 'employee_id=?',
        whereArgs: [quangId],
      );
      await manager.createPeriod(
        'NOW',
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0),
        1.5,
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: PayrollEstimateScreen(repository: quang)),
    );
    await settle(tester, find.text('Chưa có hợp đồng'));
    expect(find.text('Chưa có hợp đồng'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'Screen 3 checks 6 items and sends a dispute that managers can resolve',
    (tester) async {
      await tall(tester);
      final slip = (await tester.runAsync(paidSlip))!;
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollVerifyScreen(repository: quang, payslipId: slip),
        ),
      );
      await settle(tester, find.byKey(const Key('flag-base_salary')));
      for (final label in [
        'Lương cơ bản',
        'Tăng ca',
        'Phụ cấp',
        'Thưởng',
        'Bảo hiểm',
        'Khấu trừ khác',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Tổng các khoản khớp với thực lĩnh.'), findsOneWidget);
      // Chưa chọn khoản nào: báo lỗi.
      await tester.tap(find.byKey(const Key('send-dispute')));
      await settle(tester, find.text('Chọn ít nhất một khoản bị sai.'));
      expect(find.text('Chọn ít nhất một khoản bị sai.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flag-overtime')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-dispute')));
      await settle(tester, find.text('Nhập mô tả khoản bị sai.'));
      expect(find.text('Nhập mô tả khoản bị sai.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('dispute-message')),
        'Thiếu 2 giờ tăng ca',
      );
      await tester.tap(find.byKey(const Key('send-dispute')));
      await settle(tester, find.byKey(const Key('pending-note')));
      expect(find.byKey(const Key('pending-note')), findsOneWidget);
      expect(find.text('Chờ xử lý'), findsOneWidget);
      final rows = (await tester.runAsync(
        () => f.db.query('payroll_disputes'),
      ))!;
      expect(rows.single['message'], 'Thiếu 2 giờ tăng ca');
      await close(tester);

      // Quản lý xử lý.
      await tester.pumpWidget(
        MaterialApp(home: PayrollDisputesScreen(repository: manager)),
      );
      await settle(
        tester,
        find.byKey(Key('dispute-resolve-${rows.single['id']}')),
      );
      expect(find.text('Chờ xử lý (1)'), findsOneWidget);
      await tester.tap(find.byKey(Key('dispute-reject-${rows.single['id']}')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('review-confirm')));
      await tester.pump();
      expect(find.text('Nhập lý do từ chối'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('review-note')),
        'Công đã đủ',
      );
      await tester.tap(find.byKey(const Key('review-confirm')));
      await settle(tester, find.text('Đã từ chối báo sai.'));
      expect(find.text('Đã từ chối báo sai.'), findsOneWidget);
      final done = (await tester.runAsync(
        () => f.db.query('payroll_disputes'),
      ))!.single;
      expect(done['status'], 'rejected');
      expect(done['resolution_note'], 'Công đã đủ');
      await close(tester);
    },
  );

  testWidgets('Screen 3 locks sending while a dispute is pending', (
    tester,
  ) async {
    await tall(tester);
    final slip = (await tester.runAsync(paidSlip))!;
    await tester.runAsync(
      () => quang.submitPayrollDispute(slip, {'bonus'}, 'Thiếu thưởng'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PayrollVerifyScreen(repository: quang, payslipId: slip),
      ),
    );
    await settle(tester, find.byKey(const Key('pending-note')));
    expect(find.byKey(const Key('send-dispute')), findsNothing);
    expect(find.text('Lịch sử báo sai'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Screen 4 shows every item and links to the dispute screen', (
    tester,
  ) async {
    await tall(tester);
    final slip = (await tester.runAsync(paidSlip))!;
    await tester.pumpWidget(
      MaterialApp(
        home: PayrollDetailScreen(repository: quang, payslipId: slip),
      ),
    );
    await settle(tester, find.byKey(const Key('detail-net')));
    for (final t in ['Phụ cấp ăn', 'Thưởng', 'Bảo hiểm', 'Phạt đi trễ']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Tổng thu nhập'), findsOneWidget);
    expect(find.text('Tổng khấu trừ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-verify')));
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester, find.byKey(const Key('flag-base_salary')));
    expect(find.byKey(const Key('flag-base_salary')), findsOneWidget);
    await close(tester);
  });

  test('PDF payslip is generated with embedded Vietnamese fonts', () async {
    final slip = await paidSlip();
    final data = await quang.payrollBreakdown(slip);
    final bytes = await buildPayslipPdf(data);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000), reason: 'fonts are embedded');
  });
}
