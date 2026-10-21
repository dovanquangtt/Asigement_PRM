import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'payroll_source.dart';

/// Nhãn riêng để lần nạp sau không nhân đôi hoặc sửa lại dữ liệu đã chỉnh.
const featureSampleMarker = 'sample.features.v1';
const closureSampleAsset = 'database/demo_assets/closure_sample.png';

class SampleDataException implements Exception {
  const SampleDataException(this.message);
  final String message;
}

String _stamp(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
String _date(DateTime value) => value.toIso8601String().substring(0, 10);

/// Nạp duy nhất bộ tình huống DEMO trong một transaction, không xóa bảng nào.
/// Cần có đúng các hồ sơ mẫu ban đầu; không tự biến tài khoản thật thành mẫu.
Future<bool> installFeatureSamples(
  Database db, {
  DateTime? referenceTime,
  bool onlyForDemoAccounts = false,
}) async {
  final now = (referenceTime ?? DateTime.now()).toUtc();
  final local = now.add(const Duration(hours: 7));
  final today = DateTime.utc(local.year, local.month, local.day);
  final historyEnd = today.subtract(const Duration(days: 2));
  final historyStart = historyEnd.subtract(const Duration(days: 6));
  final openStart = historyEnd.add(const Duration(days: 1));
  final openEnd = openStart.add(const Duration(days: 29));
  // Các ngày ở trên là ngày lịch Việt Nam; chuyển về UTC khi tạo ca.
  DateTime at(DateTime day, int hour) => day.add(Duration(hours: hour - 7));
  return db.transaction((tx) async {
    if ((await tx.query(
      'audit_logs',
      where: 'action=?',
      whereArgs: [featureSampleMarker],
      limit: 1,
    )).isNotEmpty) {
      return false;
    }
    final people = <String, Map<String, Object?>>{};
    // Chỉ tự bổ sung cho đúng ba hồ sơ demo gốc, giữ nguyên nghiệp vụ nhập tay.
    // Database có tài khoản khác dùng thao tác nạp mẫu chủ động của Admin.
    if (onlyForDemoAccounts) {
      for (final table in ['users', 'employees']) {
        final count = (await tx.rawQuery('SELECT COUNT(*) AS n FROM $table'))
            .single['n'];
        if (count != 3) return false;
      }
      // Dữ liệu nhập tay không ngăn nạp mẫu: transaction chỉ thêm bản ghi DEMO.
      // Nếu mã mẫu đã được dùng nhưng thiếu marker, để Admin xử lý chủ động.
      if ((await tx.rawQuery(
        "SELECT id FROM shift_templates WHERE code IN ('DEMO_MORNING','DEMO_EVENING','DEMO_SHORT','DEMO_NIGHT') LIMIT 1",
      )).isNotEmpty) {
        return false;
      }
    }
    for (final pair in [
      ('admin', 'DEMO_ADMIN'),
      ('manager', 'DEMO_MANAGER'),
      ('employee', 'DEMO_EMPLOYEE'),
    ]) {
      final rows = await tx.rawQuery(
        'SELECT e.*,u.username FROM employees e JOIN users u ON u.id=e.user_id WHERE u.username=? AND e.employee_code=?',
        [pair.$1, pair.$2],
      );
      if (rows.length != 1) {
        if (onlyForDemoAccounts) return false;
        throw const SampleDataException(
          'Thiếu hồ sơ mẫu admin/manager/employee. Không sửa hoặc ghi đè tài khoản hiện có.',
        );
      }
      people[pair.$1] = rows.single;
    }
    final admin = people['admin']!['user_id'] as int;
    final manager = people['manager']!['user_id'] as int;
    final employee = people['employee']!['user_id'] as int;
    final branch = people['employee']!['branch_id'] as int;
    if (people.values.any((p) => p['branch_id'] != branch)) {
      if (onlyForDemoAccounts) return false;
      throw const SampleDataException(
        'Ba hồ sơ mẫu phải cùng chi nhánh để nạp bộ tình huống.',
      );
    }
    // Chỉ bổ sung cấu hình đang trống. Không ghi đè GPS thật đã được người dùng nhập.
    await tx.rawUpdate(
      'UPDATE branches SET latitude=?,longitude=? WHERE id=? AND latitude IS NULL AND longitude IS NULL',
      [10.7769, 106.7009, branch],
    );
    final wifiExists = await tx.query(
      'branch_wifi',
      where: 'branch_id=? AND bssid=?',
      whereArgs: [branch, '02:00:00:00:de:01'],
    );
    if (wifiExists.isEmpty) {
      await tx.insert('branch_wifi', {
        'branch_id': branch,
        'ssid': 'MOC_DEMO_WIFI',
        'bssid': '02:00:00:00:de:01',
        'is_active': 1,
      });
    }
    final templates = <String, int>{};
    for (final t in [
      ('MORNING', 'Ca sáng DEMO', '08:00', '16:00', 0, 30),
      ('EVENING', 'Ca chiều DEMO', '17:00', '21:00', 0, 15),
      ('SHORT', 'Ca ngắn DEMO', '21:30', '23:00', 0, 0),
      ('NIGHT', 'Ca qua đêm DEMO', '22:00', '06:00', 1, 30),
    ]) {
      templates[t.$1] = await tx.insert('shift_templates', {
        'code': 'DEMO_${t.$1}',
        'name': t.$2,
        'start_time': t.$3,
        'end_time': t.$4,
        'ends_next_day': t.$5,
        'break_minutes': t.$6,
        'late_grace_minutes': 5,
      });
    }
    final devices = <String, int>{};
    final contracts = <String, int>{};
    final newAnnualBalances = <String>{};
    final rates = {
      'admin': 24000000,
      'manager': 18000000,
      'employee': 10000000,
    };
    for (final p in people.entries) {
      devices[p.key] = await tx.insert('employee_devices', {
        'employee_id': p.value['id'],
        'device_identifier': 'DEMO_DEVICE_${p.key.toUpperCase()}',
        'platform': 'android (mẫu, không phải thiết bị thật)',
        'registered_at': _stamp(at(historyStart, 7)),
        'approved_by': p.key == 'admin' ? manager : admin,
      });
      contracts[p.key] = await tx.insert('contracts', {
        'employee_id': p.value['id'],
        'contract_number': 'DEMO_CT_${p.key.toUpperCase()}',
        'contract_type': 'indefinite',
        'start_date': _date(historyStart),
        'salary_basis': 'monthly',
        'base_salary_vnd': rates[p.key],
        'hourly_rate_vnd': 0,
        'standard_minutes_per_month': 12480,
        'status': 'active',
      });
      final leave = (await tx.query(
        'leave_types',
        where: 'code=?',
        whereArgs: ['ANNUAL'],
      )).single;
      final previousBalance = await tx.query(
        'leave_balances',
        where: 'employee_id=? AND leave_type_id=? AND year=?',
        whereArgs: [p.value['id'], leave['id'], today.year],
      );
      // Không đổi cả số phút đã cấp/đã dùng của số dư người dùng đã nhập.
      if (previousBalance.isEmpty) {
        newAnnualBalances.add(p.key);
        await tx.insert('leave_balances', {
          'employee_id': p.value['id'],
          'leave_type_id': leave['id'],
          'year': today.year,
          'granted_minutes': 5760,
          'used_minutes': 0,
        });
      }
    }
    await tx.insert('employee_devices', {
      'employee_id': people['employee']!['id'],
      'device_identifier': 'DEMO_DEVICE_PENDING',
      'platform': 'android (mẫu chờ duyệt)',
    });
    await tx.insert('employee_devices', {
      'employee_id': people['employee']!['id'],
      'device_identifier': 'DEMO_DEVICE_REVOKED',
      'platform': 'android (mẫu đã thu hồi)',
      'revoked_at': _stamp(now),
      'approved_by': manager,
    });
    final assignments = <String, int>{};
    final records = <String, int>{};
    Future<int> shift(
      String code,
      DateTime starts,
      DateTime ends,
      List<String> staff, {
      String? template = 'MORNING',
      String status = 'scheduled',
      bool completed = false,
      int extraCapacity = 0,
    }) async {
      final id = await tx.insert('shifts', {
        'branch_id': branch,
        'template_id': template == null ? null : templates[template],
        'starts_at': _stamp(starts),
        'ends_at': _stamp(ends),
        'required_staff': staff.length + extraCapacity,
        'status': status,
        'created_by': manager,
        'note': '[DEMO $code] Dữ liệu mẫu để thử chức năng; giờ Việt Nam.',
      });
      for (final name in staff) {
        assignments['$code/$name'] = await tx.insert('shift_assignments', {
          'shift_id': id,
          'employee_id': people[name]!['id'],
          'assigned_by': manager,
          'assigned_at': _stamp(now),
          'status': completed ? 'completed' : 'assigned',
        });
      }
      return id;
    }

    Future<int> worked(
      String key,
      DateTime starts,
      DateTime scheduledEnd, {
      int breakMinutes = 30,
      int overtime = 0,
    }) async {
      final name = key.split('/').last;
      final assignment = assignments[key]!;
      final out = scheduledEnd.add(Duration(minutes: overtime));
      for (final e in [('check_in', starts), ('check_out', out)]) {
        await tx.insert('attendance_events', {
          'assignment_id': assignment,
          'event_type': e.$1,
          'occurred_at': _stamp(e.$2),
          'device_id': devices[name],
          'latitude': 10.7769,
          'longitude': 106.7009,
          'gps_accuracy_m': 5,
          'wifi_ssid': 'MOC_DEMO_WIFI',
          'wifi_bssid': '02:00:00:00:de:01',
          'device_valid': 1,
          'gps_valid': 1,
          'wifi_valid': 1,
          'result': 'accepted',
          'confirmed_at': _stamp(e.$2),
        });
      }
      final id = await tx.insert('attendance_records', {
        'assignment_id': assignment,
        'check_in_at': _stamp(starts),
        'check_out_at': _stamp(out),
        'worked_minutes': out.difference(starts).inMinutes - breakMinutes,
        'overtime_minutes': overtime,
        'status': 'present',
        'approved_by': name == 'admin' ? manager : admin,
        'approved_at': _stamp(out),
      });
      records[key] = id;
      return id;
    }

    Future<void> closure(
      String key,
      String status, {
      String? reviewNote,
    }) async {
      final name = key.split('/').last;
      final record = (await tx.query(
        'attendance_records',
        where: 'id=?',
        whereArgs: [records[key]],
      )).single;
      final submitted = _utc(record['check_out_at'])
          .add(const Duration(minutes: 5));
      final id = await tx.insert('shift_closures', {
        'assignment_id': assignments[key],
        'submitted_by': people[name]!['user_id'],
        'note': '[DEMO] Đã vệ sinh khu vực, kiểm tra dụng cụ và bàn giao ca.',
        'submitted_at': _stamp(submitted),
        'status': status,
        if (status != 'submitted')
          'reviewed_by': name == 'admin' ? manager : admin,
        if (status != 'submitted')
          'reviewed_at': _stamp(submitted.add(const Duration(minutes: 5))),
        'review_note': reviewNote,
      });
      await tx.insert('shift_closure_photos', {
        'closure_id': id,
        'file_url': 'asset:$closureSampleAsset',
        'captured_at': _stamp(submitted),
        'caption': 'Ảnh minh họa dữ liệu DEMO, không phải ảnh chụp thực tế.',
      });
    }

    for (var i = 0; i < 2; i++) {
      final day = historyStart.add(Duration(days: 1 + i * 2));
      final code = 'HISTORY_$i';
      await shift(
        code,
        at(day, 8),
        at(day, 16),
        people.keys.toList(),
        status: 'closed',
        completed: true,
      );
      for (final name in people.keys) {
        final key = '$code/$name';
        await worked(
          key,
          at(day, 8),
          at(day, 16),
          overtime: i == 1 && name == 'employee' ? 60 : 0,
        );
        await closure(key, 'approved');
      }
    }
    // Hai lần xác thực không thành công để kiểm tra lịch sử, không tính vào công.
    final first = assignments['HISTORY_0/employee']!;
    await tx.insert('attendance_events', {
      'assignment_id': first,
      'event_type': 'check_in',
      'occurred_at': _stamp(
        at(
          historyStart.add(const Duration(days: 1)),
          8,
        ).subtract(const Duration(minutes: 2)),
      ),
      'device_id': devices['employee'],
      'device_valid': 1,
      'gps_valid': 1,
      'wifi_valid': 0,
      'result': 'rejected',
      'rejection_reason': '[DEMO] Không kết nối đúng Wi-Fi chi nhánh.',
    });
    await tx.insert('attendance_events', {
      'assignment_id': first,
      'event_type': 'check_in',
      'occurred_at': _stamp(
        at(
          historyStart.add(const Duration(days: 1)),
          8,
        ).subtract(const Duration(minutes: 1)),
      ),
      'device_id': devices['employee'],
      'device_valid': 1,
      'gps_valid': 0,
      'wifi_valid': 1,
      'result': 'pending_review',
      'rejection_reason': '[DEMO] GPS thiếu chính xác, chờ kiểm tra.',
    });
    // Ca hôm qua: một ca sẵn sàng chụp ảnh, một báo cáo chờ duyệt, một bị từ chối.
    final yesterday = today.subtract(const Duration(days: 1));
    await shift('READY_CLOSE', at(yesterday, 8), at(yesterday, 16), [
      'employee',
      'manager',
    ], status: 'in_progress');
    await worked(
      'READY_CLOSE/employee',
      at(yesterday, 8),
      at(yesterday, 16),
      overtime: 30,
    );
    await worked('READY_CLOSE/manager', at(yesterday, 8), at(yesterday, 16));
    await closure('READY_CLOSE/manager', 'submitted');
    await shift(
      'RETRY_CLOSE',
      at(yesterday, 17),
      at(yesterday, 21),
      ['employee'],
      template: 'EVENING',
      status: 'in_progress',
    );
    await worked(
      'RETRY_CLOSE/employee',
      at(yesterday, 17),
      at(yesterday, 21),
      breakMinutes: 15,
    );
    await closure(
      'RETRY_CLOSE/employee',
      'rejected',
      reviewNote: '[DEMO] Cần bổ sung ghi chú và chụp ảnh bàn giao rõ hơn.',
    );
    await shift(
      'PENDING_CLOSE',
      at(yesterday, 21).add(const Duration(minutes: 30)),
      at(yesterday, 23),
      ['employee'],
      template: 'SHORT',
      status: 'in_progress',
    );
    await worked(
      'PENDING_CLOSE/employee',
      at(yesterday, 21).add(const Duration(minutes: 30)),
      at(yesterday, 23),
      breakMinutes: 0,
    );
    await closure('PENDING_CLOSE/employee', 'submitted');
    // Ca đang diễn ra không có sự kiện accepted: vẫn phải qua kiểm tra thật.
    await shift(
      'LIVE',
      now.subtract(const Duration(minutes: 15)),
      now.add(const Duration(hours: 7, minutes: 45)),
      ['employee', 'manager'],
      template: null,
    );
    await shift(
      'UNASSIGNED',
      at(today.add(const Duration(days: 1)), 17),
      at(today.add(const Duration(days: 1)), 21),
      [],
      template: 'EVENING',
      extraCapacity: 2,
    );
    for (var i = 1; i <= 6; i++) {
      final day = today.add(Duration(days: i));
      await shift('FUTURE_$i', at(day, 8), at(day, 16), [
        i.isOdd ? 'employee' : 'manager',
      ]);
    }
    for (final request in [
      (1, 2, 'pending', 'pending'),
      (3, 4, 'accepted', 'pending'),
      (5, 6, 'rejected', 'rejected'),
    ]) {
      await tx.insert('shift_swap_requests', {
        'from_assignment_id': assignments['FUTURE_${request.$1}/employee'],
        'to_assignment_id': assignments['FUTURE_${request.$2}/manager'],
        'from_employee_id': people['employee']!['id'],
        'to_employee_id': people['manager']!['id'],
        'requested_by': employee,
        'reason': '[DEMO] Xin đổi ca do lịch cá nhân.',
        'counterpart_status': request.$3,
        'status': request.$4,
        'created_at': _stamp(now),
        if (request.$4 == 'rejected') 'reviewed_by': admin,
        if (request.$4 == 'rejected') 'reviewed_at': _stamp(now),
      });
    }
    final annual = (await tx.query(
      'leave_types',
      where: 'code=?',
      whereArgs: ['ANNUAL'],
    )).single['id'];
    for (final item in [
      ('employee', 'pending', 10),
      ('manager', 'approved', 11),
      ('employee', 'rejected', 12),
    ]) {
      final day = today.add(Duration(days: item.$3));
      // Nếu đã có số dư thật, để đơn DEMO chờ duyệt thay vì tự trừ số dư đó.
      final status =
          item.$2 == 'approved' && !newAnnualBalances.contains(item.$1)
          ? 'pending'
          : item.$2;
      await tx.insert('leave_requests', {
        'employee_id': people[item.$1]!['id'],
        'leave_type_id': annual,
        'starts_at': _stamp(at(day, 8)),
        'ends_at': _stamp(at(day, 16)),
        'requested_minutes': 480,
        'reason': '[DEMO] Nghỉ giải quyết việc gia đình.',
        'status': status,
        if (status != 'pending') 'reviewed_by': admin,
        if (status != 'pending') 'reviewed_at': _stamp(now),
      });
    }
    if (newAnnualBalances.contains('manager')) {
      await tx.rawUpdate(
        'UPDATE leave_balances SET used_minutes=used_minutes+480 WHERE employee_id=? AND leave_type_id=? AND year=?',
        [people['manager']!['id'], annual, today.year],
      );
    }
    final adjustment = records['HISTORY_0/employee']!;
    final original = (await tx.query(
      'attendance_records',
      where: 'id=?',
      whereArgs: [adjustment],
    )).single;
    await tx.insert('attendance_adjustment_requests', {
      'attendance_id': adjustment,
      'requested_by': employee,
      'requested_check_in': original['check_in_at'],
      'requested_check_out': original['check_out_at'],
      'reason': '[DEMO] Xin kiểm tra lại giờ vào ca.',
      'status': 'pending',
    });
    final approvedRecord = records['HISTORY_1/employee']!;
    final approved = (await tx.query(
      'attendance_records',
      where: 'id=?',
      whereArgs: [approvedRecord],
    )).single;
    await tx.insert('attendance_adjustment_requests', {
      'attendance_id': approvedRecord,
      'requested_by': employee,
      'requested_check_in': approved['check_in_at'],
      'requested_check_out': approved['check_out_at'],
      'reason': '[DEMO] Đã đối chiếu và xác nhận lại giờ công.',
      'status': 'approved',
      'reviewed_by': admin,
      'reviewed_at': _stamp(now),
      'review_note': '[DEMO] Giữ nguyên công sau khi đối chiếu.',
    });
    await tx.update(
      'attendance_records',
      {'status': 'adjusted'},
      where: 'id=?',
      whereArgs: [approvedRecord],
    );
    for (final event in [
      ('employee', 3, 'Hoàn thành tốt ca làm'),
      ('employee', -1, 'Đi muộn trong tình huống mẫu'),
      ('manager', 5, 'Điều phối ca tốt'),
      ('admin', 2, 'Hỗ trợ đội ngũ'),
    ]) {
      await tx.insert('star_events', {
        'employee_id': people[event.$1]!['id'],
        'stars_delta': event.$2,
        'reason': '[DEMO] ${event.$3}',
        'awarded_by': event.$1 == 'admin' ? manager : admin,
        'created_at': _stamp(now),
      });
    }
    const steps = [
      'Kiểm tra kỳ lương và hồ sơ',
      'Kiểm tra hợp đồng và đơn giá',
      'Tổng hợp công hợp lệ',
      'Tính lương thường và tăng ca',
      'Tổng hợp khoản cộng/trừ',
      'Kiểm tra và lưu phiếu lương',
    ];
    // Tính số tiền từ chính các bản ghi công vừa tạo, không chèn tổng lương tùy ý.
    for (final period in [
      ('DEMO_PAID', historyStart, historyEnd, true),
      ('DEMO_OPEN', openStart, openEnd, false),
    ]) {
      final id = await tx.insert('payroll_periods', {
        'code': period.$1,
        'starts_on': _date(period.$2),
        'ends_on': _date(period.$3),
        'status': period.$4 ? 'paid' : 'calculating',
        if (period.$4) 'approved_by': admin,
        if (period.$4) 'approved_at': _stamp(at(historyEnd, 18)),
      });
      await tx.insert('payroll_policies', {
        'period_id': id,
        'overtime_multiplier': 1.5,
        'created_by': manager,
      });
      for (final person in people.entries) {
        final rows = await tx.rawQuery(
          "SELECT r.* FROM attendance_records r JOIN shift_assignments a ON a.id=r.assignment_id JOIN shifts s ON s.id=a.shift_id WHERE a.employee_id=? AND r.status IN ('present','adjusted') AND date(s.starts_at,'+7 hours') BETWEEN ? AND ?",
          [person.value['id'], _date(period.$2), _date(period.$3)],
        );
        var regular = 0, ot = 0;
        for (final record in rows) {
          ot += record['overtime_minutes'] as int;
          regular +=
              (record['worked_minutes'] as int) -
              (record['overtime_minutes'] as int);
        }
        final perMinute = rates[person.key]! / 12480;
        final base = (regular * perMinute).round();
        final overtime = (ot * perMinute * 1.5).round();
        final pay = await tx.insert('payslips', {
          'period_id': id,
          'employee_id': person.value['id'],
          'contract_id': contracts[person.key],
          'regular_minutes': regular,
          'overtime_minutes': ot,
          'base_pay_vnd': base,
          'overtime_pay_vnd': overtime,
          'status': period.$4 ? 'paid' : 'draft',
          'calculated_at': _stamp(now),
          if (period.$4) 'approved_by': admin,
          if (period.$4) 'approved_at': _stamp(at(historyEnd, 18)),
          if (period.$4) 'paid_at': _stamp(at(historyEnd, 19)),
        });
        for (final item in [
          ('MEAL', 'Phụ cấp ăn', 'allowance', 100000),
          ('PERFORMANCE', 'Thưởng hiệu suất', 'bonus', 50000),
          ('INSURANCE', 'Bảo hiểm mẫu', 'insurance', 30000),
          ('TAX', 'Thuế mẫu', 'tax', 10000),
          ('OTHER', 'Khấu trừ mẫu', 'deduction', 5000),
        ]) {
          await tx.insert('payslip_items', {
            'payslip_id': pay,
            'code': item.$1,
            'name': item.$2,
            'item_type': item.$3,
            'amount_vnd': item.$4,
            'note':
                '[DEMO] Số tiền minh họa, không phải quy định thuế/bảo hiểm.',
          });
        }
        final totals = (await tx.query(
          'v_payslip_totals',
          where: 'id=?',
          whereArgs: [pay],
        )).single;
        final details = [
          '[DEMO] Kỳ ${period.$1} • ${person.value['employee_code']}',
          'Hợp đồng DEMO_CT_${person.key.toUpperCase()} • ${perMinute.toStringAsFixed(2)} VND/phút',
          '$regular phút thường, $ot phút tăng ca',
          '$base VND + $overtime VND; hệ số 1.5',
          'Cộng 150000 VND, trừ 45000 VND',
          'Phiếu #$pay • thực lĩnh ${totals['net_pay_vnd']} VND',
        ];
        for (var i = 0; i < 6; i++) {
          await tx.insert('employee_payroll_checks', {
            'period_id': id,
            'employee_id': person.value['id'],
            'step_number': i + 1,
            'name': steps[i],
            'detail': details[i],
            'checked_at': _stamp(now),
            'source_hash': i == 5
                ? await payrollSourceHash(
                    tx,
                    id,
                    person.value['id'] as int,
                    contracts[person.key]!,
                  )
                : '',
          });
        }
      }
      for (var i = 0; i < 6; i++) {
        await tx.insert('payroll_calculation_steps', {
          'period_id': id,
          'step_number': i + 1,
          'name': steps[i],
          'status': 'completed',
          'executed_by': manager,
          'executed_at': _stamp(now),
          'detail': '[DEMO] Đã kiểm tra 3 hồ sơ mẫu.',
        });
      }
    }
    for (final message in [
      (
        'Lịch ca DEMO đã sẵn sàng',
        'Mở lịch ca để thử điểm danh, đổi ca và đóng ca.',
        'schedule',
      ),
      (
        'Phiếu lương mẫu',
        'Đã có kỳ DEMO_PAID và DEMO_OPEN để xem/tính lại.',
        'payroll',
      ),
      (
        'Cấu hình thật trước khi điểm danh',
        'GPS/Wi-Fi và mã thiết bị DEMO không thay cho cấu hình, thiết bị thật.',
        'system',
      ),
    ]) {
      final id = await tx.insert('notifications', {
        'title': message.$1,
        'body': '[DEMO] ${message.$2}',
        'notification_type': message.$3,
        'created_by': admin,
        'created_at': _stamp(now),
      });
      for (final user in people.values) {
        await tx.insert('notification_recipients', {
          'notification_id': id,
          'user_id': user['user_id'],
        });
      }
    }
    await tx.insert('audit_logs', {
      'actor_user_id': admin,
      'action': featureSampleMarker,
      'entity_type': 'sample_dataset',
      'after_json': jsonEncode({
        'reference_utc': _stamp(now),
        'live_shift': 'DEMO LIVE',
        'tables': 34,
        'note':
            'Dữ liệu mẫu, không thay cấu hình bảo mật hoặc danh tính Google.',
      }),
      'created_at': _stamp(now),
    });
    return true;
  });
}

DateTime _utc(Object? value) =>
    DateTime.parse('${value.toString().replaceFirst(' ', 'T')}Z');
