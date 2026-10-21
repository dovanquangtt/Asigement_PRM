import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import 'operations_screen.dart';
import '../state/workspace_controller.dart';
import '../services/workspace_actions.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.repository,
    this.controller,
    this.actions,
  });

  final WorkforceRepository repository;
  final WorkspaceController? controller;
  final WorkspaceActions? actions;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  WorkforceRepository get r => widget.repository;

  late Future<(List<RowData>, List<RowData>)> _loading;
  int? _selectedDayIndex; // null = Tất cả ngày
  String _statusFilter = 'all'; // 'all', 'upcoming', 'completed'

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _loading = _fetchData();
    });
  }

  Future<(List<RowData>, List<RowData>)> _fetchData() async {
    final shifts = await r.employeeSchedule();
    final leaves = await r.employeeLeaveRequests();
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

    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
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
          options: {
            for (final t in types) '${t['id']}': '${t['name']}',
          },
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
    final options = await r.swapOptions(ownAssignmentId);
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có ca phù hợp để gửi yêu cầu đổi ca lúc này.'),
        ),
      );
      return;
    }

    await featureForm(
      context,
      'Gửi yêu cầu đổi ca',
      [
        InputSpec(
          'target',
          'Chọn ca muốn đổi',
          options: {
            for (final a in options)
              '${a['id']}': '${a['full_name']} • ${localTime(a['starts_at'])}',
          },
        ),
        const InputSpec('reason', 'Lý do đổi ca'),
      ],
      (v) => r.requestSwap(
        ownAssignmentId,
        int.parse(v['target']!),
        v['reason']!,
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

  IconData _shiftIcon(DateTime start) {
    final hour = start.hour;
    if (hour < 12) return Icons.wb_sunny_rounded;
    if (hour < 17) return Icons.wb_twilight_rounded;
    return Icons.bedtime_rounded;
  }

  Color _shiftColor(DateTime start) {
    final hour = start.hour;
    if (hour < 12) return const Color(0xFFD35400); // Amber orange
    if (hour < 17) return const Color(0xFFE67E22); // Coral
    return const Color(0xFF2C3E50); // Deep Blue
  }

  DateTime _mondayOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  @override
  Widget build(BuildContext context) {
    final nowVn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final startOfWeek = _mondayOfWeek(nowVn);

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

        // Lọc ca làm
        final filteredShifts = allShifts.where((s) {
          final dt = utcTime(s['starts_at']).add(const Duration(hours: 7));
          if (_selectedDayIndex != null) {
            final weekdayIndex = dt.weekday - 1; // 0..6
            if (weekdayIndex != _selectedDayIndex) return false;
          }

          if (_statusFilter == 'upcoming') {
            return utcTime(s['starts_at']).isAfter(nowUtc) &&
                s['shift_status'] != 'cancelled';
          } else if (_statusFilter == 'completed') {
            return utcTime(s['ends_at']).isBefore(nowUtc) ||
                s['shift_status'] == 'completed';
          }
          return true;
        }).toList();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              heading('Lịch ca làm của bạn', 'LỊCH PHÂN CÔNG & XIN NGHỈ'),

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

              // 2. Thanh chọn thứ trong tuần có hiển thị ngày thực tế
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lịch theo thứ trong tuần',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (_selectedDayIndex != null)
                    InkWell(
                      onTap: () => setState(() => _selectedDayIndex = null),
                      child: const Text(
                        'Xem tất cả',
                        style: TextStyle(
                          color: green,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Strip ngày thứ T2 -> CN
              Row(
                children: [
                  // Nút Tất cả
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color:
                              _selectedDayIndex == null ? green : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _selectedDayIndex == null
                                ? green
                                : const Color(0xFFE8EDE7),
                          ),
                          boxShadow: _selectedDayIndex == null
                              ? [
                                  BoxShadow(
                                    color: green.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedDayIndex = null),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                Text(
                                  'TẤT CẢ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: _selectedDayIndex == null
                                        ? Colors.white
                                        : Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Icon(
                                  Icons.clear_all_rounded,
                                  size: 18,
                                  color: _selectedDayIndex == null
                                      ? Colors.white
                                      : ink,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Nút T2 -> CN với ngày thực tế
                  for (int i = 0; i < 7; i++) ...[
                    Builder(
                      builder: (_) {
                        final dayDate = startOfWeek.add(Duration(days: i));
                        final isToday = dayDate.year == nowVn.year &&
                            dayDate.month == nowVn.month &&
                            dayDate.day == nowVn.day;
                        final isSelected = _selectedDayIndex == i;

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: isSelected ? green : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? green
                                      : isToday
                                      ? green.withValues(alpha: 0.5)
                                      : const Color(0xFFE8EDE7),
                                  width: isToday && !isSelected ? 1.5 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: green.withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _selectedDayIndex = i),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Column(
                                    children: [
                                      Text(
                                        ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i],
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${dayDate.day}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected
                                              ? Colors.white
                                              : isToday
                                              ? green
                                              : ink,
                                        ),
                                      ),
                                      if (isToday && !isSelected) ...[
                                        const SizedBox(height: 2),
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: const BoxDecoration(
                                            color: green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Filter theo trạng thái
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Tất cả ca', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Ca sắp tới', 'upcoming'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Ca đã xong', 'completed'),
                  ],
                ),
              ),

              section(
                _selectedDayIndex == null
                    ? 'Danh sách phân ca'
                    : 'Ca làm Thứ ${['2', '3', '4', '5', '6', '7', 'Chủ nhật'][_selectedDayIndex!]} (${startOfWeek.add(Duration(days: _selectedDayIndex!)).day}/${startOfWeek.add(Duration(days: _selectedDayIndex!)).month})',
              ),

              if (filteredShifts.isEmpty)
                panel(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF0F5EA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.free_breakfast_outlined,
                            size: 36,
                            color: green,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _selectedDayIndex != null
                              ? 'Bạn không có ca làm vào ngày này.'
                              : 'Không tìm thấy ca làm phù hợp.',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hãy tận dụng thời gian để nghỉ ngơi và thư giãn!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final shift in filteredShifts) ...[
                  _buildShiftCard(context, shift),
                  const SizedBox(height: 16),
                ],

              // 3. Phần yêu cầu xin nghỉ phép
              section('Yêu cầu xin nghỉ phép của bạn'),
              if (leaves.isEmpty)
                panel(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5EA),
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
                                color: const Color(0xFFF0F5EA),
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
                            _buildStatusPill(leave['status']?.toString() ?? 'pending'),
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

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: green,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? green : const Color(0xFFE8EDE7),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : ink,
      ),
      onSelected: (selected) {
        if (selected) setState(() => _statusFilter = value);
      },
    );
  }

  Widget _buildStatusPill(String status) {
    final (label, bg, fg) = switch (status) {
      'approved' => ('Đã duyệt', const Color(0xFFE8F8F5), const Color(0xFF27AE60)),
      'rejected' => ('Từ chối', const Color(0xFFFDEDEC), const Color(0xFFC0392B)),
      'cancelled' => ('Đã hủy', const Color(0xFFF2F4F4), const Color(0xFF7F8C8D)),
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildShiftCard(BuildContext context, RowData shift) {
    final startVn = utcTime(shift['starts_at']).add(const Duration(hours: 7));
    final endVn = utcTime(shift['ends_at']).add(const Duration(hours: 7));
    final durationMins = endVn.difference(startVn).inMinutes;
    final durationHoursStr = (durationMins / 60).toStringAsFixed(
      durationMins % 60 == 0 ? 0 : 1,
    );

    final title = _shiftTitle(startVn);
    final icon = _shiftIcon(startVn);
    final iconColor = _shiftColor(startVn);

    final shiftStatus = shift['shift_status']?.toString() ?? 'scheduled';
    final assignmentId = shift['assignment_id'] as int;
    final shiftId = shift['shift_id'] as int;
    final coworkersStr = shift['coworkers']?.toString() ?? '';
    final lastAttendance = shift['last_attendance_event']?.toString();
    final closureStatus = shift['closure_status']?.toString();

    final nowUtc = DateTime.now().toUtc();
    final isPast = utcTime(shift['ends_at']).isBefore(nowUtc);
    final isInProgress =
        utcTime(shift['starts_at']).isBefore(nowUtc) && !isPast;

    final List<String> coworkersList = coworkersStr.isNotEmpty
        ? coworkersStr.split(', ').where((c) => c.trim().isNotEmpty).toList()
        : [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8EDE7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thanh viền màu thể hiện loại ca
              Container(width: 6, color: iconColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header ca làm
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: iconColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                                Text(
                                  'Chi nhánh: ${shift['branch_name']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildShiftBadge(
                            isInProgress: isInProgress,
                            isPast: isPast,
                            status: shiftStatus,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Giờ làm việc & Khung thời lượng
                      Row(
                        children: [
                          Text(
                            '${startVn.hour.toString().padLeft(2, '0')}:${startVn.minute.toString().padLeft(2, '0')} — ${endVn.hour.toString().padLeft(2, '0')}:${endVn.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: ink,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F5EA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$durationHoursStr tiếng',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Ngày dương lịch
                      Text(
                        'Thứ ${startVn.weekday == 7 ? 'Chủ nhật' : startVn.weekday + 1}, ngày ${startVn.day.toString().padLeft(2, '0')}/${startVn.month.toString().padLeft(2, '0')}/${startVn.year}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),

                      if (shift['shift_note'] != null &&
                          shift['shift_note'].toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: muted,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${shift['shift_note']}',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const Divider(height: 24),

                      // Đồng nghiệp cùng ca
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.group_outlined,
                            size: 18,
                            color: green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: coworkersList.isNotEmpty
                                ? Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      const Text(
                                        'Cùng ca:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      for (final name in coworkersList)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF4F6F4),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '👤 $name',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: ink,
                                            ),
                                          ),
                                        ),
                                    ],
                                  )
                                : const Text(
                                    'Chưa có đồng nghiệp khác ghép ca',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                          ),
                        ],
                      ),

                      // Trạng thái điểm danh / đóng ca nếu có
                      if (lastAttendance != null || closureStatus != null) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (lastAttendance == 'check_in')
                              pill('✓ Đã điểm danh vào ca')
                            else if (lastAttendance == 'check_out')
                              pill('✓ Đã điểm danh ra ca'),
                            if (closureStatus == 'submitted')
                              pill('📷 Đã gửi báo cáo đóng ca')
                            else if (closureStatus == 'approved')
                              pill('✓ Báo cáo đóng ca đã duyệt'),
                          ],
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Hàng nút thao tác chính/phụ
                      Row(
                        children: [
                          // Nút chính: Điểm danh hoặc Báo cáo đóng ca
                          Expanded(
                            flex: 3,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => AttendancePage(
                                    repository: r,
                                    assignmentId: assignmentId,
                                  ),
                                ),
                              ).then((_) => _reload()),
                              style: FilledButton.styleFrom(
                                backgroundColor: isInProgress ? green : ink,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.fingerprint_rounded,
                                  size: 20),
                              label: Text(
                                isInProgress ? 'Điểm danh vào/ra ca' : 'Điểm danh',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Nút Đổi ca
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: () => _requestSwap(assignmentId),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.swap_horiz_rounded,
                                  size: 18),
                              label: const Text(
                                'Đổi ca',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          // Nút Đóng ca
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ClosurePage(
                                    repository: r,
                                    assignmentId: assignmentId,
                                  ),
                                ),
                              ).then((_) => _reload()),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.camera_alt_outlined,
                                  size: 18),
                              label: const Text(
                                'Báo cáo & đóng ca',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Nút Xem chi tiết ca
                          InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ShiftPage(
                                  repository: r,
                                  shiftId: shiftId,
                                  assignmentId: assignmentId,
                                ),
                              ),
                            ).then((_) => _reload()),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F5EA),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShiftBadge({
    required bool isInProgress,
    required bool isPast,
    required String status,
  }) {
    final (label, bg, fg) = switch (status) {
      'cancelled' => ('Đã hủy', const Color(0xFFFDEDEC), const Color(0xFFC0392B)),
      _ when isInProgress => (
        'Đang diễn ra',
        const Color(0xFFE8F8F5),
        const Color(0xFF27AE60)
      ),
      _ when isPast || status == 'completed' => (
        'Hoàn thành',
        const Color(0xFFF2F4F4),
        const Color(0xFF7F8C8D)
      ),
      _ => ('Sắp tới', const Color(0xFFEBF5FB), const Color(0xFF2980B9)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isInProgress) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
