import 'package:flutter/material.dart';

import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/attendance_outcome.dart';
import '../widgets/month_calendar.dart';

/// Lịch tháng: đủ các ngày của tháng, ngày có ca có chấm màu theo kết quả điểm danh. Bấm một
/// ngày để xem chi tiết các ca của ngày đó (xử lý bởi [onDayTap]).
class MonthCalendarScreen extends StatefulWidget {
  const MonthCalendarScreen({
    super.key,
    required this.shifts,
    required this.leaves,
    required this.onDayTap,
    this.initialMonth,
    this.now,
  });

  final List<RowData> shifts;
  final List<RowData> leaves;
  final ValueChanged<DateTime> onDayTap;
  final DateTime? initialMonth;

  /// Chỉ để kiểm thử; mặc định là giờ hiện tại.
  final DateTime? now;

  @override
  State<MonthCalendarScreen> createState() => _MonthCalendarScreenState();
}

class _MonthCalendarScreenState extends State<MonthCalendarScreen> {
  late DateTime month = () {
    final m = widget.initialMonth ?? widget.now ?? DateTime.now();
    return DateTime(m.year, m.month);
  }();

  void _move(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
    });
  }

  /// Chọn nhanh tháng/năm: mũi tên đổi năm, bấm một trong 12 tháng.
  Future<void> _pickMonth() async {
    var year = month.year;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setInner) => AlertDialog(
          title: Row(
            children: [
              IconButton(
                key: const Key('calendar-year-prev'),
                onPressed: () => setInner(() => year--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '$year',
                  textAlign: TextAlign.center,
                  key: const Key('calendar-year'),
                ),
              ),
              IconButton(
                key: const Key('calendar-year-next'),
                onPressed: () => setInner(() => year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var m = 1; m <= 12; m++)
                ChoiceChip(
                  key: Key('calendar-month-$m'),
                  label: Text('Th$m'),
                  selected: year == month.year && m == month.month,
                  onSelected: (_) => Navigator.pop(c, DateTime(year, m)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => month = picked);
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final marks = calendarMarks(
      shifts: widget.shifts,
      leaves: widget.leaves,
      month: month,
      now: now,
    );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Lịch tháng')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('calendar-prev'),
                tooltip: 'Tháng trước',
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: InkWell(
                  key: const Key('calendar-title'),
                  onTap: _pickMonth,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Tháng ${month.month}/${month.year}',
                          key: const Key('calendar-month-label'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          color: Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('calendar-next'),
                tooltip: 'Tháng sau',
                onPressed: () => _move(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: 10),
          MonthCalendarGrid(
            month: month,
            marks: marks,
            today: now,
            onDayTap: widget.onDayTap,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legend('Đã điểm danh', markPresent),
              _legend('Vắng / lỗi', markAbsent),
              _legend('Chờ duyệt', markPending),
              _legend('Sắp tới', markFuture),
              _legend('Nghỉ phép', markLeave),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Bấm vào một ngày để xem chi tiết các ca của ngày đó.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}
