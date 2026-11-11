import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Tài khoản do Admin tạo phải mở được mọi chức năng như tài khoản mẫu Đỗ Văn Quang,
/// không màn nào báo lỗi tải dữ liệu hay "chưa liên kết hồ sơ".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    admin = await repo('admin', 'Admin@12345');
    manager = await repo('manager', 'Manager@12345');
  });
  tearDown(() => f.dispose());

  Future<void> settle(WidgetTester tester, [Finder? until]) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (until != null && until.evaluate().isNotEmpty) break;
      if (until == null && i >= 6) break;
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  }

  void expectHealthy() {
    for (final bad in [
      'Không tải được',
      'chưa được liên kết',
      'Không có quyền',
      'Lỗi',
    ]) {
      expect(find.textContaining(bad), findsNothing, reason: bad);
    }
  }

  testWidgets('A new employee opens every employee feature without errors', (
    tester,
  ) async {
    final mai = (await tester.runAsync(() async {
      await admin.createUser(
        username: 'mai',
        password: 'Mai@123456',
        role: 'employee',
        fullName: 'Lê Thị Mai',
      );
      return repo('mai', 'Mai@123456');
    }))!;
    await tester.binding.setSurfaceSize(const Size(420, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(session: mai.session, repository: mai),
      ),
    );
    await settle(tester, find.text('Chức năng'));
    for (final feature in [
      'Đổi ca',
      'Ảnh & báo cáo đóng ca',
      'Lịch sử điểm danh',
      'Công của tôi & yêu cầu sửa công',
    ]) {
      await tester.tap(find.text(feature));
      await tester.pump();
      await settle(tester);
      expectHealthy();
      expect(tester.takeException(), isNull, reason: feature);
      expect(find.byTooltip('Back'), findsOneWidget, reason: feature);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 600));
      for (
        var i = 0;
        i < 30 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 600));
    }
    for (final tab in ['Lịch ca', 'Thu nhập', 'Cá nhân']) {
      final target = find.text(tab);
      if (target.evaluate().isEmpty) continue;
      await tester.tap(target.last);
      await tester.pump();
      await settle(tester);
      expectHealthy();
      expect(tester.takeException(), isNull, reason: tab);
      if (tab == 'Thu nhập') {
        expect(find.text('Bảng lương của tôi'), findsOneWidget);
        expect(find.text('Lương tạm tính'), findsOneWidget);
      }
    }
    await close(tester);
  });

  testWidgets(
    'Closures screen of a new employee explains there is nothing to close yet',
    (tester) async {
      final mai = (await tester.runAsync(() async {
        await admin.createUser(
          username: 'mai',
          password: 'Mai@123456',
          role: 'employee',
          fullName: 'Lê Thị Mai',
        );
        return repo('mai', 'Mai@123456');
      }))!;
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(session: mai.session, repository: mai),
        ),
      );
      await settle(tester, find.text('Chức năng'));
      await tester.tap(find.text('Ảnh & báo cáo đóng ca'));
      await tester.pump();
      await settle(tester, find.textContaining('Không có ca nào cần đóng'));
      expect(find.textContaining('Không có ca nào cần đóng'), findsOneWidget);
      expect(find.text('Lịch sử đóng ca'), findsOneWidget);
      await close(tester);
      expect(manager, isNotNull);
    },
  );
}
