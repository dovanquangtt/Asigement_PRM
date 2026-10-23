import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/login_screen.dart';
import 'package:quanlinhansunhahang/screens/payroll_screen.dart';
import 'package:quanlinhansunhahang/screens/payroll_checks_screen.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  testWidgets('Login checks real SQLite before navigation', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = (await tester.runAsync(DatabaseFixture.open))!;
    addTearDown(fixture.dispose);
    final id = await tester.runAsync(() => fixture.addUser());
    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: fixture.auth)));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.ensureVisible(find.text('Vào không gian làm việc →'));
    await tester.tap(find.text('Vào không gian làm việc →'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên đăng nhập'), findsOneWidget);

    Future<void> submit(String name, String password) async {
      await tester.enterText(find.byType(TextFormField).at(0), name);
      await tester.enterText(find.byType(TextFormField).at(1), password);
      await tester.ensureVisible(find.text('Vào không gian làm việc →'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Vào không gian làm việc →'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.runAsync(() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
    }

    await submit('fake_user', 'TestPass123!');
    expect(find.byType(Workspace), findsNothing);
    expect(
      find.text('Tên đăng nhập hoặc mật khẩu không đúng.'),
      findsOneWidget,
    );
    await submit('linh', 'wrong');
    expect(find.byType(Workspace), findsNothing);
    await submit('linh', 'TestPass123!');
    expect(find.byType(Workspace), findsOneWidget);
    final workspace = tester.widget<Workspace>(find.byType(Workspace));
    expect(workspace.session.userId, id);
    expect(workspace.session.role, 'Nhân viên');
    expect(find.text('Chào linh'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Cập nhật'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Chào linh'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Cá nhân').last);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đăng xuất'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Đăng xuất'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(Workspace), findsNothing);
    expect(
      tester
          .element(find.byType(LoginPage))
          .findAncestorStateOfType<NavigatorState>()!
          .canPop(),
      isFalse,
    );
  });

  testWidgets('Employee payroll filters real slips and opens a selected slip', (
    tester,
  ) async {
    int? openedId;
    var calculateOpened = false;
    final slips = <RowData>[
      {
        'id': 1,
        'period_code': 'OCT_DRAFT',
        'starts_on': '2026-10-01',
        'ends_on': '2026-10-31',
        'status': 'draft',
        'net_pay_vnd': 10600000,
        'gross_pay_vnd': 10700000,
        'deductions_vnd': 100000,
      },
      {
        'id': 2,
        'period_code': 'SEP_PAID',
        'starts_on': '2026-09-01',
        'ends_on': '2026-09-30',
        'status': 'paid',
        'net_pay_vnd': 10200000,
        'gross_pay_vnd': 10300000,
        'deductions_vnd': 100000,
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmployeePayrollScreen(
            payslips: slips,
            onRefresh: () async {},
            onCheckPayroll: () => calculateOpened = true,
            onOpen: (row) => openedId = row['id'] as int,
          ),
        ),
      ),
    );

    expect(find.text('Bảng lương của tôi'), findsOneWidget);
    expect(find.text('Kiểm tra 6 thao tác tính lương'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Bản nháp'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Tất cả'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Đã duyệt'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Đã thanh toán'), findsOneWidget);

    await tester.tap(find.text('Kiểm tra 6 thao tác tính lương'));
    expect(calculateOpened, isTrue);
    await tester.dragUntilVisible(
      find.text('Phiếu #1'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phiếu #1'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Mở chi tiết bảng lương'),
      find.byType(ListView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mở chi tiết bảng lương'));
    expect(openedId, 1);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Đã thanh toán'));
    await tester.pumpAndSettle();
    expect(find.text('Phiếu #1'), findsNothing);
    await tester.dragUntilVisible(
      find.text('Phiếu #2'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.ensureVisible(find.text('Phiếu #2'));
    await tester.pumpAndSettle();
    expect(find.text('Phiếu #2'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Xem chi tiết bảng lương'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem chi tiết bảng lương'));
    expect(openedId, 2);
  });

  testWidgets('Payroll checks have a separate six-row statistics table', (
    tester,
  ) async {
    final checks = [
      for (var step = 1; step <= 6; step++)
        <String, Object?>{
          'step_number': step,
          'name': 'Bước kiểm tra $step',
          'detail': 'Kết quả bước $step',
        },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: PayrollChecksScreen(
          payslip: {
            'id': 7,
            'full_name': 'Nguyễn An',
            'period_code': 'OCT_2026',
          },
          checks: checks,
          checksCurrent: true,
        ),
      ),
    );

    expect(find.text('Kiểm tra 6 bước tính lương'), findsOneWidget);
    expect(find.text('Đã hoàn thành 6/6 bước'), findsOneWidget);
    expect(find.text('Bảng thống kê các bước'), findsOneWidget);
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(6));
    for (var step = 1; step <= 6; step++) {
      expect(find.text('Bước kiểm tra $step'), findsOneWidget);
      expect(find.text('Kết quả bước $step'), findsOneWidget);
    }
    expect(find.text('Đạt'), findsNWidgets(6));
  });
}
