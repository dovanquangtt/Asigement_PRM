import 'package:flutter/material.dart';

import 'shift_timeline.dart';

/// Kết quả điểm danh của một ca: dùng chung cho lịch sử điểm danh (✓/✗) và lịch tháng (chấm màu).
enum AttendanceOutcome {
  /// Ca đã qua và điểm danh thành công (có cả giờ vào và giờ ra): dấu tích xanh.
  present,

  /// Ca đã qua nhưng không điểm danh, điểm danh bị từ chối, thiếu giờ ra hoặc công bị hủy: dấu X đỏ.
  absent,

  /// Có lượt điểm danh đang chờ quản lý duyệt: đồng hồ cát cam.
  pending,

  /// Ca chưa tới hoặc đang diễn ra: biểu tượng xám.
  future,
}

AttendanceOutcome attendanceOutcome(ShiftPhase phase) => switch (phase) {
  ShiftPhase.completed => AttendanceOutcome.present,
  ShiftPhase.missingCheckOut ||
  ShiftPhase.absent ||
  ShiftPhase.voided => AttendanceOutcome.absent,
  ShiftPhase.pendingReview => AttendanceOutcome.pending,
  ShiftPhase.notYet || ShiftPhase.working => AttendanceOutcome.future,
};

const markPresent = Color(0xFF1FB97D);
const markAbsent = Color(0xFFE5484D);
const markPending = Color(0xFFE08A1E);
const markFuture = Color(0xFF9AA1AB);

/// Chấm màu cho ngày nghỉ phép đã duyệt trên lịch tháng.
const markLeave = Color(0xFF8B3A12);

Color outcomeColor(AttendanceOutcome o) => switch (o) {
  AttendanceOutcome.present => markPresent,
  AttendanceOutcome.absent => markAbsent,
  AttendanceOutcome.pending => markPending,
  AttendanceOutcome.future => markFuture,
};

IconData outcomeIcon(AttendanceOutcome o) => switch (o) {
  AttendanceOutcome.present => Icons.check_rounded,
  AttendanceOutcome.absent => Icons.close_rounded,
  AttendanceOutcome.pending => Icons.hourglass_top_rounded,
  AttendanceOutcome.future => Icons.schedule_rounded,
};
