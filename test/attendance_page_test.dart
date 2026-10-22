import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlinhansunhahang/screens/operations_screen.dart';
import 'package:quanlinhansunhahang/services/attendance_evidence.dart';
import 'package:quanlinhansunhahang/services/attendance_sensors.dart';
import 'package:quanlinhansunhahang/services/workforce_repository.dart';

import 'database_fixture.dart';

class _Sensors extends AttendanceSensors {
  bool wrongWifi = false;
  int reads = 0;
  @override
  Future<AttendanceEvidence> collect({
    bool location = true,
    bool gps = true,
    bool wifi = true,
  }) async {
    reads++;
    return AttendanceEvidence(
      deviceIdentifier: 'phone-test',
      platform: 'android',
      collectedAt: DateTime.now().toUtc(),
      latitude: 10.77,
      longitude: 106.69,
      accuracy: 5,
      ssid: 'Restaurant',
      bssid: wrongWifi ? '00:00:00:00:00:00' : 'aa:bb:cc:dd:ee:ff',
    );
  }
}

void main() {
  testWidgets(
    'M01 submits pending review with fresh evidence even when Wi-Fi fails',
    (tester) async {
      tester.view.physicalSize = const Size(412, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sensors = _Sensors();
      final fixture = (await tester.runAsync(
        () => DatabaseFixture.open(keepSampleUsers: true),
      ))!;
      addTearDown(fixture.dispose);
      late WorkforceRepository employee;
      late int assignment;
      await tester.runAsync(() async {
        employee = WorkforceRepository(
          await fixture.auth.signIn('employee', 'Employee@12345'),
          openDatabase: () async => fixture.db,
        );
        final manager = WorkforceRepository(
          await fixture.auth.signIn('manager', 'Manager@12345'),
          openDatabase: () async => fixture.db,
        );
        final branch = employee.session.profile['branch_id'] as int;
        await manager.configureBranch(
          branch,
          latitude: 10.77,
          longitude: 106.69,
          radius: 100,
          ssid: 'Restaurant',
          bssid: 'aa:bb:cc:dd:ee:ff',
        );
        await employee.registerDevice(await sensors.collect(location: false));
        await manager.approveDevice(
          (await fixture.db.query('employee_devices')).single['id'] as int,
        );
        final now = DateTime.now().toUtc();
        final shift = await manager.createShift(
          branchId: branch,
          start: now.subtract(const Duration(minutes: 5)),
          end: now.add(const Duration(hours: 1)),
        );
        await manager.assignShift(shift, employee.session.profile['id'] as int);
        assignment =
            (await fixture.db.query('shift_assignments')).single['id'] as int;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AttendancePage(
            repository: employee,
            assignmentId: assignment,
            sensors: sensors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      bool enabled() =>
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Xác nhận điểm danh'),
              )
              .onPressed !=
          null;
      expect(enabled(), isTrue);
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label).last);
        await tester.runAsync(() async {
          await tester.tap(find.text(label).last);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        if (label == 'Xác nhận điểm danh') {
          await tester.pump(const Duration(milliseconds: 300));
        } else {
          await tester.pumpAndSettle();
        }
      }

      await tap('Kiểm tra thiết bị');
      expect(enabled(), isTrue);
      await tap('Kiểm tra GPS');
      expect(enabled(), isTrue);
      await tap('Kiểm tra Wi-Fi');
      expect(enabled(), isTrue);
      final beforeConfirm = sensors.reads;
      sensors.wrongWifi = true;
      await tap('Xác nhận điểm danh');
      expect(find.text('Gửi yêu cầu vào ca?'), findsOneWidget);
      await tap('Gửi yêu cầu');
      expect(sensors.reads, beforeConfirm + 3);
      expect(enabled(), isFalse);
      await tester.runAsync(() async {
        expect(await fixture.db.query('attendance_records'), isEmpty);
        expect(
          (await fixture.db.query('attendance_events')).single['result'],
          'pending_review',
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}
