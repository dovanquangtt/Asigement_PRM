import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Danh sách "Chức năng" ở Trang chủ phải khác nhau theo vai trò.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const manage = 'Lịch ca, phân ca & điểm danh';

  Future<void> openHome(
    WidgetTester tester,
    DatabaseFixture f,
    String user,
    String password,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late final WorkforceRepository repo;
    late final dynamic session;
    await tester.runAsync(() async {
      session = await f.auth.signIn(user, password);
      repo = WorkforceRepository(session, openDatabase: () async => f.db);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(session: session, repository: repo),
      ),
    );
    for (var i = 0; i < 40 && find.text('Chức năng').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Chức năng'), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    // Gỡ màn hình để hủy bộ đếm thông báo trước khi test kết thúc.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }

  late DatabaseFixture f;
  setUp(() async => f = await DatabaseFixture.open(keepSampleUsers: true));
  tearDown(() => f.dispose());

  testWidgets(
    'Employee does not get the shift management entry but keeps the rest',
    (tester) async {
      await openHome(tester, f, 'employee', 'Employee@12345');
      expect(find.text(manage), findsNothing);
      // Các chức năng của nhân viên vẫn còn.
      expect(find.text('Đổi ca'), findsOneWidget);
      expect(find.text('Lịch sử điểm danh'), findsOneWidget);
      expect(find.text('Ảnh & báo cáo đóng ca'), findsOneWidget);
      expect(find.text('Công của tôi & yêu cầu sửa công'), findsOneWidget);
      // Chức năng chỉ dành cho quản lý cũng không hiện.
      expect(find.text('Duyệt nghỉ phép'), findsNothing);
      expect(find.text('Dashboard thống kê'), findsNothing);
      // Nhân viên xem lịch ở tab "Lịch ca".
      expect(find.text('Lịch ca'), findsWidgets);
      await close(tester);
    },
  );

  for (final who in [('manager', 'Manager@12345'), ('admin', 'Admin@12345')]) {
    testWidgets('${who.$1} sees the shift management entry', (tester) async {
      await openHome(tester, f, who.$1, who.$2);
      expect(find.text(manage), findsOneWidget);
      expect(find.text('Duyệt nghỉ phép'), findsOneWidget);
      await close(tester);
    });
  }
}
