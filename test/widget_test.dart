import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/app.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';

void main() {
  testWidgets('Pixel: login, navigation and attendance flow', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const PrmApp());
    await tester.ensureVisible(find.text('Vào không gian làm việc →'));
    await tester.tap(find.text('Vào không gian làm việc →'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên đăng nhập'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'linh');
    await tester.enterText(find.byType(TextFormField).at(1), 'demo');
    await tester.ensureVisible(find.text('Vào không gian làm việc →'));
    await tester.tap(find.text('Vào không gian làm việc →'));
    await tester.pumpAndSettle();
    expect(find.text('Chào Linh'), findsOneWidget);

    await tester.tap(find.text('Điểm danh vào ca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Điểm danh ra ca'), findsOneWidget);
    await tester.tap(find.text('Điểm danh ra ca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Đã kết thúc ca'), findsOneWidget);
    await tester.tap(find.text('Lịch ca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CN'));
    await tester.pumpAndSettle();
    expect(find.text('Hôm nay bạn được nghỉ'), findsOneWidget);
    await tester.tap(find.text('Thu nhập'));
    await tester.pumpAndSettle();
    expect(find.text('10.600.000 ₫'), findsNWidgets(2));
    await tester.tap(find.text('Cá nhân'));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Linh'), findsOneWidget);
  });
  testWidgets('Compact phone has no layout overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: Workspace(role: 'Admin')));
    await tester.pumpAndSettle();
    for (final label in ['Lịch ca', 'Thu nhập', 'Cá nhân', 'Trang chủ']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
  });
}
