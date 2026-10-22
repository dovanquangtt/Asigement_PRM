part of 'workforce_repository.dart';

extension AttendanceReview on WorkforceRepository {
  Future<List<RowData>> myAttendanceDevices() async {
    final db = await _open();
    await _require(db, 'attendance.self');
    final me = await _me(db);
    return db.query(
      'employee_devices',
      where: 'employee_id=? AND revoked_at IS NULL',
      whereArgs: [me['id']],
      orderBy: 'id DESC',
    );
  }

  Future<int> submitAttendance(
    int assignmentId,
    String type,
    AttendanceEvidence evidence, {
    int? selectedDeviceId,
    List<String> collectionIssues = const [],
    DateTime? now,
  }) async {
    if (!['check_in', 'check_out'].contains(type) ||
        evidence.deviceIdentifier.trim().isEmpty) {
      throw const AuthException(
        'Thiếu loại điểm danh hoặc thông tin thiết bị thực tế.',
      );
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final db = await _open();
    return db.transaction((tx) async {
      await _require(tx, 'attendance.self');
      final me = await _me(tx);
      final rows = await tx.rawQuery(
        "SELECT a.id assignment_id,s.*,b.latitude,b.longitude,b.geofence_radius_m,b.require_gps,b.require_wifi,b.require_registered_device,COALESCE(t.break_minutes,0) break_minutes,COALESCE(t.late_grace_minutes,0) late_grace_minutes FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id LEFT JOIN shift_templates t ON t.id=s.template_id WHERE a.id=? AND a.employee_id=? AND a.status='assigned'",
        [assignmentId, me['id']],
      );
      if (rows.isEmpty) {
        throw const AuthException(
          'Phân ca không thuộc bạn hoặc không còn hiệu lực.',
        );
      }
      final shift = rows.single;
      await _ensureAttendanceEditable(tx, assignmentId);
      if (!['scheduled', 'in_progress'].contains(shift['status'])) {
        throw const AuthException('Ca đã đóng hoặc hủy.');
      }
      final previous = await tx.query(
        'attendance_events',
        where: "assignment_id=? AND result IN ('accepted','pending_review')",
        whereArgs: [assignmentId],
      );
      final currentRecord = (await tx.query(
        'attendance_records',
        where: 'assignment_id=?',
        whereArgs: [assignmentId],
      )).firstOrNull;
      if (currentRecord?[type == 'check_in' ? 'check_in_at' : 'check_out_at'] !=
          null) {
        throw const AuthException(
          'Đã có giờ công. Muốn sửa hãy gửi yêu cầu điều chỉnh.',
        );
      }
      if (previous.any((r) => r['event_type'] == type)) {
        throw const AuthException(
          'Bạn đã gửi hoặc đã được duyệt lần điểm danh này.',
        );
      }
      RowData? selected;
      if (selectedDeviceId != null) {
        selected = (await tx.query(
          'employee_devices',
          where: 'id=? AND employee_id=? AND revoked_at IS NULL',
          whereArgs: [selectedDeviceId, me['id']],
        )).firstOrNull;
        if (selected == null) {
          throw const AuthException(
            'Chỉ chọn thiết bị của chính tài khoản, chưa bị thu hồi.',
          );
        }
      }
      final checks = await _validateAttendanceEvidence(
        tx,
        shift,
        me['id'] as int,
        evidence,
        clock,
      );
      final warnings = [
        ...checks['failures'] as List<String>,
        ...collectionIssues,
      ];
      if (selected != null &&
          selected['device_identifier'] != evidence.deviceIdentifier) {
        warnings.add('Thiết bị được chọn khác thiết bị thực tế gửi yêu cầu');
      }
      if (clock.isBefore(
            utcTime(shift['starts_at']).subtract(const Duration(hours: 1)),
          ) ||
          clock.isAfter(
            utcTime(shift['ends_at']).add(const Duration(hours: 12)),
          ) ||
          (type == 'check_in' && clock.isAfter(utcTime(shift['ends_at'])))) {
        warnings.add('Gửi ngoài khoảng giờ điểm danh thông thường');
      }
      if (type == 'check_out' && currentRecord?['check_in_at'] == null) {
        warnings.add('Thiếu giờ vào hoặc giờ vào đang chờ xử lý');
      }
      final automatic = warnings.isEmpty;
      final validCoordinates =
          evidence.latitude != null &&
          evidence.longitude != null &&
          evidence.latitude!.isFinite &&
          evidence.longitude!.isFinite &&
          evidence.latitude!.abs() <= 90 &&
          evidence.longitude!.abs() <= 180;
      final id = await tx.insert('attendance_events', {
        'assignment_id': assignmentId,
        'event_type': type,
        'occurred_at': sqlTime(clock),
        'device_id': selected?['id'] ?? checks['device_id'],
        'actual_device_identifier': evidence.deviceIdentifier,
        'selected_device_identifier':
            selected?['device_identifier'] ?? evidence.deviceIdentifier,
        'device_platform': evidence.platform,
        'submitted_by': session.userId,
        'evidence_collected_at': sqlTime(evidence.collectedAt),
        'evidence_mocked': evidence.mocked ? 1 : 0,
        'latitude': validCoordinates ? evidence.latitude : null,
        'longitude': validCoordinates ? evidence.longitude : null,
        'gps_accuracy_m':
            evidence.accuracy != null &&
                evidence.accuracy!.isFinite &&
                evidence.accuracy! >= 0
            ? evidence.accuracy
            : null,
        'wifi_ssid': evidence.ssid,
        'wifi_bssid': evidence.bssid,
        'device_valid': checks['device_valid'] == true ? 1 : 0,
        'gps_valid': checks['gps_valid'] == true ? 1 : 0,
        'wifi_valid': checks['wifi_valid'] == true ? 1 : 0,
        'result': automatic ? 'accepted' : 'pending_review',
        'confirmed_at': automatic ? sqlTime(clock) : null,
        'checks_snapshot': jsonEncode({
          'warnings': warnings,
          'branch_latitude': shift['latitude'],
          'branch_longitude': shift['longitude'],
          'radius_m': checks['radius_m'],
          'distance_m': checks['distance_m'],
        }),
      });
      if (automatic) {
        await _applyAttendanceRecord(tx, shift, assignmentId, type, clock);
        final r = (await tx.query(
          'attendance_records',
          where: 'assignment_id=?',
          whereArgs: [assignmentId],
        )).single;
        if (r['overtime_status'] == 'PENDING') {
          await _notify(
            tx,
            await _attendanceReviewers(tx, shift['branch_id'] as int),
            'Tăng ca chờ xác nhận',
            '${me['full_name']} có ${r['overtime_requested_minutes']} phút tăng ca.',
            'attendance_records',
            r['id'] as int,
          );
        }
      } else {
        await _notify(
          tx,
          await _attendanceReviewers(tx, shift['branch_id'] as int),
          'Điểm danh bất thường cần kiểm tra',
          '${me['full_name']} gửi ${type == 'check_in' ? 'vào ca' : 'ra ca'} #$id. ${warnings.length} cảnh báo.',
          'attendance_events',
          id,
        );
      }
      await _audit(tx, 'attendance.submit', 'attendance_events', id);
      return id;
    });
  }

  Future<List<RowData>> attendanceSubmissions() async {
    final db = await _open();
    final scope = await _attendanceScope(db);
    return db.rawQuery(
      "SELECT ev.*,COALESCE(sender.full_name,e.full_name) full_name,COALESCE(sender.employee_code,e.employee_code) employee_code,b.name branch_name,s.starts_at,s.ends_at "
      "FROM attendance_events ev JOIN shift_assignments a ON a.id=ev.assignment_id JOIN employees e ON e.id=a.employee_id "
      "JOIN shifts s ON s.id=a.shift_id JOIN branches b ON b.id=s.branch_id LEFT JOIN employees sender ON sender.user_id=ev.submitted_by WHERE ev.submitted_by IS NOT NULL ${scope == null ? '' : 'AND s.branch_id=?'} "
      "ORDER BY CASE WHEN ev.result='pending_review' THEN 0 ELSE 1 END,ev.id DESC",
      scope == null ? [] : [scope],
    );
  }

  Future<void> reviewAttendance(
    int eventId,
    bool approve, {
    required String note,
  }) async {
    final db = await _open();
    await db.transaction((tx) async {
      await _attendanceScope(tx);
      final event = (await tx.query(
        'attendance_events',
        where: "id=? AND result='pending_review'",
        whereArgs: [eventId],
      )).firstOrNull;
      if (event == null) {
        throw const AuthException('Yêu cầu không tồn tại hoặc đã xử lý.');
      }
      final assigned = (await tx.rawQuery(
        'SELECT e.user_id FROM shift_assignments a JOIN employees e ON e.id=a.employee_id WHERE a.id=?',
        [event['assignment_id']],
      )).single;
      final senderId = event['submitted_by'] ?? assigned['user_id'];
      if (senderId == session.userId) {
        throw const AuthException('Không thể tự duyệt điểm danh của mình.');
      }
      final snapshot = event['checks_snapshot'] == null
          ? <String, dynamic>{
              'warnings': ['Dữ liệu điểm danh cũ, cần đối chiếu thủ công'],
            }
          : jsonDecode(event['checks_snapshot'] as String)
                as Map<String, dynamic>;
      if ((!approve || (snapshot['warnings'] as List).isNotEmpty) &&
          note.trim().isEmpty) {
        throw const AuthException(
          'Cần nhập lý do khi từ chối hoặc duyệt yêu cầu có cảnh báo.',
        );
      }
      final branch = (await tx.rawQuery(
        'SELECT s.branch_id FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id WHERE a.id=?',
        [event['assignment_id']],
      )).single;
      await _requireAttendanceBranch(tx, branch['branch_id'] as int);
      final now = sqlTime(DateTime.now());
      if (approve) {
        await _ensureAttendanceEditable(tx, event['assignment_id'] as int);
        final rows = await tx.rawQuery(
          "SELECT a.employee_id,a.status assignment_status,s.*,COALESCE(t.break_minutes,0) break_minutes,COALESCE(t.late_grace_minutes,0) late_grace_minutes "
          "FROM shift_assignments a JOIN shifts s ON s.id=a.shift_id LEFT JOIN shift_templates t ON t.id=s.template_id WHERE a.id=?",
          [event['assignment_id']],
        );
        final shift = rows.single;
        final owners = await tx.query(
          'employees',
          where: 'id=? AND user_id=?',
          whereArgs: [shift['employee_id'], senderId],
        );
        if (owners.isEmpty ||
            shift['assignment_status'] != 'assigned' ||
            !['scheduled', 'in_progress'].contains(shift['status'])) {
          throw const AuthException(
            'Phân ca đã đổi người, đóng hoặc hủy. Không thể duyệt.',
          );
        }
        final previous = await tx.query(
          'attendance_events',
          where: "assignment_id=? AND result='accepted'",
          whereArgs: [event['assignment_id']],
        );
        if (previous.any((r) => r['event_type'] == event['event_type'])) {
          throw const AuthException('Đã có lần điểm danh được duyệt.');
        }
        final currentRecord = (await tx.query(
          'attendance_records',
          where: 'assignment_id=?',
          whereArgs: [event['assignment_id']],
        )).firstOrNull;
        if (currentRecord?[event['event_type'] == 'check_in'
                ? 'check_in_at'
                : 'check_out_at'] !=
            null) {
          throw const AuthException(
            'Đã có giờ công. Hãy xử lý bằng yêu cầu điều chỉnh.',
          );
        }
        if (event['event_type'] == 'check_out' &&
            currentRecord?['check_in_at'] == null) {
          throw const AuthException('Hãy duyệt vào ca trước khi duyệt ra ca.');
        }
        await _applyAttendanceRecord(
          tx,
          shift,
          event['assignment_id'] as int,
          event['event_type'] as String,
          utcTime(event['occurred_at']),
        );
        await tx.update(
          'attendance_records',
          {'approved_by': session.userId, 'approved_at': now},
          where: 'assignment_id=?',
          whereArgs: [event['assignment_id']],
        );
      }
      await tx.update(
        'attendance_events',
        {
          'result': approve ? 'accepted' : 'rejected',
          'reviewed_by': session.userId,
          'reviewed_at': now,
          'review_note': note.trim(),
          'confirmed_at': approve ? now : null,
          'rejection_reason': approve ? null : note.trim(),
        },
        where: 'id=?',
        whereArgs: [eventId],
      );
      await _notify(
        tx,
        senderId == null ? <int>[] : [senderId as int],
        'Kết quả duyệt điểm danh',
        'Yêu cầu #$eventId ${approve ? 'đã được duyệt' : 'bị từ chối'}. ${note.trim()}',
        'attendance_events',
        eventId,
      );
      await _audit(
        tx,
        approve ? 'attendance.approve' : 'attendance.reject',
        'attendance_events',
        eventId,
      );
    });
  }
}
