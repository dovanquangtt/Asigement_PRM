import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/login_screen.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';

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
  });
}
