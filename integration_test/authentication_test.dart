import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quanlinhansunhahang/app.dart';
import 'package:quanlinhansunhahang/screens/login_screen.dart';

import 'package:quanlinhansunhahang/screens/workspace_screen.dart';
import 'package:quanlinhansunhahang/services/local_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android login rejects fake credentials against installed SQLite',
    (tester) async {
      await tester.pumpWidget(const PrmApp());
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      final db = await LocalDatabase.instance.database;
      expect(
        await db.query(
          'users',
          where: 'username = ?',
          whereArgs: ['fake_user_android_123'],
        ),
        isEmpty,
      );

      Future<void> submit(String name, String password) async {
        await tester.enterText(find.byType(TextFormField).at(0), name);
        await tester.enterText(find.byType(TextFormField).at(1), password);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        for (
          var attempt = 0;
          attempt < 100 && find.text('Đang kiểm tra…').evaluate().isNotEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      await submit('fake_user_android_123', 'random_password');
      expect(find.byType(Workspace), findsNothing);
      expect(
        find.text('Tên đăng nhập hoặc mật khẩu không đúng.'),
        findsOneWidget,
      );
      for (final account in [
        ('manager', 'Manager@12345', 'Quản lý'),
        ('employee', 'Employee@12345', 'Nhân viên'),
      ]) {
        await submit(account.$1, account.$2);
        expect(
          tester.widget<Workspace>(find.byType(Workspace)).session.role,
          account.$3,
        );
        expect(find.text('Tài khoản'), findsNothing);
        expect(find.text('Lịch ca'), findsOneWidget);
        expect(
          find.text('Nhân sự'),
          account.$3 == 'Quản lý' ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Lịch ca'));
        await tester.pumpAndSettle();
        final savedShifts = await tester
            .widget<Workspace>(find.byType(Workspace))
            .repository!
            .shifts();
        if (savedShifts.isEmpty) {
          expect(find.text('Chưa có phân ca được lưu.'), findsOneWidget);
        }
        await tester.tap(find.text('Cá nhân'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Đăng xuất'),
          300,
          scrollable: find.descendant(
            of: find.byType(Workspace),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.text('Đăng xuất'));
        await tester.pumpAndSettle();
      }
      await submit('admin', 'wrong_password');
      expect(find.byType(Workspace), findsNothing);
      expect(
        find.text('Tên đăng nhập hoặc mật khẩu không đúng.'),
        findsOneWidget,
      );
      await submit('admin', 'Admin@12345');
      expect(find.byType(Workspace), findsOneWidget);
      final session = tester.widget<Workspace>(find.byType(Workspace)).session;
      final users = await db.query(
        'users',
        where: 'username = ? AND is_active = 1',
        whereArgs: ['admin'],
      );
      expect(session.userId, users.single['id']);
      expect(session.role, 'Admin');
      expect(find.text('Tài khoản'), findsOneWidget);
      await tester.tap(find.text('Tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Tạo tài khoản'), findsOneWidget);
      await tester.tap(find.text('Cá nhân'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Đăng xuất'),
        300,
        scrollable: find.descendant(
          of: find.byType(Workspace),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      await submit('fake_user_android_123', 'random_password');
      expect(find.byType(Workspace), findsNothing);
    },
  );
}
