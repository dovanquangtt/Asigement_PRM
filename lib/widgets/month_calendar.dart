import 'package:flutter/material.dart';

import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import 'attendance_outcome.dart';
import 'shift_timeline.dart';

/// Màu các chấm của từng ngày trong [month], theo thứ tự giờ bắt đầu: mỗi ca một chấm theo kết quả
/// điểm danh (xanh = đã điểm danh, đỏ = vắng/lỗi, cam = chờ duyệt, xám = sắp tới), ngày nghỉ phép
/// đã duyệt một chấm nâu. Khóa là ngày (00:00 giờ địa phương).
Map<DateTime, List<Color>> calendarMarks({
  required Iterable<RowData> shifts,
  required Iterable<RowData> leaves,
  required DateTime month,
  required DateTime now,
}) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final marks = <DateTime, List<Color>>{};
  for (final e in buildTimeline(
    shifts: shifts,
    leaves: leaves,
    from: first,
    to: last,
  )) {
    final color = e.shift != null
        ? outcomeColor(attendanceOutcome(shiftPhase(e.shift!, now.toUtc())))
        : markLeave;
    marks.putIfAbsent(e.day, () => []).add(color);
  }
  return marks;
}

const _weekdays = ['CN', 'Th2', 'Th3', 'Th4', 'Th5', 'Th6', 'Th7'];

/// Lưới lịch của một tháng (tuần bắt đầu từ Chủ nhật như ảnh mẫu), mỗi ngày có chấm màu và bấm được.
class MonthCalendarGrid extends StatelessWidget {
  const MonthCalendarGrid({
    super.key,
    required this.month,
    required this.marks,
    required this.today,
    required this.onDayTap,
  });

  final DateTime month;
  final Map<DateTime, List<Color>> marks;
  final DateTime today;
  final ValueChanged<DateTime> onDayTap;

  static const maxDots = 5;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday % 7; // Chủ nhật = 0
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final todayOnly = dateOnly(today);
    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - lead + 1, days, todayOnly)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int dayNumber, int days, DateTime todayOnly) {
    if (dayNumber < 1 || dayNumber > days) return const SizedBox(height: 58);
    final day = DateTime(month.year, month.month, dayNumber);
    final isToday = day == todayOnly;
    final dots = marks[day] ?? const <Color>[];
    return InkWell(
      key: Key('calendar-day-${day.year}-${day.month}-$dayNumber'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => onDayTap(day),
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 16,
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                color: isToday ? const Color(0xFFF59E0B) : ink,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 6,
              child: Row(
                key: Key('calendar-dots-${day.year}-${day.month}-$dayNumber'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final color in dots.take(maxDots))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
