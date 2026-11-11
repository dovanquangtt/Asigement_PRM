import 'package:flutter/material.dart';

import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';

/// Trạng thái hiển thị của một ca trong lịch của nhân viên (gộp lịch ca + điểm danh).
enum ShiftPhase {
  /// Đã có cả giờ vào và giờ ra: "Ca đã hoàn thành".
  completed,

  /// Đã vào ca, ca chưa kết thúc: "Đang làm".
  working,

  /// Có lượt điểm danh đang chờ quản lý duyệt: "Chờ duyệt điểm danh".
  pendingReview,

  /// Đã vào ca nhưng ca kết thúc mà chưa có giờ ra: "Thiếu giờ ra".
  missingCheckOut,

  /// Công bị quản lý hủy: "Công bị hủy".
  voided,

  /// Ca đã kết thúc mà không điểm danh: "Nghỉ".
  absent,

  /// Chưa vào ca (ca chưa tới hoặc đang diễn ra mà chưa điểm danh): "Chưa vào ca".
  notYet,
}

class PhaseStyle {
  const PhaseStyle(this.label, this.color, this.tint, this.icon);
  final String label;
  final Color color;
  final Color tint;
  final IconData icon;
}

/// Nhãn dùng cho ngày nghỉ phép đã duyệt trong bảng lịch.
const leavePhaseStyle = PhaseStyle(
  'Nghỉ',
  Color(0xFF8B3A12),
  Color(0xFFFBEFE8),
  Icons.beach_access_rounded,
);

PhaseStyle phaseStyle(ShiftPhase phase) => switch (phase) {
  ShiftPhase.completed => const PhaseStyle(
    'Ca đã hoàn thành',
    Color(0xFF1E9E4A),
    Color(0xFFE9F7EE),
    Icons.check_circle_rounded,
  ),
  ShiftPhase.working => const PhaseStyle(
    'Đang làm',
    Color(0xFFE67E22),
    Color(0xFFFEF5E7),
    Icons.timelapse_rounded,
  ),
  ShiftPhase.pendingReview => const PhaseStyle(
    'Chờ duyệt điểm danh',
    Color(0xFFB7791F),
    Color(0xFFFFF8E1),
    Icons.hourglass_top_rounded,
  ),
  ShiftPhase.missingCheckOut => const PhaseStyle(
    'Thiếu giờ ra',
    Color(0xFFC0392B),
    Color(0xFFFDEDEC),
    Icons.error_outline_rounded,
  ),
  ShiftPhase.voided => const PhaseStyle(
    'Công bị hủy',
    Color(0xFF7F8C8D),
    Color(0xFFF1F8F7),
    Icons.block_rounded,
  ),
  ShiftPhase.absent => leavePhaseStyle,
  ShiftPhase.notYet => const PhaseStyle(
    'Chưa vào ca',
    Color(0xFF6B7280),
    Color(0xFFF3F4F6),
    Icons.schedule_rounded,
  ),
};

/// Trạng thái của một ca tại thời điểm [nowUtc], từ dòng của `employeeSchedule()`.
ShiftPhase shiftPhase(RowData shift, DateTime nowUtc) {
  if (shift['attendance_state'] == 'VOIDED') return ShiftPhase.voided;
  final hasIn = shift['check_in_at'] != null;
  final hasOut = shift['check_out_at'] != null;
  if (hasIn && hasOut) return ShiftPhase.completed;
  if (((shift['pending_events'] as num?)?.toInt() ?? 0) > 0) {
    return ShiftPhase.pendingReview;
  }
  final ended = utcTime(shift['ends_at']).isBefore(nowUtc);
  if (hasIn) return ended ? ShiftPhase.missingCheckOut : ShiftPhase.working;
  return ended ? ShiftPhase.absent : ShiftPhase.notYet;
}

/// Màu nhấn của ca mới (viền, nhãn MỚI, thông báo).
const newShiftColor = Color(0xFF2F6FDE);

/// Ca vừa được phân: giao trong [newShiftWindow] gần đây hoặc nhân viên chưa chấp nhận/từ chối,
/// và ca chưa kết thúc.
const newShiftWindow = Duration(hours: 48);

bool shiftIsOld(RowData shift, DateTime nowUtc) =>
    utcTime(shift['ends_at']).isBefore(nowUtc);

bool shiftIsNew(RowData shift, DateTime nowUtc) {
  if (shiftIsOld(shift, nowUtc) || shift['assignment_status'] == 'cancelled') {
    return false;
  }
  if (shift['response_status'] == 'pending') return true;
  final assigned = shift['assigned_at'];
  if (assigned == null) return false;
  return nowUtc.difference(utcTime(assigned)) <= newShiftWindow;
}

/// Một dòng của bảng lịch: một ca, hoặc một ngày trong đợt nghỉ phép đã duyệt.
class TimelineEntry {
  const TimelineEntry({
    required this.day,
    required this.start,
    required this.end,
    this.shift,
    this.leave,
  });

  /// Ngày (giờ địa phương, 00:00) mà dòng này thuộc về.
  final DateTime day;
  final DateTime start;
  final DateTime end;
  final RowData? shift;
  final RowData? leave;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Gộp ca làm và các ngày nghỉ phép đã duyệt trong [from]..[to] (gồm cả hai đầu, theo ngày
/// địa phương), sắp theo ngày rồi giờ bắt đầu. Đợt nghỉ nhiều ngày được tách theo từng ngày.
List<TimelineEntry> buildTimeline({
  required Iterable<RowData> shifts,
  required Iterable<RowData> leaves,
  required DateTime from,
  required DateTime to,
}) {
  final first = dateOnly(from), last = dateOnly(to);
  final entries = <TimelineEntry>[];
  for (final s in shifts) {
    final start = utcTime(s['starts_at']).toLocal();
    final day = dateOnly(start);
    if (day.isBefore(first) || day.isAfter(last)) continue;
    entries.add(
      TimelineEntry(
        day: day,
        start: start,
        end: utcTime(s['ends_at']).toLocal(),
        shift: s,
      ),
    );
  }
  for (final l in leaves) {
    if (l['status'] != 'approved') continue;
    final start = utcTime(l['starts_at']).toLocal();
    final end = utcTime(l['ends_at']).toLocal();
    // Đợt nghỉ kết thúc đúng 00:00 thì không tính ngày kế tiếp.
    var lastDay = dateOnly(end);
    if (end == lastDay && end.isAfter(start)) {
      lastDay = DateTime(lastDay.year, lastDay.month, lastDay.day - 1);
    }
    for (
      var day = dateOnly(start);
      !day.isAfter(lastDay);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (day.isBefore(first) || day.isAfter(last)) continue;
      entries.add(TimelineEntry(day: day, start: start, end: end, leave: l));
    }
  }
  entries.sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.start.compareTo(b.start);
  });
  return entries;
}

const _slotColors = [
  Color(0xFFE67E22),
  Color(0xFF2F6FDE),
  Color(0xFF27AE60),
  Color(0xFF8E44AD),
];

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _hmUtc(Object? utc) =>
    utc == null ? 'Chưa có' : _hm(utcTime(utc).toLocal());

const _weekdayNames = [
  'Thứ 2',
  'Thứ 3',
  'Thứ 4',
  'Thứ 5',
  'Thứ 6',
  'Thứ 7',
  'CN',
];
const _weekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String shiftTitleOf(DateTime start) => start.hour < 12
    ? 'Ca sáng'
    : start.hour < 17
    ? 'Ca chiều'
    : 'Ca tối';

/// Bảng lịch theo tuần: dải T2–CN có chấm ở ngày có ca, danh sách thẻ nhóm theo ngày, mỗi thẻ
/// có trạng thái nổi bật (Ca đã hoàn thành / Nghỉ / Chưa vào ca ...). Thao tác trên thẻ do
/// [cardActions] cung cấp (điểm danh, đổi ca, đóng ca...).
class ShiftTimeline extends StatelessWidget {
  const ShiftTimeline({
    super.key,
    required this.entries,
    required this.weekStart,
    required this.selectedDay,
    required this.now,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onThisWeek,
    required this.onSelectDay,
    required this.cardActions,
  });

  /// Các dòng của đúng tuần đang xem (đã qua `buildTimeline`).
  final List<TimelineEntry> entries;
  final DateTime weekStart;
  final DateTime? selectedDay;
  final DateTime now;
  final VoidCallback onPrevWeek, onNextWeek, onThisWeek;
  final ValueChanged<DateTime?> onSelectDay;
  final List<Widget> Function(RowData shift, ShiftPhase phase) cardActions;

  bool get _isThisWeek {
    final monday = dateOnly(now).subtract(Duration(days: now.weekday - 1));
    return dateOnly(monday) == dateOnly(weekStart);
  }

  Widget _header() {
    final end = DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
    return Row(
      children: [
        IconButton(
          key: const Key('timeline-prev'),
          tooltip: 'Tuần trước',
          onPressed: onPrevWeek,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'Tuần ${_dm(weekStart)} – ${_dm(end)}/${end.year}',
                key: const Key('timeline-week-label'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              if (!_isThisWeek)
                TextButton(
                  key: const Key('timeline-today'),
                  onPressed: onThisWeek,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Về tuần này'),
                ),
            ],
          ),
        ),
        IconButton(
          key: const Key('timeline-next'),
          tooltip: 'Tuần sau',
          onPressed: onNextWeek,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _strip() {
    final today = dateOnly(now);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (_) {
              final day = DateTime(
                weekStart.year,
                weekStart.month,
                weekStart.day + i,
              );
              final selected =
                  selectedDay != null && dateOnly(selectedDay!) == day;
              final isToday = day == today;
              final has = entries.any((e) => e.day == day);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    key: Key(
                      'timeline-day-${day.year}-${day.month}-${day.day}',
                    ),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelectDay(selected ? null : day),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? green : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? green
                              : isToday
                              ? green.withValues(alpha: 0.6)
                              : const Color(0xFFD5E7E4),
                          width: isToday && !selected ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _weekdayShort[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? Colors.white
                                  : isToday
                                  ? green
                                  : ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: has
                                  ? (selected ? Colors.white : green)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _chip(PhaseStyle style, {Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: style.color,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: style.color.withValues(alpha: 0.35),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(style.icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        // Flexible: trên màn hẹp chữ xuống dòng thay vì tràn.
        Flexible(
          child: Text(
            style.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _infoBox(String label, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: muted)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ],
    ),
  );

  Widget _card({
    required Color stripe,
    required String tag,
    required DateTime start,
    required DateTime end,
    required PhaseStyle style,
    required List<Widget> body,
    bool isNew = false,
    bool isOld = false,
    Key? key,
  }) => Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      // Ca cũ hơi nhạt đi để ca sắp tới nổi lên; ca mới có viền xanh dày và đổ bóng.
      color: isOld
          ? Color.alphaBlend(Colors.white.withValues(alpha: 0.45), style.tint)
          : style.tint,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isNew
            ? newShiftColor
            : style.color.withValues(alpha: isOld ? 0.25 : 0.45),
        width: isNew ? 2.4 : 1.4,
      ),
      boxShadow: isNew
          ? [
              BoxShadow(
                color: newShiftColor.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 6, color: stripe),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 4, 12),
            child: SizedBox(
              width: 56,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: stripe.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tag,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: stripe,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hm(start),
                    style: const TextStyle(fontSize: 12.5, color: muted),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFCBD3CF),
                    ),
                  ),
                  Text(
                    _hm(end),
                    style: const TextStyle(fontSize: 12.5, color: muted),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: body,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _shiftCard(TimelineEntry e, int slot) {
    final s = e.shift!;
    final phase = shiftPhase(s, now.toUtc());
    final style = phaseStyle(phase);
    final note = '${s['shift_note'] ?? ''}'.trim();
    final id = (s['assignment_id'] as num).toInt();
    final isNew = shiftIsNew(s, now.toUtc());
    final isOld = shiftIsOld(s, now.toUtc());
    return _card(
      key: Key('timeline-shift-$id'),
      stripe: _slotColors[(slot - 1) % _slotColors.length],
      tag: 'Ca $slot',
      start: e.start,
      end: e.end,
      style: style,
      isNew: isNew,
      isOld: isOld,
      body: [
        if (isNew || isOld)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              children: [
                if (isNew)
                  Container(
                    key: Key('timeline-new-$id'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: newShiftColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fiber_new_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'MỚI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isOld)
                  Container(
                    key: Key('timeline-old-$id'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E8E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Ca cũ',
                      style: TextStyle(
                        color: Color(0xFF5F6B6B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        _infoBox('Chi nhánh', '${s['branch_name']}'),
        const SizedBox(height: 8),
        Text(
          'Mã ca #${s['shift_id']} • ${shiftTitleOf(e.start)}',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          'Giờ vào: ${_hmUtc(s['check_in_at'])}   Giờ ra: ${_hmUtc(s['check_out_at'])}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        if (note.isNotEmpty)
          Text(
            'Ghi chú: $note',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        const SizedBox(height: 10),
        _chip(style, key: Key('timeline-status-$id')),
        ...cardActions(s, phase),
      ],
    );
  }

  Widget _leaveCard(TimelineEntry e) {
    final l = e.leave!;
    final reason = '${l['reason'] ?? ''}'.trim();
    return _card(
      key: Key('timeline-leave-${l['id']}'),
      stripe: leavePhaseStyle.color,
      tag: 'Nghỉ phép',
      start: e.start,
      end: e.end,
      style: leavePhaseStyle,
      body: [
        _infoBox('Loại nghỉ', '${l['leave_type_name']}'),
        const SizedBox(height: 8),
        Text(
          'Nghỉ phép đã được duyệt${reason.isEmpty ? '' : ' • $reason'}',
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        _chip(leavePhaseStyle, key: Key('timeline-leave-status-${l['id']}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = <DateTime>[];
    for (final e in entries) {
      if (selectedDay != null && e.day != dateOnly(selectedDay!)) continue;
      if (!days.contains(e.day)) days.add(e.day);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 8),
        _strip(),
        const SizedBox(height: 14),
        if (days.isEmpty)
          Container(
            key: const Key('timeline-empty'),
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD5E7E4)),
            ),
            child: Text(
              selectedDay != null
                  ? 'Bạn không có ca làm vào ngày này.'
                  : 'Tuần này bạn không có ca làm.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        else
          for (final day in days)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      children: [
                        Text(
                          _dm(day),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                        Text(
                          _weekdayNames[day.weekday - 1],
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      for (final item in _forDay(day))
                        item.$1.leave != null
                            ? _leaveCard(item.$1)
                            : _shiftCard(item.$1, item.$2),
                    ],
                  ),
                ),
              ],
            ),
      ],
    );
  }

  /// Các dòng của một ngày, kèm số thứ tự ca trong ngày (Ca 1, Ca 2, ...).
  List<(TimelineEntry, int)> _forDay(DateTime day) {
    var slot = 0;
    return [
      for (final e in entries)
        if (e.day == day) (e, e.shift != null ? ++slot : 0),
    ];
  }
}
