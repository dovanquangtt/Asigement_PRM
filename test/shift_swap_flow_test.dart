import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/shift_swap_screen.dart';
import 'package:quanlinhansunhahang/services/auth_service.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

/// M05 Đổi ca: nhân viên xem ca đổi được, gửi yêu cầu cho đồng nghiệp, hai bên đồng ý/từ chối,
/// và chỉ khi cả hai đồng ý quản lý (không tham gia) mới duyệt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseFixture f;
  late WorkforceRepository alice, bob, manager, admin;
  late int aliceId, bobId, branch;
  // a1/a2 của Alice; b1/b2 của Bob (id của phân ca).
  final ids = <String, int>{};

  // Tuần sau: Thứ Hai (a1), Thứ Ba (b1), Thứ Tư (a2 và b2 cùng giờ), tất cả 08:00–12:00.
  DateTime day(int offset) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day - (t.weekday - 1) + 7 + offset, 8);
  }

  Future<WorkforceRepository> repo(String n, String p) async =>
      WorkforceRepository(
        await f.auth.signIn(n, p),
        openDatabase: () async => f.db,
      );

  Future<int> assignTo(
    WorkforceRepository who,
    int employeeId,
    DateTime start, {
    Duration length = const Duration(hours: 4),
  }) async {
    final shift = await manager.createShift(
      branchId: branch,
      start: start.toUtc(),
      end: start.add(length).toUtc(),
    );
    await manager.assignShift(shift, employeeId);
    return (await f.db.query(
          'shift_assignments',
          where: 'shift_id=? AND employee_id=?',
          whereArgs: [shift, employeeId],
        )).single['id']
        as int;
  }

  setUp(() async {
    f = await DatabaseFixture.open(keepSampleUsers: true);
    alice = await repo('employee', 'Employee@12345');
    manager = await repo('manager', 'Manager@12345');
    admin = await repo('admin', 'Admin@12345');
    branch = alice.session.profile['branch_id'] as int;
    aliceId = alice.session.profile['id'] as int;
    // Nhân viên thứ hai có tài khoản đăng nhập.
    final bobUser = await f.addUser(username: 'bob');
    bobId = await f.db.insert('employees', {
      'user_id': bobUser,
      'employee_code': 'BOB01',
      'full_name': 'Trần Thị B',
      'branch_id': branch,
      'hire_date': '2026-01-01',
      'status': 'active',
    });
    bob = await repo('bob', 'TestPass123!');
    ids['a1'] = await assignTo(alice, aliceId, day(0));
    ids['b1'] = await assignTo(bob, bobId, day(1));
    ids['a2'] = await assignTo(alice, aliceId, day(2));
    ids['b2'] = await assignTo(bob, bobId, day(2));
  });
  tearDown(() => f.dispose());

  Future<int> request(
    String reason, {
    String mine = 'a1',
    String theirs = 'b1',
  }) async {
    await alice.requestSwap(ids[mine]!, ids[theirs]!, reason);
    return (await f.db.query(
          'shift_swap_requests',
          orderBy: 'id DESC',
          limit: 1,
        )).single['id']
        as int;
  }

  RowData row(List<RowData> list, int id) =>
      list.singleWhere((r) => r['id'] == id);

  test('Alice only sees shifts Bob can really swap with her (no overlap), sorted by date', () async {
    final forA1 = await alice.swapOptions(ids['a1']!);
    // b2 (Thứ Tư 08:00) trùng giờ với a2 của chính Alice => không đổi được; chỉ còn b1.
    expect(forA1.map((o) => o['id']), [ids['b1']]);
    expect(forA1.single['full_name'], 'Trần Thị B');
    // Với a2: nhận b1 thì Bob bị trùng b2; chỉ còn b2 (cùng giờ nhưng khác ca).
    final forA2 = await alice.swapOptions(ids['a2']!);
    expect(forA2.map((o) => o['id']), [ids['b2']]);
    final mine = await alice.swappableShifts();
    expect(mine.map((s) => s['id']), [ids['a1'], ids['a2']]);
    expect(mine.map((s) => s['options_count']), [1, 1]);
    expect(mine.every((s) => s['blocker'] == null), isTrue);
  });

  test(
    'Started, ended or attended shifts cannot be swapped and give a reason',
    () async {
      final past = await assignTo(
        alice,
        aliceId,
        DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(await alice.swapOptions(past), isEmpty);
      await expectLater(
        alice.requestSwap(past, ids['b1']!, 'Việc riêng'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Chỉ đổi ca tương lai'),
          ),
        ),
      );
      // Ca sắp tới đã có điểm danh => không đổi được.
      await f.db.insert('attendance_events', {
        'assignment_id': ids['a1'],
        'event_type': 'check_in',
        'occurred_at': '2026-01-01 00:00:00',
        'device_valid': 0,
        'gps_valid': 0,
        'wifi_valid': 0,
        'result': 'rejected',
      });
      expect(await alice.swapOptions(ids['a1']!), isEmpty);
      final a1 = (await alice.swappableShifts()).singleWhere(
        (s) => s['id'] == ids['a1'],
      );
      expect(a1['blocker'], 'Ca đã có điểm danh.');
      expect(a1['options_count'], 0);
    },
  );

  test('Conflicts are reported at request time with who is affected', () async {
    // Alice nhận b2 (Thứ Tư) nhưng vẫn giữ a2 cùng giờ => Alice bị trùng giờ.
    await expectLater(
      alice.requestSwap(ids['a1']!, ids['b2']!, 'Đổi thử'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          startsWith('Bạn:'),
        ),
      ),
    );
    await expectLater(
      alice.requestSwap(ids['a1']!, ids['b1']!, '  '),
      throwsA(isA<AuthException>()),
    );
    expect(await f.db.query('shift_swap_requests'), isEmpty);
  });

  test('Full flow: both agree, only then the manager approves and the shifts change hands', () async {
    final id = await request('Có việc gia đình');
    // Bob được báo ngay, nội dung nêu rõ hai ca.
    final note = (await bob.notifications()).firstWhere(
      (n) => n['title'] == 'Yêu cầu đổi ca mới',
    );
    expect(
      note['body'],
      allOf(contains('đổi ca'), contains('Có việc gia đình')),
    );
    expect(note['related_id'], id);

    // Cả hai thấy yêu cầu với trạng thái "chờ người nhận".
    for (final who in [alice, bob]) {
      final r = row(await who.swaps(), id);
      expect(swapStage(r), SwapStage.waitingCounterpart);
      expect(r['from_name'], isNotEmpty);
      expect(r['to_name'], 'Trần Thị B');
      expect(r['target_user_id'], bob.session.userId);
    }
    // Ca đang có yêu cầu thì không thể đem đi đổi lần nữa.
    expect(
      (await alice.swappableShifts()).singleWhere(
        (s) => s['id'] == ids['a1'],
      )['blocker'],
      'Ca đang có yêu cầu đổi chờ xử lý.',
    );
    // Quản lý chưa duyệt được khi người nhận chưa đồng ý; người gửi không tự duyệt.
    await expectLater(
      manager.respondSwap(id, true, review: true),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      alice.respondSwap(id, true),
      throwsA(isA<AuthException>()),
      reason: 'người gửi không trả lời thay người nhận',
    );

    // Bob đồng ý.
    await bob.respondSwap(id, true);
    expect(swapStage(row(await alice.swaps(), id)), SwapStage.waitingManager);
    expect(
      (await alice.notifications()).any((n) => n['title'] == 'Phản hồi đổi ca'),
      isTrue,
    );
    expect(
      (await manager.notifications()).any(
        (n) => n['title'] == 'Đổi ca chờ duyệt',
      ),
      isTrue,
    );
    // Người tham gia không tự duyệt; quản lý không tham gia thì duyệt được.
    await expectLater(
      bob.respondSwap(id, true, review: true),
      throwsA(isA<AuthException>()),
    );
    await manager.respondSwap(id, true, review: true);

    String owner(String key) =>
        '${(f.db.query('shift_assignments', where: 'id=?', whereArgs: [ids[key]]))}';
    final a1 = (await f.db.query(
      'shift_assignments',
      where: 'id=?',
      whereArgs: [ids['a1']],
    )).single;
    final b1 = (await f.db.query(
      'shift_assignments',
      where: 'id=?',
      whereArgs: [ids['b1']],
    )).single;
    expect(owner('a1'), isNotEmpty);
    expect(a1['employee_id'], bobId);
    expect(b1['employee_id'], aliceId);
    // Ca mới của mỗi người coi như đã chấp nhận (hai bên đã đồng ý đổi).
    expect(a1['response_status'], 'accepted');
    expect(b1['response_status'], 'accepted');
    final done = row(await alice.swaps(), id);
    expect(swapStage(done), SwapStage.approved);
    expect(done['reviewer_name'], 'manager');
    for (final who in [alice, bob]) {
      expect(
        (await who.notifications()).any(
          (n) => n['title'] == 'Kết quả duyệt đổi ca',
        ),
        isTrue,
      );
    }
    // Sau khi đổi, ca của Alice (b1, Thứ Ba) hiện trong lịch của chính Alice.
    expect(
      (await alice.employeeSchedule()).any(
        (s) => s['assignment_id'] == ids['b1'],
      ),
      isTrue,
    );
    expect(await f.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'If the other side rejects, the request closes and nothing changes',
    () async {
      final id = await request('Đổi ca giúp mình');
      await bob.respondSwap(id, false);
      final r = row(await alice.swaps(), id);
      expect(swapStage(r), SwapStage.rejectedByCounterpart);
      expect(
        (await alice.notifications()).any(
          (n) => '${n['body']}'.contains('từ chối'),
        ),
        isTrue,
      );
      await expectLater(
        manager.respondSwap(id, true, review: true),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        alice.cancelSwap(id),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Yêu cầu đã được xử lý.',
          ),
        ),
      );
      final a1 = (await f.db.query(
        'shift_assignments',
        where: 'id=?',
        whereArgs: [ids['a1']],
      )).single;
      expect(a1['employee_id'], aliceId);
      // Ca được giải phóng, có thể gửi yêu cầu khác.
      expect(await alice.swapOptions(ids['a1']!), isNotEmpty);
    },
  );

  test('The manager can decline after both agreed; the shifts stay', () async {
    final id = await request('Lý do');
    await bob.respondSwap(id, true);
    await admin.respondSwap(id, false, review: true);
    expect(swapStage(row(await bob.swaps(), id)), SwapStage.rejectedByManager);
    final a1 = (await f.db.query(
      'shift_assignments',
      where: 'id=?',
      whereArgs: [ids['a1']],
    )).single;
    expect(a1['employee_id'], aliceId);
  });

  test(
    'Requester can cancel; nobody else can; the other side is told',
    () async {
      final id = await request('Lý do');
      await expectLater(
        bob.cancelSwap(id),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Chỉ người gửi mới hủy được yêu cầu.',
          ),
        ),
      );
      await alice.cancelSwap(id);
      expect(swapStage(row(await alice.swaps(), id)), SwapStage.cancelled);
      expect(
        (await bob.notifications()).any(
          (n) => n['title'] == 'Yêu cầu đổi ca đã bị hủy',
        ),
        isTrue,
      );
      await expectLater(
        bob.respondSwap(id, true),
        throwsA(isA<AuthException>()),
      );
      // Hủy xong thì ca đổi được lại.
      expect(
        (await alice.swappableShifts()).singleWhere(
          (s) => s['id'] == ids['a1'],
        )['blocker'],
        isNull,
      );
    },
  );

  test(
    'Cancelling after the other side agreed also tells the managers',
    () async {
      final id = await request('Lý do');
      await bob.respondSwap(id, true);
      await alice.cancelSwap(id);
      await expectLater(
        manager.respondSwap(id, true, review: true),
        throwsA(isA<AuthException>()),
      );
      expect(swapStage(row(await manager.swaps(), id)), SwapStage.cancelled);
    },
  );

  test(
    'Each person sees only own requests; managers see all, pending first',
    () async {
      final first = await request('Lần 1');
      await bob.respondSwap(first, false);
      await alice.requestSwap(ids['a2']!, ids['b2']!, 'Lần 2');
      final second =
          (await f.db.query(
                'shift_swap_requests',
                orderBy: 'id DESC',
                limit: 1,
              )).single['id']
              as int;
      final seen = (await alice.swaps()).map((r) => r['id']).toList();
      expect(seen, [second, first], reason: 'yêu cầu đang chờ lên đầu');
      expect((await manager.swaps()).map((r) => r['id']).toSet(), {
        first,
        second,
      });
    },
  );

  group('swap stage', () {
    RowData r(String status, String counterpart) => {
      'status': status,
      'counterpart_status': counterpart,
    };
    test('maps every state', () {
      expect(swapStage(r('pending', 'pending')), SwapStage.waitingCounterpart);
      expect(swapStage(r('pending', 'accepted')), SwapStage.waitingManager);
      expect(swapStage(r('approved', 'accepted')), SwapStage.approved);
      expect(
        swapStage(r('rejected', 'rejected')),
        SwapStage.rejectedByCounterpart,
      );
      expect(swapStage(r('rejected', 'accepted')), SwapStage.rejectedByManager);
      expect(swapStage(r('cancelled', 'pending')), SwapStage.cancelled);
      expect(
        swapStageStyle(SwapStage.waitingCounterpart, 'Bob').label,
        'Chờ Bob đồng ý',
      );
    });
  });

  group('screens', () {
    Future<void> settle(WidgetTester tester, Finder until) async {
      for (var i = 0; i < 50 && until.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Cho hoạt ảnh chuyển tab / bảng trượt lên kết thúc trước khi thao tác tiếp.
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// Chờ các lần tải nền (danh sách ca/yêu cầu) xong trước khi test kết thúc và DB bị đóng.
    Future<void> drain(WidgetTester tester) async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> open(
      WidgetTester tester,
      WorkforceRepository who, {
      int? initial,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ShiftSwapScreen(repository: who, initialAssignmentId: initial),
        ),
      );
    }

    testWidgets(
      'Alice picks a swappable shift, sends the request and sees its status',
      (tester) async {
        await open(tester, alice);
        await settle(tester, find.byKey(Key('swap-mine-${ids['a1']}')));
        // Tab "Ca có thể đổi": hai ca, mỗi ca 1 lựa chọn.
        expect(find.text('1 ca có thể đổi'), findsNWidgets(2));
        await tester.tap(find.byKey(Key('swap-pick-${ids['a1']}')));
        await settle(tester, find.byKey(Key('swap-option-${ids['b1']}')));
        // Chỉ hiện ca đổi được (b2 bị loại vì trùng giờ với a2).
        expect(find.byKey(Key('swap-option-${ids['b2']}')), findsNothing);
        await tester.tap(find.byKey(Key('swap-option-${ids['b1']}')));
        await settle(tester, find.byKey(const Key('swap-send')));
        // Lý do bắt buộc.
        await tester.tap(find.byKey(const Key('swap-send')));
        await tester.pump();
        expect(find.text('Nhập lý do đổi ca'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('swap-reason')),
          'Có việc riêng',
        );
        await tester.tap(find.byKey(const Key('swap-send')));
        await settle(tester, find.textContaining('Đã gửi yêu cầu'));
        // Tự chuyển sang tab "Yêu cầu đổi ca" và hiện trạng thái.
        final request = (await tester.runAsync(
          () => f.db.query('shift_swap_requests'),
        ))!.single['id'];
        await settle(tester, find.byKey(Key('swap-card-$request')));
        expect(find.text('Chờ Trần Thị B đồng ý'), findsWidgets);
        expect(find.byKey(Key('swap-cancel-$request')), findsOneWidget);
        expect(find.byKey(Key('swap-accept-$request')), findsNothing);
        expect(find.text('Bạn gửi'), findsOneWidget);
        await drain(tester);
      },
    );

    testWidgets(
      'Bob accepts from his list; the card moves to "waiting for manager"',
      (tester) async {
        final id = (await tester.runAsync(() => request('Có việc riêng')))!;
        await open(tester, bob);
        await settle(tester, find.byKey(Key('swap-tab-requests')));
        await tester.tap(find.byKey(const Key('swap-tab-requests')));
        await tester.pump(const Duration(milliseconds: 400));
        await settle(tester, find.byKey(Key('swap-card-$id')));
        expect(find.text('Gửi cho bạn'), findsOneWidget);
        expect(find.byKey(Key('swap-accept-$id')), findsOneWidget);
        expect(find.byKey(Key('swap-reject-$id')), findsOneWidget);
        await tester.tap(find.byKey(Key('swap-accept-$id')));
        await settle(tester, find.byKey(const Key('swap-confirm')));
        await tester.tap(find.byKey(const Key('swap-confirm')));
        await settle(
          tester,
          find.text('Hai bên đã đồng ý • chờ quản lý duyệt'),
        );
        expect(
          find.text('Hai bên đã đồng ý • chờ quản lý duyệt'),
          findsOneWidget,
        );
        expect(find.byKey(Key('swap-accept-$id')), findsNothing);
        expect(
          (await tester.runAsync(() => f.db.query('shift_swap_requests')))!
              .single['counterpart_status'],
          'accepted',
        );
        await drain(tester);
      },
    );

    testWidgets(
      'Manager sees the request but can approve only after both agreed',
      (tester) async {
        final id = (await tester.runAsync(() => request('Có việc riêng')))!;
        await open(tester, manager);
        await settle(tester, find.byKey(Key('swap-card-$id')));
        expect(find.byKey(const Key('swap-tab-mine')), findsNothing);
        expect(find.byKey(Key('swap-approve-$id')), findsNothing);
        expect(find.byKey(Key('swap-step-manager-$id')), findsOneWidget);
        await tester.runAsync(() => bob.respondSwap(id, true));
        await tester.tap(find.byTooltip('Tải lại'));
        await tester.pump();
        await settle(tester, find.byKey(Key('swap-approve-$id')));
        expect(find.byKey(Key('swap-deny-$id')), findsOneWidget);
        await tester.tap(find.byKey(Key('swap-approve-$id')));
        await settle(tester, find.text('Đã đổi ca'));
        expect(find.text('Đã đổi ca'), findsWidgets);
        expect(
          (await tester.runAsync(
            () => f.db.query(
              'shift_assignments',
              where: 'id=?',
              whereArgs: [ids['a1']],
            ),
          ))!.single['employee_id'],
          bobId,
        );
        await drain(tester);
      },
    );

    testWidgets(
      'Opening from a shift card jumps straight to choosing the other shift',
      (tester) async {
        await open(tester, alice, initial: ids['a1']);
        await settle(tester, find.byKey(Key('swap-option-${ids['b1']}')));
        expect(find.text('Chọn ca muốn đổi'), findsOneWidget);
        await drain(tester);
      },
    );

    testWidgets(
      'A shift that cannot be swapped shows why and its button is disabled',
      (tester) async {
        await tester.runAsync(() => request('Đã gửi rồi'));
        await open(tester, alice);
        await settle(tester, find.byKey(Key('swap-mine-status-${ids['a1']}')));
        expect(find.text('Ca đang có yêu cầu đổi chờ xử lý.'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(Key('swap-pick-${ids['a1']}')))
              .onPressed,
          isNull,
        );
        await drain(tester);
      },
    );
  });
}
