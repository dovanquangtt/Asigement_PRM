import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/open_shifts_section.dart';
import '../widgets/shift_day_dialog.dart';
import '../widgets/shift_timeline.dart';
import 'month_calendar_screen.dart';
import 'shift_swap_screen.dart';
import 'operations_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.repository,
    this.reloadToken = 0,
  });

  final WorkforceRepository repository;

  /// Đổi giá trị này (ví dụ khi có thông báo phân ca mới) để màn hình tải lại dữ liệu mà không
  /// mất tuần/ngày người dùng đang xem.
  final int reloadToken;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  WorkforceRepository get r => widget.repository;

  late Future<(List<RowData>, List<RowData>)> _loading;
  late DateTime _weekStart = _mondayOfWeek(DateTime.now());
  DateTime? _selectedDay; // null = cả tuần

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) _reload();
  }

  void _openCalendar(List<RowData> shifts, List<RowData> leaves) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MonthCalendarScreen(
          shifts: shifts,
          leaves: leaves,
          initialMonth: _weekStart,
          onDayTap: _showDayDialog,
        ),
      ),
    );
  }

  /// Chuyển bảng lịch tới tuần chứa [shift] để người dùng thấy ca đó ngay.
  void _goToShift(RowData shift) {
    final start = utcTime(shift['starts_at']).toLocal();
    setState(() {
      _weekStart = _mondayOfWeek(start);
      _selectedDay = DateTime(start.year, start.month, start.day);
    });
  }

  /// Biểu ngữ báo có ca mới được phân (kể cả ở tuần khác), bấm để tới ca sớm nhất.
  Widget _newShiftsBanner(List<RowData> shifts) {
    final nowUtc = DateTime.now().toUtc();
    final fresh = [
      for (final s in shifts)
        if (shiftIsNew(s, nowUtc)) s,
    ]..sort((a, b) => '${a['starts_at']}'.compareTo('${b['starts_at']}'));
    if (fresh.isEmpty) return const SizedBox.shrink();
    final first = utcTime(fresh.first['starts_at']).toLocal();
    return Container(
      key: const Key('new-shifts-banner'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: newShiftColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: newShiftColor, width: 1.6),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: newShiftColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bạn có ${fresh.length} ca mới được phân. '
              'Ca gần nhất: ${first.day.toString().padLeft(2, '0')}/${first.month.toString().padLeft(2, '0')} '
              '${first.hour.toString().padLeft(2, '0')}:${first.minute.toString().padLeft(2, '0')}.',
              style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
            ),
          ),
          TextButton(
            key: const Key('new-shifts-go'),
            onPressed: () => _goToShift(fresh.first),
            child: const Text('Xem'),
          ),
        ],
      ),
    );
  }

  void _reload() {
    setState(() {
      _loading = _fetchData();
    });
  }

  List<RowData> _allShifts = const [];
  List<RowData> _balances = const [];
  List<RowData> _leaves = const [];

  /// 1 ngày phép = 480 phút.
  String _days(int minutes) =>
      (minutes / 480).toStringAsFixed(minutes % 480 == 0 ? 0 : 1);

  Future<(List<RowData>, List<RowData>)> _fetchData() async {
    final shifts = await r.employeeSchedule();
    _allShifts = shifts;
    try {
      _balances = await r.leaveBalances();
    } catch (_) {
      _balances = const []; // tài khoản chưa có hồ sơ nhân viên: không có số dư
    }
    final leaves = await r.employeeLeaveRequests();
    _leaves = leaves;
    return (shifts, leaves);
  }

  Future<void> _createLeaveDialog() async {
    final types = await r.leaveTypes();
    if (!mounted) return;
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có danh mục loại nghỉ phép.')),
      );
      return;
    }

    final now = DateTime.now();
    final defaultStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day + 1).toString().padLeft(2, '0')} 08:00';
    final defaultEnd =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day + 1).toString().padLeft(2, '0')} 17:00';

    await featureForm(
      context,
      'Tạo yêu cầu nghỉ phép',
      [
        InputSpec(
          'type',
          'Loại nghỉ',
          options: {for (final t in types) '${t['id']}': '${t['name']}'},
        ),
        InputSpec('start', 'Từ ngày (YYYY-MM-DD HH:mm)', value: defaultStart),
        InputSpec('end', 'Đến ngày (YYYY-MM-DD HH:mm)', value: defaultEnd),
        const InputSpec('reason', 'Lý do xin nghỉ'),
      ],
      (v) async {
        final leaveTypeId = int.parse(v['type']!);
        final start = inputTime(v['start']!);
        final end = inputTime(v['end']!);
        await r.createLeaveRequest(
          leaveTypeId: leaveTypeId,
          start: start,
          end: end,
          reason: v['reason']!,
        );
      },
    );
    if (mounted) _reload();
  }

  Future<void> _requestSwap(int ownAssignmentId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ShiftSwapScreen(
          repository: r,
          initialAssignmentId: ownAssignmentId,
        ),
      ),
    );
    if (mounted) _reload();
  }

  String _shiftTitle(DateTime start) {
    final hour = start.hour;
    if (hour < 12) return 'Ca sáng';
    if (hour < 17) return 'Ca chiều';
    return 'Ca tối';
  }

  DateTime _mondayOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<RowData>, List<RowData>)>(
      future: _loading,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.error is AuthException
                        ? (snapshot.error as AuthException).message
                        : 'Không tải được lịch ca làm việc.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        }

        final (allShifts, leaves) = snapshot.data!;

        // Thống kê giờ làm
        int totalHours = 0;
        int upcomingCount = 0;
        final nowUtc = DateTime.now().toUtc();

        for (final s in allShifts) {
          final start = utcTime(s['starts_at']);
          final end = utcTime(s['ends_at']);
          final mins = end.difference(start).inMinutes;
          totalHours += mins ~/ 60;
          if (start.isAfter(nowUtc)) {
            upcomingCount++;
          }
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              heading('Lịch ca làm của bạn', 'LỊCH PHÂN CÔNG & XIN NGHỈ'),
              if (r.session.role == 'Nhân viên')
                OpenShiftsSection(
                  key: ValueKey(widget.reloadToken),
                  repository: r,
                  onRegistered: _reload,
                ),

              if (r.session.role != 'Nhân viên') ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            OperationsPage(repository: r, kind: 'schedule'),
                      ),
                    ).then((_) => _reload()),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Quản lý phân ca toàn nhà hàng'),
                  ),
                ),
              ],

              // 1. Thẻ chỉ số tổng quan
              Row(
                children: [
                  Expanded(
                    child: metric(
                      'Tổng ca làm',
                      '${allShifts.length}',
                      'ca',
                      Icons.calendar_month_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: metric(
                      'Tổng số giờ',
                      '$totalHours',
                      'giờ',
                      Icons.schedule_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: metric(
                      'Ca sắp tới',
                      '$upcomingCount',
                      'ca',
                      Icons.upcoming_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // 2. Bảng lịch tuần: lịch ca + điểm danh + nghỉ phép gộp một chỗ
              Row(
                children: [
                  Expanded(child: section('Lịch ca & điểm danh')),
                  Tooltip(
                    message: 'Xem lịch tháng',
                    child: Material(
                      color: const Color(0xFFE0F2EF),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        key: const Key('open-month-calendar'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openCalendar(allShifts, leaves),
                        child: const SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(
                            Icons.calendar_month_rounded,
                            color: green,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _newShiftsBanner(allShifts),
              ShiftTimeline(
                entries: buildTimeline(
                  shifts: allShifts,
                  leaves: leaves,
                  from: _weekStart,
                  to: DateTime(
                    _weekStart.year,
                    _weekStart.month,
                    _weekStart.day + 6,
                  ),
                ),
                weekStart: _weekStart,
                selectedDay: _selectedDay,
                now: DateTime.now(),
                onPrevWeek: () => _moveWeek(-7),
                onNextWeek: () => _moveWeek(7),
                onThisWeek: () => setState(() {
                  _weekStart = _mondayOfWeek(DateTime.now());
                  _selectedDay = null;
                }),
                onSelectDay: (day) => setState(() => _selectedDay = day),
                cardActions: _cardActions,
              ),
              const SizedBox(height: 8),

              // 3. Số ngày phép còn lại và yêu cầu xin nghỉ phép
              section('Số ngày phép của bạn'),
              if (_balances.isEmpty)
                panel(child: const Text('Chưa có số ngày phép được cấp.'))
              else
                panel(
                  child: Column(
                    key: const Key('leave-balances'),
                    children: [
                      for (final b in _balances)
                        money(
                          '${b['name']}${b['is_paid'] == 1 ? '' : ' (không lương)'}',
                          'còn ${_days(b['remaining_minutes'] as int)} / ${_days(b['granted_minutes'] as int)} ngày',
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              section('Yêu cầu xin nghỉ phép của bạn'),
              if (leaves.isEmpty)
                panel(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F8F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.event_available_outlined,
                          color: green,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Chưa có yêu cầu xin nghỉ phép nào.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final leave in leaves) ...[
                  panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F8F7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.event_busy_rounded,
                                size: 18,
                                color: green,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${leave['leave_type_name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _buildStatusPill(
                              leave['status']?.toString() ?? 'pending',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 15,
                              color: muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${localTime(leave['starts_at'])} — ${localTime(leave['ends_at'])}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              size: 15,
                              color: muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Lý do: ${leave['reason']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _createLeaveDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Tạo yêu cầu nghỉ phép mới'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusPill(String status) {
    final (label, bg, fg) = switch (status) {
      'approved' => (
        'Đã duyệt',
        const Color(0xFFE8F8F5),
        const Color(0xFF27AE60),
      ),
      'rejected' => (
        'Từ chối',
        const Color(0xFFFDEDEC),
        const Color(0xFFC0392B),
      ),
      'cancelled' => (
        'Đã hủy',
        const Color(0xFFF1F8F7),
        const Color(0xFF7F8C8D),
      ),
      _ => ('Chờ duyệt', const Color(0xFFFEF5E7), const Color(0xFFE67E22)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  void _moveWeek(int days) {
    setState(() {
      _weekStart = DateTime(
        _weekStart.year,
        _weekStart.month,
        _weekStart.day + days,
      );
      _selectedDay = null;
    });
  }

  /// Thao tác trên thẻ ca trong bảng lịch: phản hồi ca, điểm danh, đổi ca, đóng ca, xem thông tin.
  List<Widget> _cardActions(RowData shift, ShiftPhase phase) {
    final assignmentId = shift['assignment_id'] as int;
    final response = shift['response_status']?.toString() ?? 'accepted';
    final started = !utcTime(shift['starts_at'])
        .isAfter(DateTime.now().toUtc());
    final closure = shift['closure_status']?.toString();
    final canPunch =
        phase == ShiftPhase.notYet ||
        phase == ShiftPhase.working ||
        phase == ShiftPhase.pendingReview;
    final canSwap = phase == ShiftPhase.notYet && !started;
    final canClose =
        phase == ShiftPhase.completed &&
        closure != 'submitted' &&
        closure != 'approved';
    Widget action(
      String label,
      IconData icon,
      VoidCallback onTap, {
      Key? key,
    }) => OutlinedButton.icon(
      key: key,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
    return [
      if (response != 'accepted') ..._responseSection(shift),
      if (closure == 'submitted' || closure == 'approved') ...[
        const SizedBox(height: 8),
        pill(
          closure == 'approved'
              ? '✓ Báo cáo đóng ca đã duyệt'
              : '📷 Đã gửi báo cáo đóng ca',
        ),
      ],
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (canPunch)
            FilledButton.icon(
              key: Key('timeline-punch-$assignmentId'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AttendancePage(repository: r, assignmentId: assignmentId),
                ),
              ).then((_) => _reload()),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.fingerprint_rounded, size: 18),
              label: Text(
                phase == ShiftPhase.working ? 'Điểm danh ra ca' : 'Điểm danh',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (canSwap)
            action(
              'Đổi ca',
              Icons.swap_horiz_rounded,
              () => _requestSwap(assignmentId),
            ),
          if (canClose)
            action(
              'Báo cáo đóng ca',
              Icons.camera_alt_outlined,
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ClosurePage(repository: r, assignmentId: assignmentId),
                ),
              ).then((_) => _reload()),
              key: Key('timeline-close-$assignmentId'),
            ),
          action(
            'Xem thông tin',
            Icons.info_outline_rounded,
            () => _showDayInfo(shift),
            key: Key('shift-info-$assignmentId'),
          ),
        ],
      ),
    ];
  }

  /// Chấp nhận / từ chối ca được phân. Chỉ hỏi khi ca còn chờ phản hồi và chưa bắt đầu.
  Future<void> _respond(int assignmentId, bool accept) async {
    String note = '';
    if (!accept) {
      final controller = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Từ chối ca làm?'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Lý do (bắt buộc)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(c, controller.text.trim());
                }
              },
              child: const Text('Từ chối ca'),
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.dispose();
      if (reason == null || !mounted) return;
      note = reason;
    }
    try {
      await r.respondAssignment(assignmentId, accept, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Đã chấp nhận ca làm.'
                : 'Đã từ chối ca. Quản lý sẽ được báo.',
          ),
        ),
      );
      _reload();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  List<Widget> _responseSection(RowData shift) {
    final response = shift['response_status']?.toString() ?? 'accepted';
    final canRespond =
        response == 'pending' &&
        shift['assignment_status'] == 'assigned' &&
        shift['shift_status'] == 'scheduled' &&
        utcTime(shift['starts_at']).isAfter(DateTime.now().toUtc());
    final (label, color) = switch (response) {
      'pending' => ('Chờ bạn xác nhận', Colors.orange.shade800),
      'rejected' => ('Bạn đã từ chối', Colors.red.shade700),
      _ => ('Đã chấp nhận', green),
    };
    return [
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: Text(label),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
          side: BorderSide(color: color),
          backgroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      ),
      if (canRespond)
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _respond(shift['assignment_id'] as int, true),
                icon: const Icon(Icons.check),
                label: const Text('Chấp nhận'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _respond(shift['assignment_id'] as int, false),
                icon: const Icon(Icons.close),
                label: const Text('Từ chối'),
              ),
            ),
          ],
        ),
    ];
  }

  static const _slotColors = [
    Color(0xFFE67E22),
    Color(0xFF2F6FDE),
    Color(0xFF27AE60),
    Color(0xFF8E44AD),
  ];

  String _hhmm(Object? utc) {
    if (utc == null) return 'Chưa có';
    final d = utcTime(utc).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Bảng thông tin chi tiết toàn bộ ca của ngày chứa [tapped], theo từng thẻ ca.
  /// Hộp chi tiết ca của ngày chứa [tapped] (ca vừa bấm được viền đậm).
  void _showDayInfo(RowData tapped) => _showDayDialog(
    dateOnly(utcTime(tapped['starts_at']).toLocal()),
    highlight: tapped['assignment_id'] as int?,
  );

  /// Hộp chi tiết toàn bộ ca và ngày nghỉ phép đã duyệt của một [day]; dùng cho cả nút "Xem thông
  /// tin" trên thẻ ca và việc bấm một ngày trên lịch tháng.
  void _showDayDialog(DateTime day, {int? highlight}) {
    final dayShifts = [
      for (final s in _allShifts)
        if (dateOnly(utcTime(s['starts_at']).toLocal()) == day) s,
    ]..sort((a, b) => '${a['starts_at']}'.compareTo('${b['starts_at']}'));
    final nowUtc = DateTime.now().toUtc();
    final items = <ShiftDayItem>[];
    for (var i = 0; i < dayShifts.length; i++) {
      final s = dayShifts[i];
      final start = utcTime(s['starts_at']).toLocal();
      final end = utcTime(s['ends_at']).toLocal();
      final mins = end.difference(start).inMinutes;
      final hours = (mins / 60).toStringAsFixed(mins % 60 == 0 ? 0 : 1);
      final responseText = switch ('${s['response_status']}') {
        'accepted' => 'Đã chấp nhận',
        'rejected' => 'Đã từ chối',
        _ => 'Chờ xác nhận',
      };
      final note = '${s['shift_note'] ?? ''}'.trim();
      final reason = '${s['response_note'] ?? ''}'.trim();
      final coworkers = '${s['coworkers'] ?? ''}'.trim();
      // Cùng bộ nhãn trạng thái với bảng lịch: Ca đã hoàn thành / Nghỉ / Chưa vào ca ...
      final phase = phaseStyle(shiftPhase(s, nowUtc));
      final closure = s['closure_status']?.toString();
      final shiftId = s['shift_id'] as int;
      final assignmentId = s['assignment_id'] as int;
      items.add(
        ShiftDayItem(
          slot: 'Ca ${i + 1}',
          color: _slotColors[i % _slotColors.length],
          start: start,
          end: end,
          branch: '${s['branch_name']}',
          code: 'Mã ca #$shiftId',
          title: _shiftTitle(start),
          highlighted: assignmentId == highlight,
          lines: [
            MapEntry('Thời lượng', '$hours tiếng'),
            MapEntry(
              'Phản hồi',
              reason.isEmpty ? responseText : '$responseText ($reason)',
            ),
            MapEntry(
              'Số người',
              '${s['total_assigned'] ?? 0}/${s['required_staff'] ?? 1}',
            ),
            MapEntry('Cùng ca', coworkers.isEmpty ? 'Chưa có' : coworkers),
            MapEntry('Giờ vào', _hhmm(s['check_in_at'])),
            MapEntry('Giờ ra', _hhmm(s['check_out_at'])),
            if (note.isNotEmpty) MapEntry('Ghi chú', note),
          ],
          chips: [
            ShiftChip(phase.label, phase.color, Colors.white),
            if (closure == 'submitted')
              const ShiftChip(
                'ĐÃ GỬI ĐÓNG CA',
                Color(0xFFEBF5FB),
                Color(0xFF2980B9),
              )
            else if (closure == 'approved')
              const ShiftChip(
                'ĐÓNG CA ĐÃ DUYỆT',
                Color(0xFFE8F8F5),
                Color(0xFF27AE60),
              ),
            ShiftChip(
              'Xem chi tiết',
              const Color(0xFF1DBF8B),
              Colors.white,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ShiftPage(
                      repository: r,
                      shiftId: shiftId,
                      assignmentId: assignmentId,
                    ),
                  ),
                ).then((_) => _reload());
              },
            ),
          ],
        ),
      );
    }
    // Ngày nghỉ phép đã duyệt rơi vào ngày này.
    for (final e in buildTimeline(
      shifts: const [],
      leaves: _leaves,
      from: day,
      to: day,
    )) {
      final l = e.leave!;
      final why = '${l['reason'] ?? ''}'.trim();
      items.add(
        ShiftDayItem(
          slot: 'Nghỉ',
          color: leavePhaseStyle.color,
          start: e.start,
          end: e.end,
          boxLabel: 'Loại nghỉ',
          branch: '${l['leave_type_name']}',
          code: 'Nghỉ phép đã được duyệt',
          title: why.isEmpty ? 'Nghỉ phép' : why,
          chips: [
            ShiftChip(
              leavePhaseStyle.label,
              leavePhaseStyle.color,
              Colors.white,
            ),
          ],
        ),
      );
    }
    showShiftDayDialog(context, day: day, items: items);
  }
}
