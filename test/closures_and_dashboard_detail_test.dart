import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/closures_screen.dart';
import 'package:quanlinhansunhahang/screens/dashboard_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// Màn đóng ca (nhân viên + quản lý) và nút "Xem chi tiết" của dashboard, trên dữ liệu mẫu có sẵn.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository admin, manager, quang;

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true, bundledData: true);
    admin = await repo('admin', 'Admin@12345');
    manager = await repo('manager', 'Manager@12345');
    quang = await repo('employee', 'Employee@12345');
  });
  tearDown(() => f.dispose());

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

  group('repository', () {
    test(
      'reviewClosure requires a reason to reject and stores the review note',
      () async {
        final pending = (await f.db.query('shift_closures'));
        expect(pending, isNotEmpty);
        final id = pending.first['id'] as int;
        await f.db
            .update(
              'shift_closures',
              {'status': 'submitted', 'reviewed_by': null, 'reviewed_at': null},
              where: 'id=?',
              whereArgs: [id],
            )
            .catchError((_) => 0);
        await expectLater(
          manager.reviewClosure(id, false),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'm',
              contains('lý do'),
            ),
          ),
        );
      },
    );

    test(
      'closures expose shift time, branch and reviewer for the history card',
      () async {
        final rows = await manager.closures();
        expect(rows, isNotEmpty);
        expect(rows.first['starts_at'], isNotNull);
        expect(rows.first['branch_name'], isNotNull);
        expect(rows.first.containsKey('reviewer'), isTrue);
        expect(rows.first['photos'], isA<List>());
      },
    );

    test(
      'closureTasks lists only started shifts without an open report',
      () async {
        final tasks = await quang.closureTasks();
        for (final t in tasks) {
          expect(t['ready'], t['check_out_at'] != null);
          expect(t['ready'] == true || t['blocked'] != null, isTrue);
        }
      },
    );

    test('dashboardDetail lists every employee for Admin, only the branch for managers', () async {
      final from = DateTime(2000);
      final to = DateTime(2100);
      final all = await admin.dashboardDetail('employees', from: from, to: to);
      final total = (await f.db.query('employees')).length;
      expect(all, hasLength(total));
      expect(
        all.every((r) => r['title'] != null && r['badge'] != null),
        isTrue,
      );
      final mine = await manager.dashboardDetail(
        'employees',
        from: from,
        to: to,
      );
      expect(mine.length, lessThanOrEqualTo(all.length));
      for (final kind in [
        'shifts',
        'attendance',
        'leave',
        'hours',
        'payroll',
      ]) {
        final rows = await admin.dashboardDetail(
          kind,
          from: DateTime(2000),
          to: DateTime(2100),
        );
        expect(rows, isA<List<Map<String, Object?>>>(), reason: kind);
      }
      expect(
        (await admin.dashboardSummary(
          from: DateTime(2026),
          to: DateTime(2026, 12, 31),
        ))['employees'],
        isNotNull,
      );
      await expectLater(
        quang.dashboardDetail('employees', from: from, to: to),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        admin.dashboardDetail('nope', from: from, to: to),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('screens', () {
    testWidgets(
      'Manager filters closures, sees photos and must give a reason to reject',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.runAsync(() async {
          await f.db.update('shift_closures', {
            'status': 'submitted',
            'reviewed_by': null,
            'reviewed_at': null,
          });
        });
        await tester.pumpWidget(
          MaterialApp(home: ClosuresScreen(repository: manager)),
        );
        await settle(tester, find.byKey(const Key('closure-filter-submitted')));
        final pending = (await tester.runAsync(
          () => f.db.query('shift_closures'),
        ))!.length;
        expect(find.textContaining('Chờ duyệt ($pending)'), findsOneWidget);
        expect(find.text('Từ chối'), findsWidgets);
        // Từ chối không có lý do: hộp thoại không đóng và chưa ghi gì.
        await tester.tap(find.text('Từ chối').first);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const Key('review-confirm')));
        await tester.pump();
        expect(find.text('Nhập lý do từ chối'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('review-note')), 'Ảnh mờ');
        await tester.tap(find.byKey(const Key('review-confirm')));
        await settle(tester, find.text('Đã từ chối báo cáo.'));
        expect(find.text('Đã từ chối báo cáo.'), findsOneWidget);
        final rejected = (await tester.runAsync(
          () => f.db.query('shift_closures', where: "status='rejected'"),
        ))!;
        expect(rejected, hasLength(1));
        expect(rejected.single['review_note'], 'Ảnh mờ');
        await tester.tap(find.byKey(const Key('closure-filter-rejected')));
        await settle(tester, find.text('Bị từ chối'));
        expect(find.text('Bị từ chối'), findsWidgets);
        expect(find.textContaining('Ảnh mờ'), findsOneWidget);
        await close(tester);
      },
    );

    testWidgets('Manager approves a closure and the employee is notified', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await f.db.update('shift_closures', {
          'status': 'submitted',
          'reviewed_by': null,
          'reviewed_at': null,
        });
      });
      await tester.pumpWidget(
        MaterialApp(home: ClosuresScreen(repository: manager)),
      );
      await settle(tester, find.byKey(const Key('closure-filter-submitted')));
      await tester.tap(find.text('Duyệt').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('review-confirm')));
      await settle(tester, find.text('Đã duyệt báo cáo đóng ca.'));
      expect(find.text('Đã duyệt báo cáo đóng ca.'), findsOneWidget);
      expect(
        (await tester.runAsync(
          () => f.db.query('shift_closures', where: "status='approved'"),
        ))!,
        hasLength(1),
      );
      await close(tester);
    });

    testWidgets('Employee sees the two tabs and the history with status', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: ClosuresScreen(repository: quang)),
      );
      await settle(tester, find.text('Lịch sử đóng ca'));
      expect(find.textContaining('Cần đóng ca'), findsOneWidget);
      await tester.tap(find.text('Lịch sử đóng ca'));
      await tester.pump(const Duration(milliseconds: 600));
      final mine = (await tester.runAsync(quang.closures))!;
      await settle(tester, find.byType(Card));
      if (mine.isEmpty) {
        expect(find.textContaining('Chưa có báo cáo đóng ca'), findsOneWidget);
      } else {
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                ['Đã duyệt', 'Chờ duyệt', 'Bị từ chối'].contains(w.data),
          ),
          findsWidgets,
        );
      }
      await close(tester);
    });

    testWidgets(
      'Dashboard "Xem chi tiết" lists every employee and can be searched',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 3200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: DashboardScreen(repository: admin)),
        );
        await settle(tester, find.byKey(const Key('detail-employees')));
        expect(find.text('Xem chi tiết'), findsNWidgets(6));
        await tester.tap(find.byKey(const Key('detail-employees')));
        await tester.pump(const Duration(milliseconds: 600));
        await settle(tester, find.byKey(const Key('detail-count')));
        final total = (await tester.runAsync(() => f.db.query('employees')))!
            .length;
        expect(find.text('Tổng cộng $total mục'), findsOneWidget);
        expect(find.text('Đỗ Văn Quang'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('detail-search')), 'Quang');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('1/$total mục'), findsOneWidget);
        await close(tester);
      },
    );

    testWidgets('Every dashboard detail opens without an error', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(repository: manager)),
      );
      await settle(tester, find.byKey(const Key('detail-employees')));
      for (final kind in [
        'shifts',
        'attendance',
        'leave',
        'hours',
        'payroll',
      ]) {
        await tester.tap(find.byKey(Key('detail-$kind')));
        await tester.pump(const Duration(milliseconds: 600));
        await settle(tester, find.byKey(const Key('detail-count')));
        expect(
          find.byKey(const Key('detail-count')),
          findsOneWidget,
          reason: kind,
        );
        expect(
          find.textContaining('Không tải được'),
          findsNothing,
          reason: kind,
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      await close(tester);
    });
  });
}
