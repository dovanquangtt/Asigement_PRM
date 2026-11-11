import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Trang chủ thiết kế lại cho từng vai trò: thẻ chào, số liệu, việc cần xử lý, lưới chức năng.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true, bundledData: true);
  });
  tearDown(() => f.dispose());

  Future<void> open(WidgetTester tester, String user, String pass) async {
    final session = (await tester.runAsync(() => f.auth.signIn(user, pass)))!;
    final repo = WorkforceRepository(session, openDatabase: () async => f.db);
    await tester.binding.setSurfaceSize(const Size(420, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(session: session, repository: repo),
      ),
    );
    for (var i = 0; i < 60 && find.text('Chức năng').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Chờ số liệu nền của trang chủ.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('…').evaluate().isEmpty &&
          find.text('Đang tải…').evaluate().isEmpty)
        break;
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  }

  testWidgets(
    'Employee home shows hero, next shift, leave, pay and the feature grid',
    (tester) async {
      await open(tester, 'employee', 'Employee@12345');
      expect(find.text('Chào Đỗ Văn Quang'), findsOneWidget);
      expect(find.text('NHÂN VIÊN'), findsOneWidget);
      expect(find.text('ĐQ'), findsOneWidget);
      expect(find.byKey(const Key('home-next-shift')), findsOneWidget);
      expect(find.text('CA LÀM SẮP TỚI'), findsOneWidget);
      expect(find.byKey(const Key('home-leave')), findsOneWidget);
      expect(find.text('Phép năm còn lại'), findsOneWidget);
      expect(find.byKey(const Key('home-pay')), findsOneWidget);
      for (final t in [
        'Đổi ca',
        'Lịch sử điểm danh',
        'Ảnh & báo cáo đóng ca',
        'Công của tôi & yêu cầu sửa công',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Cần xử lý'), findsNothing);
      // Chạm vào lưới mở đúng chức năng.
      await tester.tap(find.byKey(const Key('home-swaps')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ca có thể đổi'), findsWidgets);
      await close(tester);
    },
  );

  for (final who in [
    ('manager', 'Manager@12345', 'QUẢN LÝ'),
    ('admin', 'Admin@12345', 'ADMIN'),
  ]) {
    testWidgets('${who.$3} home shows counters and the to-do tiles', (
      tester,
    ) async {
      await open(tester, who.$1, who.$2);
      expect(find.text(who.$3), findsOneWidget);
      expect(find.text('Cần xử lý'), findsOneWidget);
      for (final k in [
        'todo-leave',
        'todo-attendance',
        'todo-closures',
        'todo-disputes',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('stat-employees')), findsOneWidget);
      expect(find.text('Nhân viên đang làm'), findsOneWidget);
      expect(find.text('Duyệt nghỉ phép'), findsOneWidget);
      expect(find.text('Dashboard thống kê'), findsOneWidget);
      // Số liệu đã tải xong (không còn dấu …).
      expect(find.text('…'), findsNothing);
      await tester.tap(find.byKey(const Key('todo-leave')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Duyệt nghỉ phép'), findsWidgets);
      await close(tester);
    });
  }
}
