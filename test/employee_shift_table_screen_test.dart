import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/employee_shift_table_screen.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Manager reviews an employee punch directly from the shift table (phone width)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late DatabaseFixture f;
      late WorkforceRepository manager;
      await tester.runAsync(() async {
        f = await DatabaseFixture.open(keepSampleUsers: true);
        Future<WorkforceRepository> repo(String n, String p) async =>
            WorkforceRepository(
              await f.auth.signIn(n, p),
              openDatabase: () async => f.db,
            );
        manager = await repo('manager', 'Manager@12345');
        final employee = await repo('employee', 'Employee@12345');
        final start = DateTime.now().toUtc().subtract(
          const Duration(minutes: 30),
        );
        final shift = await manager.createShift(
          branchId: employee.session.profile['branch_id'] as int,
          start: start,
          end: start.add(const Duration(hours: 4)),
        );
        await manager.assignShift(shift, employee.session.profile['id'] as int);
        final assignment =
            (await f.db.query('shift_assignments')).single['id'] as int;
        // Wrong Wi-Fi / unapproved device => goes to manual review instead of the timesheet.
        await employee.submitAttendance(
          assignment,
          'check_in',
          AttendanceEvidence(
            deviceIdentifier: 'real-phone',
            platform: 'android',
            collectedAt: DateTime.now().toUtc(),
            latitude: 10.77,
            longitude: 106.69,
            accuracy: 5,
            ssid: 'Other Wifi',
            bssid: '00:00:00:00:00:00',
          ),
        );
      });
      addTearDown(() => tester.runAsync(() => f.dispose()));

      Future<void> settle(Finder until) async {
        for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(
        MaterialApp(home: EmployeeShiftTableScreen(repository: manager)),
      );
      await settle(find.byKey(const Key('table-employee')));
      await tester.tap(find.byKey(const Key('table-employee')));
      await tester.pump(
        const Duration(milliseconds: 500),
      ); // spinner may still be animating
      await tester.tap(find.textContaining('DEMO_EMPLOYEE').last);
      await tester.pump();
      await settle(find.textContaining('(chờ duyệt)'));

      // Everything the manager needs is visible without any horizontal scrolling.
      expect(find.textContaining('(chờ duyệt)'), findsOneWidget);
      expect(find.text('Phản hồi chấm công'), findsOneWidget);
      expect(find.text('Duyệt Vào'), findsOneWidget);
      expect(find.text('Từ chối Vào'), findsOneWidget);

      await tester.tap(find.text('Duyệt Vào'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('review-note')),
        'Đã kiểm tra',
      );
      await tester.tap(find.byKey(const Key('review-confirm')));
      await settle(find.text('Chưa có phản hồi chấm công'));
      for (
        var i = 0;
        i < 40 && find.text('Phản hồi chấm công').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Phản hồi chấm công'), findsNothing);
      expect(find.textContaining('(chờ duyệt)'), findsNothing);
      expect(
        (await tester.runAsync(
          () => f.db.query('attendance_records', columns: ['check_in_at']),
        ))!.single['check_in_at'],
        isNotNull,
      );
    },
  );
}
