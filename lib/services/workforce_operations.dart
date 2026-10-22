part of 'workforce_repository.dart';

String sqlTime(DateTime time) =>
    time.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
DateTime utcTime(Object? text) =>
    DateTime.parse('${text.toString().replaceFirst(' ', 'T')}Z');

/// M01/M03/M04/M05: luôn kiểm tra quyền từ database trước khi đọc/ghi.
/// Các thao tác nhiều bảng nằm trong transaction để tránh dữ liệu dở dang.
extension WorkforceOperations on WorkforceRepository {
  Future<RowData> _me(DatabaseExecutor db) async {
    await _require(db, 'profile.self');
    final rows = await db.query(
      'employees',
      where: "user_id=? AND status='active'",
      whereArgs: [session.userId],
    );
    if (rows.isEmpty) {
      throw const AuthException(
        'Tài khoản chưa được liên kết hồ sơ nhân viên đang làm việc.',
      );
    }
    return rows.single;
  }

  Future<void> _audit(
    DatabaseExecutor db,
    String action,
    String entity,
    int id, [
    Object? detail,
  ]) => db.insert('audit_logs', {
    'actor_user_id': session.userId,
    'action': action,
    'entity_type': entity,
    'entity_id': id,
    'after_json': jsonEncode(detail ?? {}),
  });
  Future<List<RowData>> branches() async {
    final db = await _open();
    await _require(db, 'employees.manage');
    return db.query('branches', orderBy: 'name');
  }

  Future<List<RowData>> allShifts() async {
    final db = await _open();
    await _require(db, 'shifts.manage');
    return db.rawQuery(
      'SELECT s.*,b.name AS branch_name,(SELECT COUNT(*) FROM shift_assignments a WHERE a.shift_id=s.id AND a.status<>?) AS assigned_count FROM shifts s JOIN branches b ON b.id=s.branch_id ORDER BY starts_at DESC',
      ['cancelled'],
    );
  }

  Future<int> createShift({
    required int branchId,
    required DateTime start,
    required DateTime end,
    int requiredStaff = 1,
    String note = '',
  }) async {
    if (!end.isAfter(start) || requiredStaff < 1) {
      throw const AuthException(
        'Giờ kết thúc phải sau giờ bắt đầu; số nhân viên phải lớn hơn 0.',
      );
    }
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'shifts.manage');
      final id = await tx.insert('shifts', {
        'branch_id': branchId,
        'starts_at': sqlTime(start),
        'ends_at': sqlTime(end),
        'required_staff': requiredStaff,
        'created_by': session.userId,
        'note': note,
      });
      await _audit(tx, 'shift.create', 'shifts', id);
      return id;
    });
  }

  Future<void> _available(
    DatabaseExecutor db,
    int employeeId,
    RowData shift, {
    List<int> ignoring = const [],
  }) async {
    final employees = await db.query(
      'employees',
      where: "id=? AND status='active'",
      whereArgs: [employeeId],
    );
    if (employees.isEmpty ||
        employees.single['branch_id'] != shift['branch_id']) {
      throw const AuthException(
        'Nhân viên phải đang làm việc và thuộc cùng chi nhánh.',
      );
    }
    if (!['scheduled', 'in_progress'].contains(shift['status'])) {
      throw const AuthException('Ca đã đóng hoặc hủy.');
    }
    final overlaps = await db.rawQuery(
      "SELECT a.id FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.employee_id=? AND a.status<>'cancelled' AND s.status<>'cancelled' AND s.starts_at<? AND s.ends_at>?",
      [employeeId, shift['ends_at'], shift['starts_at']],
    );
    if (overlaps.any((a) => !ignoring.contains(a['id']))) {
      throw const AuthException('Nhân viên bị trùng giờ ca.');
    }
    if ((await db.rawQuery(
      "SELECT id FROM leave_requests WHERE employee_id=? AND status='approved' AND starts_at<? AND ends_at>?",
      [employeeId, shift['ends_at'], shift['starts_at']],
    )).isNotEmpty) {
      throw const AuthException('Nhân viên đang nghỉ phép.');
    }
  }

  Future<void> assignShift(int shiftId, int employeeId) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'shifts.manage');
      final shift = (await tx.query(
        'shifts',
        where: 'id=?',
        whereArgs: [shiftId],
      )).firstOrNull;
      if (shift == null) throw const AuthException('Không tìm thấy ca.');
      await _available(tx, employeeId, shift);
      final count =
          (await tx.rawQuery(
                "SELECT COUNT(*) n FROM shift_assignments WHERE shift_id=? AND status<>'cancelled'",
                [shiftId],
              )).single['n']
              as int;
      if (count >= (shift['required_staff'] as int)) {
        throw const AuthException('Ca đã đủ nhân viên.');
      }
      final old = await tx.query(
        'shift_assignments',
        where: 'shift_id=? AND employee_id=?',
        whereArgs: [shiftId, employeeId],
      );
      final data = {
        'shift_id': shiftId,
        'employee_id': employeeId,
        'assigned_by': session.userId,
        'status': 'assigned',
      };
      final id = old.isEmpty
          ? await tx.insert('shift_assignments', data)
          : old.single['id'] as int;
      if (old.isNotEmpty) {
        await tx.update(
          'shift_assignments',
          data,
          where: 'id=?',
          whereArgs: [id],
        );
      }
      await _audit(tx, 'shift.assign', 'shift_assignments', id);
    });
  }

  Future<RowData> shiftDetail(int shiftId) async {
    final db = await _open();
    final managing = await _can(db, 'shifts.manage');
    if (!managing) {
      await _require(db, 'schedule.self');
      final me = await _me(db);
      if ((await db.query(
        'shift_assignments',
        where: "shift_id=? AND employee_id=? AND status<>'cancelled'",
        whereArgs: [shiftId, me['id']],
      )).isEmpty) {
        throw const AuthException('Bạn không thuộc ca này.');
      }
    }
    final rows = await db.rawQuery(
      'SELECT s.*, b.name AS branch_name, b.latitude, b.longitude, b.geofence_radius_m FROM shifts s JOIN branches b ON b.id=s.branch_id WHERE s.id=?',
      [shiftId],
    );
    if (rows.isEmpty) throw const AuthException('Không tìm thấy ca.');
    final roster = await db.rawQuery(
      "SELECT a.id, a.status, e.employee_code, e.full_name, e.user_id, "
      "(SELECT event_type FROM attendance_events WHERE assignment_id=a.id AND result='accepted' ORDER BY occurred_at DESC LIMIT 1) AS last_event, "
      "(SELECT status FROM shift_closures WHERE assignment_id=a.id ORDER BY id DESC LIMIT 1) AS closure_status "
      "FROM shift_assignments a JOIN employees e ON e.id=a.employee_id WHERE a.shift_id=? AND a.status<>'cancelled'",
      [shiftId],
    );
    return {...rows.single, 'roster': roster};
  }

  /// Lấy danh sách lịch ca chi tiết của nhân viên hiện tại (hoặc nhân viên chỉ định nếu có quyền quản lý)
  Future<List<RowData>> employeeSchedule({int? employeeId}) async {
    final db = await _open();
    final managing = await _can(db, 'shifts.manage');
    int targetEmpId;
    if (employeeId != null && managing) {
      targetEmpId = employeeId;
    } else {
      await _require(db, 'schedule.self');
      final me = await _me(db);
      targetEmpId = me['id'] as int;
    }

    return db.rawQuery(
      '''
      SELECT
        a.id AS assignment_id,
        s.id AS shift_id,
        s.branch_id,
        s.starts_at,
        s.ends_at,
        s.status AS shift_status,
        s.required_staff,
        s.note AS shift_note,
        b.name AS branch_name,
        a.status AS assignment_status,
        (SELECT GROUP_CONCAT(e2.full_name, ', ')
         FROM shift_assignments a2
         JOIN employees e2 ON e2.id=a2.employee_id
         WHERE a2.shift_id=s.id AND a2.employee_id <> a.employee_id AND a2.status<>'cancelled') AS coworkers,
        (SELECT COUNT(*)
         FROM shift_assignments a3
         WHERE a3.shift_id=s.id AND a3.status<>'cancelled') AS total_assigned,
        (SELECT event_type
         FROM attendance_events
         WHERE assignment_id=a.id AND result='accepted'
         ORDER BY occurred_at DESC LIMIT 1) AS last_attendance_event,
        (SELECT status
         FROM shift_closures
         WHERE assignment_id=a.id
         ORDER BY id DESC LIMIT 1) AS closure_status
      FROM shift_assignments a
      JOIN shifts s ON s.id=a.shift_id
      JOIN branches b ON b.id=s.branch_id
      WHERE a.employee_id=? AND a.status<>'cancelled'
      ORDER BY s.starts_at DESC
      ''',
      [targetEmpId],
    );
  }

  /// Danh sách loại nghỉ phép có trong hệ thống
  Future<List<RowData>> leaveTypes() async {
    final db = await _open();
    await _require(db, 'schedule.self');
    return db.query('leave_types', orderBy: 'name');
  }

  /// Yêu cầu nghỉ phép của nhân viên hiện tại
  Future<List<RowData>> employeeLeaveRequests() async {
    final db = await _open();
    await _require(db, 'schedule.self');
    final me = await _me(db);
    return db.rawQuery(
      '''
      SELECT l.*, t.name AS leave_type_name
      FROM leave_requests l
      JOIN leave_types t ON t.id=l.leave_type_id
      WHERE l.employee_id=?
      ORDER BY l.starts_at DESC
      ''',
      [me['id']],
    );
  }

  /// Tạo yêu cầu nghỉ phép mới
  Future<void> createLeaveRequest({
    required int leaveTypeId,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    if (!end.isAfter(start)) {
      throw const AuthException(
        'Thời gian kết thúc phải sau thời gian bắt đầu.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const AuthException('Vui lòng nhập lý do nghỉ phép.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'schedule.self');
      final me = await _me(tx);
      final minutes = end.difference(start).inMinutes;
      if (minutes <= 0) {
        throw const AuthException('Thời gian nghỉ không hợp lệ.');
      }
      await tx.insert('leave_requests', {
        'employee_id': me['id'],
        'leave_type_id': leaveTypeId,
        'starts_at': sqlTime(start),
        'ends_at': sqlTime(end),
        'requested_minutes': minutes,
        'reason': reason.trim(),
        'status': 'pending',
      });
    });
  }

  Future<RowData> attendanceContext(int assignmentId) async {
    final db = await _open();
    await _require(db, 'attendance.self');
    final me = await _me(db);
    final rows = await db.rawQuery(
      "SELECT a.id AS assignment_id,s.*,b.latitude,b.longitude,b.geofence_radius_m,b.require_gps,b.require_wifi,b.require_registered_device FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id WHERE a.id=? AND a.employee_id=? AND a.status='assigned'",
      [assignmentId, me['id']],
    );
    if (rows.isEmpty) {
      throw const AuthException('Phân ca không hợp lệ hoặc không thuộc bạn.');
    }
    return rows.single;
  }

  Future<void> registerDevice(AttendanceEvidence evidence) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'attendance.self');
      final me = await _me(tx);
      final existing = await tx.query(
        'employee_devices',
        where: 'device_identifier=?',
        whereArgs: [evidence.deviceIdentifier],
      );
      if (existing.isNotEmpty) {
        if (existing.single['employee_id'] != me['id'] ||
            existing.single['revoked_at'] != null) {
          throw const AuthException(
            'Thiết bị đã đăng ký cho tài khoản khác hoặc bị thu hồi.',
          );
        }
        return;
      }
      await tx.insert('employee_devices', {
        'employee_id': me['id'],
        'device_identifier': evidence.deviceIdentifier,
        'platform': evidence.platform,
      });
    });
  }

  Future<List<RowData>> devices() async {
    final db = await _open();
    await _require(db, 'attendance.review');
    final scope = await _attendanceScope(db);
    return db.rawQuery(
      'SELECT d.*,e.full_name FROM employee_devices d JOIN employees e ON e.id=d.employee_id ${scope == null ? '' : 'WHERE e.branch_id=?'} ORDER BY d.id DESC',
      scope == null ? [] : [scope],
    );
  }

  Future<void> approveDevice(int deviceId, {bool revoke = false}) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'attendance.review');
      final d = (await tx.query(
        'employee_devices',
        where: 'id=?',
        whereArgs: [deviceId],
      )).firstOrNull;
      if (d == null) throw const AuthException('Không tìm thấy thiết bị.');
      final employee = (await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [d['employee_id']],
      )).single;
      await _requireAttendanceBranch(tx, employee['branch_id'] as int);
      final own = await tx.query(
        'employees',
        where: 'id=? AND user_id=?',
        whereArgs: [d['employee_id'], session.userId],
      );
      if (own.isNotEmpty) {
        throw const AuthException('Không thể tự duyệt thiết bị của mình.');
      }
      await tx.update(
        'employee_devices',
        {
          'approved_by': revoke ? null : session.userId,
          'revoked_at': revoke ? sqlTime(DateTime.now()) : null,
        },
        where: 'id=?',
        whereArgs: [deviceId],
      );
      await _audit(tx, 'device.review', 'employee_devices', deviceId);
      await _notify(
        tx,
        await _employeeUsers(tx, [d['employee_id'] as int]),
        'Thiết bị điểm danh',
        revoke
            ? 'Thiết bị đã bị thu hồi quyền điểm danh.'
            : 'Thiết bị đã được duyệt.',
        'employee_devices',
        deviceId,
      );
    });
  }

  Future<void> configureBranch(
    int branchId, {
    required double latitude,
    required double longitude,
    required int radius,
    required String ssid,
    required String bssid,
    bool? requireOvertimeApproval,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180 ||
        radius <= 0 ||
        ssid.trim().isEmpty ||
        !RegExp(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$').hasMatch(bssid)) {
      throw const AuthException(
        'Tọa độ, bán kính hoặc BSSID Wi-Fi không hợp lệ.',
      );
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'employees.manage');
      await _requireAttendanceBranch(tx, branchId);
      if (requireOvertimeApproval != null && !await _attendanceIsAdmin(tx)) {
        throw const AuthException(
          'Chỉ Admin được thay đổi chính sách tăng ca.',
        );
      }
      await tx.update(
        'branches',
        {
          'latitude': latitude,
          'longitude': longitude,
          'geofence_radius_m': radius,
          if (requireOvertimeApproval != null)
            'require_overtime_approval': requireOvertimeApproval ? 1 : 0,
        },
        where: 'id=?',
        whereArgs: [branchId],
      );
      await tx.insert('branch_wifi', {
        'branch_id': branchId,
        'ssid': ssid.trim(),
        'bssid': bssid.toLowerCase(),
        'is_active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Read-only preflight; final confirmation validates again in its transaction.
  Future<RowData> inspectAttendance(
    int assignmentId,
    AttendanceEvidence evidence, {
    DateTime? now,
  }) async {
    final context = await attendanceContext(assignmentId);
    final db = await _open();
    final me = await _me(db);
    return _validateAttendanceEvidence(
      db,
      context,
      me['id'] as int,
      evidence,
      (now ?? DateTime.now()).toUtc(),
    );
  }

  Future<RowData> _validateAttendanceEvidence(
    DatabaseExecutor tx,
    RowData s,
    int employeeId,
    AttendanceEvidence evidence,
    DateTime clock,
  ) async {
    final ds = await tx.query(
      'employee_devices',
      where: 'device_identifier=? AND employee_id=? AND revoked_at IS NULL AND approved_by IS NOT NULL',
      whereArgs: [evidence.deviceIdentifier, employeeId],
    );
    final deviceValid = ds.isNotEmpty;
    final registrations = await tx.query(
      'employee_devices',
      where: 'device_identifier=?',
      whereArgs: [evidence.deviceIdentifier],
    );
    final registration = registrations.firstOrNull;
    final deviceStatus = registration == null
        ? 'unregistered'
        : registration['employee_id'] != employeeId
        ? 'another_employee'
        : registration['revoked_at'] != null
        ? 'revoked'
        : registration['approved_by'] == null
        ? 'pending'
        : 'approved';
    var gpsValid = false;
    double? distanceMeters;
    if (s['latitude'] != null &&
        s['longitude'] != null &&
        evidence.latitude != null &&
        evidence.longitude != null &&
        evidence.accuracy != null &&
        evidence.latitude!.isFinite &&
        evidence.latitude!.abs() <= 90 &&
        evidence.longitude!.isFinite &&
        evidence.longitude!.abs() <= 180 &&
        evidence.accuracy!.isFinite &&
        !evidence.mocked) {
      final lat1 = (s['latitude'] as num).toDouble() * math.pi / 180;
      final lat2 = evidence.latitude! * math.pi / 180;
      final dl = lat2 - lat1;
      final dn =
          (evidence.longitude! - (s['longitude'] as num)) * math.pi / 180;
      final a =
          math.pow(math.sin(dl / 2), 2) +
          math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dn / 2), 2);
      final distance =
          6371000 *
          2 *
          math.atan2(
            math.sqrt(a.toDouble().clamp(0, 1)),
            math.sqrt((1 - a).toDouble().clamp(0, 1)),
          );
      distanceMeters = distance;
      gpsValid =
          distance <= (s['geofence_radius_m'] as int) &&
          evidence.accuracy! >= 0 &&
          evidence.accuracy! <= math.min(100, s['geofence_radius_m'] as int);
    }
    final wifi = evidence.bssid == null || evidence.ssid == null
        ? <RowData>[]
        : await tx.query(
            'branch_wifi',
            where: 'branch_id=? AND lower(bssid)=? AND ssid=? AND is_active=1',
            whereArgs: [
              s['branch_id'],
              evidence.bssid?.toLowerCase(),
              evidence.ssid,
            ],
          );
    final wifiValid = wifi.isNotEmpty;
    final failures = [
      if (s['require_registered_device'] == 1 && !deviceValid)
        'Thiết bị chưa được quản lý duyệt',
      if (s['require_gps'] == 1 && !gpsValid)
        'GPS ngoài phạm vi, thiếu chính xác hoặc vị trí giả',
      if (s['require_wifi'] == 1 && !wifiValid) 'Wi-Fi không đúng chi nhánh',
      if (clock.difference(evidence.collectedAt.toUtc()).abs() >
          const Duration(minutes: 2))
        'Dữ liệu xác thực đã quá hạn',
    ];
    final accepted = failures.isEmpty;
    return {
      'accepted': accepted,
      'device_valid': deviceValid,
      'device_status': deviceStatus,
      'registration_id': registration?['id'],
      'gps_valid': gpsValid,
      'wifi_valid': wifiValid,
      'device_ok': s['require_registered_device'] != 1 || deviceValid,
      'gps_ok': s['require_gps'] != 1 || gpsValid,
      'wifi_ok': s['require_wifi'] != 1 || wifiValid,
      'fresh':
          clock.difference(evidence.collectedAt.toUtc()).abs() <=
          const Duration(minutes: 2),
      'device_id': ds.firstOrNull?['id'],
      'distance_m': distanceMeters,
      'radius_m': s['geofence_radius_m'],
      'failures': failures,
    };
  }

  /// Đối chiếu chủ ca, thiết bị đã duyệt, GPS, Wi-Fi và độ mới bằng chứng.
  /// Lần bị từ chối vẫn được lưu; chỉ lần accepted mới cập nhật bảng công.
  Future<RowData> recordAttendance(
    int assignmentId,
    String type,
    AttendanceEvidence evidence, {
    DateTime? now,
  }) async {
    if (!['check_in', 'check_out'].contains(type)) {
      throw const AuthException('Loại điểm danh không hợp lệ.');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'attendance.self');
      final me = await _me(tx);
      final rows = await tx.rawQuery(
        "SELECT a.id AS assignment_id,s.*,b.latitude,b.longitude,b.geofence_radius_m,b.require_gps,b.require_wifi,b.require_registered_device,COALESCE(t.break_minutes,0) break_minutes,COALESCE(t.late_grace_minutes,0) late_grace_minutes FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id LEFT JOIN shift_templates t ON t.id=s.template_id WHERE a.id=? AND a.employee_id=? AND a.status='assigned'",
        [assignmentId, me['id']],
      );
      if (rows.isEmpty) {
        throw const AuthException('Phân ca không thuộc bạn hoặc đã hoàn tất.');
      }
      final s = rows.single;
      if (!['scheduled', 'in_progress'].contains(s['status'])) {
        throw const AuthException('Ca đã đóng/hủy.');
      }
      final previous = await tx.query(
        'attendance_events',
        where: "assignment_id=? AND result='accepted'",
        whereArgs: [assignmentId],
      );
      if (previous.any((r) => r['event_type'] == type)) {
        throw const AuthException('Bạn đã xác nhận lần điểm danh này.');
      }
      if (type == 'check_out' &&
          !previous.any((r) => r['event_type'] == 'check_in')) {
        throw const AuthException('Cần vào ca trước khi ra ca.');
      }
      final start = utcTime(s['starts_at']);
      final end = utcTime(s['ends_at']);
      if (clock.isBefore(start.subtract(const Duration(hours: 1))) ||
          clock.isAfter(end.add(const Duration(hours: 12))) ||
          (type == 'check_in' && clock.isAfter(end))) {
        throw const AuthException(
          'Ngoài khoảng giờ cho phép điểm danh ca này.',
        );
      }
      final checks = await _validateAttendanceEvidence(
        tx,
        s,
        me['id'] as int,
        evidence,
        clock,
      );
      final deviceValid = checks['device_valid'] == true;
      final gpsValid = checks['gps_valid'] == true;
      final wifiValid = checks['wifi_valid'] == true;
      final accepted = checks['accepted'] == true;
      final failures = checks['failures'] as List<String>;
      final eventId = await tx.insert('attendance_events', {
        'assignment_id': assignmentId,
        'event_type': type,
        'occurred_at': sqlTime(clock),
        'device_id': checks['device_id'],
        'latitude': evidence.latitude,
        'longitude': evidence.longitude,
        'gps_accuracy_m': evidence.accuracy,
        'wifi_ssid': evidence.ssid,
        'wifi_bssid': evidence.bssid,
        'device_valid': deviceValid ? 1 : 0,
        'gps_valid': gpsValid ? 1 : 0,
        'wifi_valid': wifiValid ? 1 : 0,
        'result': accepted ? 'accepted' : 'rejected',
        'rejection_reason': accepted ? null : failures.join('; '),
        'confirmed_at': accepted ? sqlTime(clock) : null,
      });
      if (accepted) {
        await _applyAttendanceRecord(tx, s, assignmentId, type, clock);
      }
      return {
        'id': eventId,
        'accepted': accepted,
        'message': accepted
            ? 'Đã xác nhận ${type == 'check_in' ? 'vào ca' : 'ra ca'}'
            : failures.join('\n'),
      };
    });
  }

  Future<void> _applyAttendanceRecord(
    DatabaseExecutor tx,
    RowData s,
    int assignmentId,
    String type,
    DateTime clock,
  ) async {
    await _ensureAttendanceEditable(tx, assignmentId);
    final start = utcTime(s['starts_at']);
    final end = utcTime(s['ends_at']);
    if (type == 'check_in') {
      final late = math.max(
        0,
        clock.difference(start).inMinutes - (s['late_grace_minutes'] as int),
      );
      final current = (await tx.query(
        'attendance_records',
        where: 'assignment_id=?',
        whereArgs: [assignmentId],
      )).firstOrNull;
      final values = <String, Object?>{
        'assignment_id': assignmentId,
        'check_in_at': sqlTime(clock),
        'late_minutes': late,
        'status': 'present',
      };
      if (current == null) {
        await tx.insert('attendance_records', values);
      } else {
        await tx.update(
          'attendance_records',
          values,
          where: 'id=?',
          whereArgs: [current['id']],
        );
      }
      await tx.update(
        'shifts',
        {'status': 'in_progress'},
        where: 'id=?',
        whereArgs: [s['id']],
      );
    } else {
      final record = (await tx.query(
        'attendance_records',
        where: 'assignment_id=?',
        whereArgs: [assignmentId],
      )).single;
      final inAt = utcTime(record['check_in_at']);
      if (clock.isBefore(inAt)) {
        throw const AuthException('Giờ ra ca trước giờ vào ca.');
      }
      final worked = math.max(
        0,
        clock.difference(inAt).inMinutes - (s['break_minutes'] as int),
      );
      final planned =
          end.difference(start).inMinutes - (s['break_minutes'] as int);
      await tx.update(
        'attendance_records',
        {
          'check_out_at': sqlTime(clock),
          'worked_minutes': worked,
          'overtime_minutes': math.max(0, worked - planned),
        },
        where: 'id=?',
        whereArgs: [record['id']],
      );
    }
    await _refreshAttendanceMetrics(tx, assignmentId);
  }

  Future<List<RowData>> attendanceHistory() async {
    final db = await _open();
    final managing = await _can(db, 'attendance.review');
    final scope = managing ? await _attendanceScope(db) : null;
    if (!managing) await _require(db, 'attendance.self');
    return db.rawQuery(
      'SELECT ev.*,COALESCE(sender.full_name,e.full_name) full_name FROM attendance_events ev JOIN shift_assignments a ON a.id=ev.assignment_id JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id LEFT JOIN employees sender ON sender.user_id=ev.submitted_by ${managing
          ? scope == null
                ? ''
                : 'WHERE s.branch_id=? '
          : 'WHERE ev.submitted_by=? OR (ev.submitted_by IS NULL AND e.user_id=?) '}ORDER BY ev.occurred_at DESC',
      managing
          ? scope == null
                ? []
                : [scope]
          : [session.userId, session.userId],
    );
  }

  Future<List<RowData>> swapOptions(int assignmentId) async {
    final db = await _open();
    await _require(db, 'swaps.self');
    final me = await _me(db);
    final from = (await txOwnAssignment(db, assignmentId, me['id'] as int));
    return db.rawQuery(
      "SELECT a.id,s.starts_at,s.ends_at,e.full_name FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN employees e ON e.id=a.employee_id WHERE a.employee_id<>? AND a.status='assigned' AND s.status='scheduled' AND s.branch_id=? AND s.starts_at>? ORDER BY s.starts_at",
      [me['id'], from['branch_id'], sqlTime(DateTime.now())],
    );
  }

  Future<RowData> txOwnAssignment(
    DatabaseExecutor db,
    int id,
    int employeeId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT a.*,s.starts_at,s.ends_at,s.branch_id FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.id=? AND a.employee_id=?',
      [id, employeeId],
    );
    if (rows.isEmpty) throw const AuthException('Phân ca không thuộc bạn.');
    return rows.single;
  }

  Future<void> requestSwap(int from, int to, String reason) async {
    if (reason.trim().isEmpty || from == to) {
      throw const AuthException('Chọn ca khác và nhập lý do.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'swaps.self');
      final me = await _me(tx);
      final own = await txOwnAssignment(tx, from, me['id'] as int);
      final target = (await tx.rawQuery(
        "SELECT a.*,s.starts_at,s.branch_id FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.id=? AND a.status='assigned' AND s.status='scheduled'",
        [to],
      )).firstOrNull;
      if (target == null ||
          target['employee_id'] == me['id'] ||
          target['branch_id'] != own['branch_id'] ||
          utcTime(target['starts_at']).isBefore(DateTime.now().toUtc()) ||
          utcTime(own['starts_at']).isBefore(DateTime.now().toUtc())) {
        throw const AuthException(
          'Chỉ đổi ca tương lai với nhân viên khác cùng chi nhánh.',
        );
      }
      final requestId = await tx.insert('shift_swap_requests', {
        'from_assignment_id': from,
        'to_assignment_id': to,
        'requested_by': session.userId,
        'from_employee_id': own['employee_id'],
        'to_employee_id': target['employee_id'],
        'reason': reason.trim(),
      });
      await _notify(
        tx,
        await _employeeUsers(tx, [target['employee_id'] as int]),
        'Yêu cầu đổi ca mới',
        reason.trim(),
        'shift_swap_requests',
        requestId,
      );
    });
  }

  Future<List<RowData>> swaps() async {
    final db = await _open();
    final managing = await _can(db, 'swaps.review');
    if (!managing) await _require(db, 'swaps.self');
    return db.rawQuery(
      'SELECT r.*,f.full_name AS from_name,t.full_name AS to_name,tf.user_id AS target_user_id,sf.starts_at AS from_start,st.starts_at AS to_start FROM shift_swap_requests r JOIN shift_assignments af ON af.id=r.from_assignment_id JOIN shift_assignments at ON at.id=r.to_assignment_id JOIN employees f ON f.id=r.from_employee_id JOIN employees t ON t.id=r.to_employee_id JOIN employees tf ON tf.id=r.to_employee_id JOIN shifts sf ON sf.id=af.shift_id JOIN shifts st ON st.id=at.shift_id ${managing ? '' : 'WHERE r.requested_by=? OR tf.user_id=? '}ORDER BY r.id DESC',
      managing ? [] : [session.userId, session.userId],
    );
  }

  /// Người nhận phản hồi trước; quản lý không tham gia mới được duyệt.
  /// Chuyển cả hai phân ca nguyên tử và giữ nguyên ID để bảo toàn khóa ngoại.
  Future<void> respondSwap(int id, bool accept, {bool review = false}) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, review ? 'swaps.review' : 'swaps.self');
      final r = (await tx.query(
        'shift_swap_requests',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      if (r['status'] != 'pending') {
        throw const AuthException('Yêu cầu đã được xử lý.');
      }
      final a = (await tx.query(
        'shift_assignments',
        where: 'id=?',
        whereArgs: [r['from_assignment_id']],
      )).single;
      final b = (await tx.query(
        'shift_assignments',
        where: 'id=?',
        whereArgs: [r['to_assignment_id']],
      )).single;
      if (a['employee_id'] != r['from_employee_id'] ||
          b['employee_id'] != r['to_employee_id']) {
        throw const AuthException(
          'Người được phân ca đã thay đổi. Hãy tạo yêu cầu đổi ca mới.',
        );
      }
      if (!review) {
        final me = await _me(tx);
        if (b['employee_id'] != me['id'] ||
            r['counterpart_status'] != 'pending') {
          throw const AuthException('Chỉ người nhận được phản hồi một lần.');
        }
        await tx.update(
          'shift_swap_requests',
          {
            'counterpart_status': accept ? 'accepted' : 'rejected',
            if (!accept) 'status': 'rejected',
            if (!accept) 'reviewed_by': session.userId,
            if (!accept) 'reviewed_at': sqlTime(DateTime.now()),
          },
          where: 'id=?',
          whereArgs: [id],
        );
        await _notify(
          tx,
          [r['requested_by'] as int],
          'Phản hồi đổi ca',
          accept
              ? 'Người nhận đã đồng ý; yêu cầu đang chờ quản lý duyệt.'
              : 'Người nhận đã từ chối đổi ca.',
          'shift_swap_requests',
          id,
        );
        if (accept) {
          final participants = await _employeeUsers(tx, [
            r['from_employee_id'] as int,
            r['to_employee_id'] as int,
          ]);
          await _notify(
            tx,
            await _reviewers(tx, 'swaps.review', excluding: participants),
            'Đổi ca chờ duyệt',
            'Hai bên đã đồng ý đổi ca. Vui lòng kiểm tra yêu cầu.',
            'shift_swap_requests',
            id,
          );
        }
        return;
      }
      final involved = await tx.query(
        'employees',
        where: 'user_id=? AND id IN (?,?)',
        whereArgs: [session.userId, a['employee_id'], b['employee_id']],
      );
      if (involved.isNotEmpty || r['requested_by'] == session.userId) {
        throw const AuthException('Người tham gia không được tự duyệt đổi ca.');
      }
      if (accept) {
        if (r['counterpart_status'] != 'accepted' ||
            a['status'] != 'assigned' ||
            b['status'] != 'assigned') {
          throw const AuthException(
            'Cần người nhận đồng ý và hai phân ca còn hiệu lực.',
          );
        }
        if ((await tx.rawQuery(
          'SELECT id FROM attendance_events WHERE assignment_id IN (?,?)',
          [a['id'], b['id']],
        )).isNotEmpty) {
          throw const AuthException(
            'Ca đã có lịch sử điểm danh, không thể đổi.',
          );
        }
        final sa = (await tx.query(
          'shifts',
          where: 'id=?',
          whereArgs: [a['shift_id']],
        )).single;
        final sb = (await tx.query(
          'shifts',
          where: 'id=?',
          whereArgs: [b['shift_id']],
        )).single;
        if (utcTime(sa['starts_at']).isBefore(DateTime.now().toUtc()) ||
            utcTime(sb['starts_at']).isBefore(DateTime.now().toUtc())) {
          throw const AuthException('Ca đã bắt đầu.');
        }
        await _available(
          tx,
          b['employee_id'] as int,
          sa,
          ignoring: [a['id'] as int, b['id'] as int],
        );
        await _available(
          tx,
          a['employee_id'] as int,
          sb,
          ignoring: [a['id'] as int, b['id'] as int],
        );
        if (a['shift_id'] == b['shift_id']) {
          throw const AuthException('Hai phân ca phải thuộc hai ca khác nhau.');
        }
        await tx.update(
          'shift_assignments',
          {'employee_id': b['employee_id'], 'assigned_by': session.userId},
          where: 'id=?',
          whereArgs: [a['id']],
        );
        await tx.update(
          'shift_assignments',
          {'employee_id': a['employee_id'], 'assigned_by': session.userId},
          where: 'id=?',
          whereArgs: [b['id']],
        );
      }
      await tx.update(
        'shift_swap_requests',
        {
          'status': accept ? 'approved' : 'rejected',
          'reviewed_by': session.userId,
          'reviewed_at': sqlTime(DateTime.now()),
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await _notify(
        tx,
        [
          r['requested_by'] as int,
          ...await _employeeUsers(tx, [
            r['from_employee_id'] as int,
            r['to_employee_id'] as int,
          ]),
        ],
        'Kết quả duyệt đổi ca',
        accept
            ? 'Yêu cầu đã được duyệt. Lịch ca của bạn đã cập nhật.'
            : 'Yêu cầu đổi ca đã bị từ chối. Lịch ca được giữ nguyên.',
        'shift_swap_requests',
        id,
      );
    });
  }
}

/// M02/M06/M07: tiền lưu bằng VND nguyên, thời lượng lưu bằng phút.
extension WorkforcePayrollAndClosure on WorkforceRepository {
  /// Hash nguồn công/hợp đồng/khoản điều chỉnh để chặn duyệt kết quả đã cũ.
  Future<String> _paySource(
    DatabaseExecutor tx,
    int periodId,
    int employeeId,
    int contractId,
  ) => payrollSourceHash(tx, periodId, employeeId, contractId);
  Future<List<RowData>> periods() async {
    final db = await _open();
    await _require(db, 'payslips.self');
    return db.rawQuery(
      'SELECT p.*,pol.overtime_multiplier FROM payroll_periods p LEFT JOIN payroll_policies pol ON pol.period_id=p.id ORDER BY p.starts_on DESC',
    );
  }

  Future<int> createPeriod(
    String code,
    DateTime start,
    DateTime end,
    double multiplier,
  ) async {
    if (code.trim().isEmpty ||
        end.isBefore(start) ||
        !multiplier.isFinite ||
        multiplier < 1) {
      throw const AuthException('Kỳ lương hoặc hệ số tăng ca không hợp lệ.');
    }
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final id = await tx.insert('payroll_periods', {
        'code': code.trim(),
        'starts_on': sqlTime(start).substring(0, 10),
        'ends_on': sqlTime(end).substring(0, 10),
      });
      await tx.insert('payroll_policies', {
        'period_id': id,
        'overtime_multiplier': multiplier,
        'created_by': session.userId,
      });
      return id;
    });
  }

  Future<void> saveContract(
    int employeeId,
    String number,
    int monthlySalary,
    int standardMinutes,
    DateTime startsOn,
  ) async {
    if (number.trim().isEmpty || monthlySalary < 0 || standardMinutes <= 0) {
      throw const AuthException('Thông tin hợp đồng không hợp lệ.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'employees.manage');
      await tx.insert('contracts', {
        'employee_id': employeeId,
        'contract_number': number.trim(),
        'contract_type': 'indefinite',
        'start_date': startsOn.toIso8601String().substring(0, 10),
        'salary_basis': 'monthly',
        'base_salary_vnd': monthlySalary,
        'standard_minutes_per_month': standardMinutes,
        'status': 'active',
      });
    });
  }

  /// Nhân viên chỉ tính bản nháp của mình; quản lý tính toàn kỳ.
  /// Hệ số lấy từ chính sách kỳ đã nhập, không tự gán thuế hay phụ cấp.
  Future<RowData> calculatePay(int periodId, {int? employeeId}) async {
    final db = await _open();
    return db.transaction((tx) async {
      final managing = await _can(tx, 'payroll.manage');
      if (!managing) {
        await _require(tx, 'payslips.self');
        final me = await _me(tx);
        if (employeeId != null && employeeId != me['id']) {
          throw const AuthException('Chỉ tính phiếu lương của chính mình.');
        }
        employeeId = me['id'] as int;
      }
      final p = (await tx.rawQuery(
        'SELECT p.*,pol.overtime_multiplier FROM payroll_periods p JOIN payroll_policies pol ON pol.period_id=p.id WHERE p.id=?',
        [periodId],
      )).firstOrNull;
      if (p == null || ['approved', 'paid'].contains(p['status'])) {
        throw const AuthException(
          'Kỳ lương chưa có chính sách hoặc đã được chốt.',
        );
      }
      final employees = await tx.query(
        'employees',
        where: employeeId == null
            ? "status='active'"
            : "id=? AND status='active'",
        whereArgs: employeeId == null ? [] : [employeeId],
      );
      if (employees.isEmpty) {
        throw const AuthException('Không có nhân viên để tính lương.');
      }
      if (managing && employeeId == null) {
        final oldPays = await tx.query(
          'payslips',
          where: 'period_id=?',
          whereArgs: [periodId],
        );
        for (final old in oldPays.where(
          (pay) => !employees.any((e) => e['id'] == pay['employee_id']),
        )) {
          if (old['status'] != 'draft') {
            throw const AuthException('Không được xóa phiếu lương đã chốt.');
          }
          await tx.delete(
            'payslip_items',
            where: 'payslip_id=?',
            whereArgs: [old['id']],
          );
          await tx.delete(
            'employee_payroll_checks',
            where: 'period_id=? AND employee_id=?',
            whereArgs: [periodId, old['employee_id']],
          );
          await tx.delete('payslips', where: 'id=?', whereArgs: [old['id']]);
        }
      }
      final now = sqlTime(DateTime.now());
      var total = 0;
      const names = [
        'Kiểm tra kỳ lương và hồ sơ',
        'Kiểm tra hợp đồng và đơn giá',
        'Tổng hợp công hợp lệ',
        'Tính lương thường và tăng ca',
        'Tổng hợp khoản cộng/trừ',
        'Kiểm tra và lưu phiếu lương',
      ];
      for (final e in employees) {
        final contracts = await tx.rawQuery(
          "SELECT * FROM contracts WHERE employee_id=? AND status='active' AND start_date<=? AND (end_date IS NULL OR end_date>=?) ORDER BY start_date DESC,id DESC",
          [e['id'], p['starts_on'], p['ends_on']],
        );
        if (contracts.isEmpty) {
          throw AuthException(
            'Nhân viên ${e['full_name']} chưa có hợp đồng bao phủ kỳ lương.',
          );
        }
        final c = contracts.first;
        final existing = (await tx.query(
          'payslips',
          where: 'period_id=? AND employee_id=?',
          whereArgs: [periodId, e['id']],
        )).firstOrNull;
        if (existing != null && existing['status'] != 'draft') {
          throw const AuthException('Không được sửa phiếu lương đã chốt.');
        }
        final records = await tx.rawQuery(
          "SELECT r.* FROM attendance_records r JOIN shift_assignments a ON a.id=r.assignment_id JOIN shifts s ON s.id=a.shift_id WHERE a.employee_id=? AND r.status IN ('present','adjusted') AND r.check_out_at IS NOT NULL AND date(s.starts_at,'localtime') BETWEEN ? AND ?",
          [e['id'], p['starts_on'], p['ends_on']],
        );
        var regular = 0;
        var overtime = 0;
        for (final r in records) {
          overtime += r['overtime_minutes'] as int;
          final unpaidExtra =
              ['PENDING', 'REJECTED'].contains(r['overtime_status'])
              ? r['overtime_requested_minutes'] as int
              : 0;
          regular +=
              (r['worked_minutes'] as int) -
              (r['overtime_minutes'] as int) -
              unpaidExtra;
        }
        final perMinute = c['salary_basis'] == 'hourly'
            ? (c['hourly_rate_vnd'] as int) / 60
            : (c['base_salary_vnd'] as int) /
                  (c['standard_minutes_per_month'] as int);
        final base = (regular * perMinute).round();
        final ot = (overtime * perMinute * (p['overtime_multiplier'] as num))
            .round();
        final values = {
          'period_id': periodId,
          'employee_id': e['id'],
          'contract_id': c['id'],
          'regular_minutes': regular,
          'overtime_minutes': overtime,
          'base_pay_vnd': base,
          'overtime_pay_vnd': ot,
          'calculated_at': now,
          'status': 'draft',
        };
        final id = existing == null
            ? await tx.insert('payslips', values)
            : existing['id'] as int;
        if (existing != null) {
          await tx.update('payslips', values, where: 'id=?', whereArgs: [id]);
        }
        final totals = (await tx.query(
          'v_payslip_totals',
          where: 'id=?',
          whereArgs: [id],
        )).single;
        if ((totals['net_pay_vnd'] as int) < 0) {
          throw const AuthException(
            'Thực lĩnh âm, cần kiểm tra khoản khấu trừ.',
          );
        }
        final details = [
          'Kỳ ${p['code']} • ${e['employee_code']}',
          'Hợp đồng ${c['contract_number']} • ${perMinute.toStringAsFixed(2)} VND/phút',
          '$regular phút thường, $overtime phút tăng ca',
          '$base VND + $ot VND; hệ số ${p['overtime_multiplier']}',
          'Khấu trừ ${totals['deductions_vnd']} VND',
          'Phiếu #$id • thực lĩnh ${totals['net_pay_vnd']} VND',
        ];
        for (var i = 0; i < 6; i++) {
          await tx.insert('employee_payroll_checks', {
            'period_id': periodId,
            'employee_id': e['id'],
            'step_number': i + 1,
            'name': names[i],
            'detail': details[i],
            'checked_at': now,
            'source_hash': i == 5
                ? await _paySource(tx, periodId, e['id'] as int, c['id'] as int)
                : '',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        total += totals['net_pay_vnd'] as int;
      }
      if (managing && employeeId == null) {
        for (var i = 0; i < 6; i++) {
          await tx.insert('payroll_calculation_steps', {
            'period_id': periodId,
            'step_number': i + 1,
            'name': names[i],
            'status': 'completed',
            'executed_by': session.userId,
            'executed_at': now,
            'detail': 'Đã kiểm tra ${employees.length} nhân viên',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await tx.update(
          'payroll_periods',
          {'status': 'calculating'},
          where: 'id=?',
          whereArgs: [periodId],
        );
      }
      await _audit(tx, 'payroll.calculate', 'payroll_periods', periodId, {
        'employees': employees.length,
        'net': total,
      });
      return {
        'count': employees.length,
        'net': total,
        'message':
            'Đã hoàn tất 6 bước và lưu ${employees.length} phiếu lương nháp.',
      };
    });
  }

  Future<RowData> payslipDetail(int id) async {
    final db = await _open();
    final managing = await _can(db, 'payroll.manage');
    if (!managing) await _require(db, 'payslips.self');
    final rows = await db.rawQuery(
      'SELECT p.*,e.full_name FROM v_payslip_totals p JOIN employees e ON e.id=p.employee_id WHERE p.id=? ${managing ? '' : 'AND e.user_id=?'}',
      managing ? [id] : [id, session.userId],
    );
    if (rows.isEmpty) {
      throw const AuthException('Không có quyền xem phiếu lương này.');
    }
    return {
      ...rows.single,
      'items': await db.query(
        'payslip_items',
        where: 'payslip_id=?',
        whereArgs: [id],
      ),
      'checks': await db.query(
        'employee_payroll_checks',
        where: 'period_id=? AND employee_id=?',
        whereArgs: [rows.single['period_id'], rows.single['employee_id']],
        orderBy: 'step_number',
      ),
    };
  }

  Future<void> addPayItem(
    int payslipId,
    String code,
    String name,
    String type,
    int amount,
  ) async {
    if (code.trim().isEmpty ||
        name.trim().isEmpty ||
        amount < 0 ||
        ![
          'allowance',
          'bonus',
          'deduction',
          'tax',
          'insurance',
        ].contains(type)) {
      throw const AuthException('Khoản điều chỉnh không hợp lệ.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final pay = (await tx.query(
        'payslips',
        where: 'id=?',
        whereArgs: [payslipId],
      )).single;
      if (pay['status'] != 'draft') {
        throw const AuthException('Phiếu đã chốt không thể thay đổi.');
      }
      await tx.insert('payslip_items', {
        'payslip_id': payslipId,
        'code': code.trim(),
        'name': name.trim(),
        'item_type': type,
        'amount_vnd': amount,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.delete(
        'employee_payroll_checks',
        where: 'period_id=? AND employee_id=?',
        whereArgs: [pay['period_id'], pay['employee_id']],
      );
      await tx.delete(
        'payroll_calculation_steps',
        where: 'period_id=?',
        whereArgs: [pay['period_id']],
      );
    });
  }

  /// Chốt khi đủ 6 bước và nguồn dữ liệu vẫn khớp lần tính gần nhất.
  Future<void> approvePayroll(int periodId) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'payroll.manage');
      final p = (await tx.query(
        'payroll_periods',
        where: 'id=?',
        whereArgs: [periodId],
      )).single;
      if (p['status'] != 'calculating') {
        throw const AuthException(
          'Cần tính lại lương toàn kỳ trước khi duyệt.',
        );
      }
      final steps = await tx.query(
        'payroll_calculation_steps',
        where: "period_id=? AND status='completed'",
        whereArgs: [periodId],
      );
      if (steps.length != 6) {
        throw const AuthException('Chưa hoàn thành đủ 6 bước.');
      }
      final pays = await tx.query(
        'payslips',
        where: 'period_id=?',
        whereArgs: [periodId],
      );
      if (pays.isEmpty) throw const AuthException('Kỳ lương chưa có phiếu.');
      final activeEmployees = await tx.query(
        'employees',
        columns: ['id'],
        where: "status='active'",
      );
      if (pays.length != activeEmployees.length ||
          activeEmployees.any(
            (e) => !pays.any((pay) => pay['employee_id'] == e['id']),
          )) {
        throw const AuthException(
          'Danh sách nhân viên đã đổi. Cần tính lại toàn kỳ.',
        );
      }
      for (final pay in pays) {
        final check = (await tx.query(
          'employee_payroll_checks',
          where: 'period_id=? AND employee_id=? AND step_number=6',
          whereArgs: [periodId, pay['employee_id']],
        )).firstOrNull;
        if (check == null ||
            check['source_hash'] !=
                await _paySource(
                  tx,
                  periodId,
                  pay['employee_id'] as int,
                  pay['contract_id'] as int,
                )) {
          throw const AuthException(
            'Dữ liệu công/hợp đồng/phiếu lương đã đổi. Cần tính lại toàn kỳ trước khi duyệt.',
          );
        }
      }
      final now = sqlTime(DateTime.now());
      final recipients = await tx.rawQuery(
        'SELECT e.user_id FROM payslips p JOIN employees e ON e.id=p.employee_id WHERE p.period_id=? AND e.user_id IS NOT NULL',
        [periodId],
      );
      await _notify(
        tx,
        recipients.map((r) => r['user_id'] as int),
        'Bảng lương đã được duyệt',
        'Bạn có thể mở mục Thu nhập để xem phiếu lương.',
        'payroll_periods',
        periodId,
      );
      await tx.update(
        'payslips',
        {
          'status': 'approved',
          'approved_by': session.userId,
          'approved_at': now,
        },
        where: 'period_id=?',
        whereArgs: [periodId],
      );
      await tx.update(
        'payroll_periods',
        {
          'status': 'approved',
          'approved_by': session.userId,
          'approved_at': now,
        },
        where: 'id=?',
        whereArgs: [periodId],
      );
    });
  }

  Future<List<RowData>> stars() async {
    final db = await _open();
    final managing = await _can(db, 'stars.award');
    if (!managing) await _require(db, 'stars.self');
    return db.rawQuery(
      'SELECT v.* FROM v_employee_stars v JOIN employees e ON e.id=v.employee_id ${managing ? '' : 'WHERE e.user_id=?'} ORDER BY total_stars DESC',
      managing ? [] : [session.userId],
    );
  }

  Future<void> awardStars(int employeeId, int delta, String reason) async {
    if (delta == 0 || reason.trim().isEmpty) {
      throw const AuthException('Nhập số sao khác 0 và lý do.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'stars.award');
      if ((await tx.query(
        'employees',
        where: 'id=? AND user_id=?',
        whereArgs: [employeeId, session.userId],
      )).isNotEmpty) {
        throw const AuthException('Không thể tự tặng sao.');
      }
      await tx.insert('star_events', {
        'employee_id': employeeId,
        'stars_delta': delta,
        'reason': reason.trim(),
        'awarded_by': session.userId,
      });
    });
  }

  Future<List<RowData>> closures() async {
    final db = await _open();
    final managing = await _can(db, 'closures.review');
    if (!managing) await _require(db, 'closures.self');
    final rows = await db.rawQuery(
      'SELECT c.*,e.full_name FROM shift_closures c JOIN shift_assignments a ON a.id=c.assignment_id JOIN employees e ON e.id=a.employee_id ${managing ? '' : 'WHERE e.user_id=?'} ORDER BY c.id DESC',
      managing ? [] : [session.userId],
    );
    final result = <RowData>[];
    for (final row in rows) {
      result.add({
        ...row,
        'photos': await db.query(
          'shift_closure_photos',
          where: 'closure_id=?',
          whereArgs: [row['id']],
        ),
      });
    }
    return result;
  }

  /// Chỉ chủ phân ca đã check-out được gửi ảnh/ghi chú; cho gửi lại khi bị từ chối.
  Future<void> closeAssignment(
    int assignmentId,
    String note,
    String photoPath,
  ) async {
    if (note.trim().isEmpty ||
        !await File(photoPath).exists() ||
        await File(photoPath).length() == 0) {
      throw const AuthException('Cần ghi chú và ảnh chụp đóng ca.');
    }
    final header = await File(photoPath).readAsBytes();
    final jpeg =
        header.length >= 3 &&
        header[0] == 255 &&
        header[1] == 216 &&
        header[2] == 255;
    final png =
        header.length >= 8 &&
        header[0] == 137 &&
        header[1] == 80 &&
        header[2] == 78 &&
        header[3] == 71;
    if (!jpeg && !png) {
      throw const AuthException('File ảnh đóng ca phải là JPEG hoặc PNG.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'closures.self');
      final me = await _me(tx);
      final a = await txOwnAssignment(tx, assignmentId, me['id'] as int);
      if (a['status'] != 'assigned') {
        throw const AuthException('Phân ca không còn hiệu lực.');
      }
      final record = await tx.query(
        'attendance_records',
        where: 'assignment_id=? AND check_out_at IS NOT NULL',
        whereArgs: [assignmentId],
      );
      if (record.isEmpty) {
        throw const AuthException('Cần điểm danh ra ca trước khi đóng ca.');
      }
      final previous = await tx.query(
        'shift_closures',
        where: 'assignment_id=?',
        whereArgs: [assignmentId],
      );
      if (previous.isNotEmpty && previous.single['status'] != 'rejected') {
        throw const AuthException('Đã gửi báo cáo đóng ca.');
      }
      final values = <String, Object?>{
        'assignment_id': assignmentId,
        'submitted_by': session.userId,
        'note': note.trim(),
        'status': 'submitted',
        'submitted_at': sqlTime(DateTime.now()),
        'reviewed_by': null,
        'reviewed_at': null,
        'review_note': null,
      };
      final id = previous.isEmpty
          ? await tx.insert('shift_closures', values)
          : previous.single['id'] as int;
      if (previous.isNotEmpty) {
        await tx.update(
          'shift_closures',
          values,
          where: 'id=?',
          whereArgs: [id],
        );
      }
      await tx.insert('shift_closure_photos', {
        'closure_id': id,
        'file_url': photoPath,
        'captured_at': sqlTime(DateTime.now()),
      });
    });
  }

  /// Duyệt từng báo cáo; ca chung chỉ đóng sau khi hết phân ca chưa hoàn tất.
  Future<void> reviewClosure(int id, bool approve) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'closures.review');
      final c = (await tx.query(
        'shift_closures',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      if (c['submitted_by'] == session.userId || c['status'] != 'submitted') {
        throw const AuthException('Không thể tự duyệt hoặc duyệt lại.');
      }
      if (approve &&
          (await tx.query(
            'shift_closure_photos',
            where: 'closure_id=?',
            whereArgs: [id],
          )).isEmpty) {
        throw const AuthException('Báo cáo chưa có ảnh.');
      }
      await tx.update(
        'shift_closures',
        {
          'status': approve ? 'approved' : 'rejected',
          'reviewed_by': session.userId,
          'reviewed_at': sqlTime(DateTime.now()),
        },
        where: 'id=?',
        whereArgs: [id],
      );
      if (approve) {
        await tx.update(
          'shift_assignments',
          {'status': 'completed'},
          where: 'id=?',
          whereArgs: [c['assignment_id']],
        );
        final a = (await tx.query(
          'shift_assignments',
          where: 'id=?',
          whereArgs: [c['assignment_id']],
        )).single;
        final pending = await tx.query(
          'shift_assignments',
          where: "shift_id=? AND status='assigned'",
          whereArgs: [a['shift_id']],
        );
        if (pending.isEmpty) {
          await tx.update(
            'shifts',
            {'status': 'closed'},
            where: 'id=?',
            whereArgs: [a['shift_id']],
          );
        }
      }
      await _notify(
        tx,
        [c['submitted_by'] as int],
        'Kết quả báo cáo đóng ca',
        approve
            ? 'Báo cáo đóng ca đã được duyệt.'
            : 'Báo cáo bị từ chối. Bạn có thể bổ sung và gửi lại.',
        'shift_closures',
        id,
      );
    });
  }
}

extension WorkforceAccountLinks on WorkforceRepository {
  Future<void> setUserEmail(int userId, String email) async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw const AuthException('Email không hợp lệ.');
    }
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'users.manage');
      await tx.update(
        'users',
        {'email': email.trim().toLowerCase(), 'google_subject': null},
        where: 'id=?',
        whereArgs: [userId],
      );
    });
  }

  Future<List<RowData>> unlinkedAccounts() async {
    final db = await _open();
    await _require(db, 'employees.manage');
    return db.rawQuery(
      'SELECT u.id,u.username FROM users u LEFT JOIN employees e ON e.user_id=u.id WHERE e.id IS NULL AND u.is_active=1 ORDER BY u.username',
    );
  }

  Future<void> linkEmployee(int employeeId, int userId) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _require(tx, 'employees.manage');
      if ((await tx.query(
        'employees',
        where: 'id=? AND user_id IS NULL',
        whereArgs: [employeeId],
      )).isEmpty) {
        throw const AuthException('Hồ sơ đã có tài khoản hoặc không tồn tại.');
      }
      if ((await tx.query(
        'users',
        where: 'id=? AND is_active=1',
        whereArgs: [userId],
      )).isEmpty) {
        throw const AuthException('Tài khoản không hợp lệ.');
      }
      await tx.update(
        'employees',
        {'user_id': userId},
        where: 'id=?',
        whereArgs: [employeeId],
      );
    });
  }
}
