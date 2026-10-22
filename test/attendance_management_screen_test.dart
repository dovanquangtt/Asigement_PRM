import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/attendance_management_screen.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets(
      'Attendance dashboard fits phone $size and filters real SQLite data',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = (await tester.runAsync(
          () => DatabaseFixture.open(keepSampleUsers: true),
        ))!;
        addTearDown(f.dispose);
        late WorkforceRepository repo;
        await tester.runAsync(() async {
          repo = WorkforceRepository(
            await f.auth.signIn('admin', 'Admin@12345'),
            openDatabase: () async => f.db,
          );
          final local = DateTime.now().toUtc().add(const Duration(hours: 7));
          final start = DateTime.utc(
            local.year,
            local.month,
            local.day,
          ).subtract(const Duration(hours: 6));
          final shift = await repo.createShift(
            branchId: 1,
            start: start,
            end: start.add(const Duration(hours: 8)),
            requiredStaff: 3,
          );
          final people = await f.db.query('employees', orderBy: 'id');
          final names = [
            'Nhân viên đúng giờ',
            'Nhân viên đi muộn',
            'Nhân viên tăng ca',
          ];
          for (var i = 0; i < people.length; i++) {
            await f.db.update(
              'employees',
              {'full_name': names[i]},
              where: 'id=?',
              whereArgs: [people[i]['id']],
            );
            await repo.assignShift(shift, people[i]['id'] as int);
            final assignment =
                (await f.db.query(
                      'shift_assignments',
                      where: 'employee_id=?',
                      whereArgs: [people[i]['id']],
                    )).single['id']
                    as int;
            final id = await f.db.insert('attendance_records', {
              'assignment_id': assignment,
              'check_in_at': sqlTime(start),
              'check_out_at': i == 1
                  ? null
                  : sqlTime(start.add(const Duration(hours: 8))),
              'status': 'present',
              'arrival_status': i == 1 ? 'LATE' : 'ON_TIME',
              'late_minutes': i == 1 ? 15 : 0,
              'overtime_status': i == 2 ? 'PENDING' : 'NOT_REQUIRED',
              'overtime_requested_minutes': i == 2 ? 30 : 0,
            });
            if (i == 1) {
              await f.db.insert('attendance_adjustment_requests', {
                'attendance_id': id,
                'requested_by': people[i]['user_id'],
                'reason': 'Quên giờ ra',
              });
            }
          }
        });
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(home: AttendanceManagementScreen(repository: repo)),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pumpAndSettle();
        expect(find.text('Quản lý chấm công'), findsOneWidget);
        expect(find.text('Tổng nhân viên'), findsOneWidget);
        expect(find.text('Đã điểm danh'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Cần xử lý'));
        await tester.tap(find.text('Cần xử lý'));
        await tester.pumpAndSettle();
        expect(find.text('Nhân viên đúng giờ'), findsNothing);
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Đi muộn'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Đi muộn'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Nhân viên đi muộn'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Nhân viên đi muộn'), findsOneWidget);
        expect(find.text('Nhân viên tăng ca'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
