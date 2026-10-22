import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import 'operations_screen.dart';

class ManagerScheduleScreen extends StatefulWidget {
  const ManagerScheduleScreen({
    super.key,
    required this.repository,
  });

  final WorkforceRepository repository;

  @override
  State<ManagerScheduleScreen> createState() => _ManagerScheduleScreenState();
}

class _ManagerScheduleScreenState extends State<ManagerScheduleScreen> {
  WorkforceRepository get r => widget.repository;

  late Future<List<RowData>> _loading;
  int? _selectedDayIndex; // null = tất cả
  String _statusFilter = 'all'; // 'all', 'understaffed', 'in_progress', 'upcoming', 'completed'
  int? _selectedBranchId; // null = tất cả chi nhánh

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _loading = r.managerShiftOverview(branchId: _selectedBranchId);
    });
  }

  DateTime _mondayOfWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
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
    if (hour < 12) return const Color(0xFFD35400);
    if (hour < 17) return const Color(0xFFE67E22);
    return const Color(0xFF2C3E50);
  }

  Future<void> _showCreateShiftDialog() async {
    final branches = await r.branches();
    if (!mounted) return;
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần tạo chi nhánh trước khi phân ca.')),
      );
      return;
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateShiftModal(repository: r, branches: branches),
    );

    if (created == true && mounted) {
      _reload();
    }
  }

  Future<void> _showAssignDialog(int shiftId, String shiftTitleText) async {
    final assigned = await showDialog<bool>(
      context: context,
      builder: (_) => _AssignEmployeeModal(
        repository: r,
        shiftId: shiftId,
        shiftTitle: shiftTitleText,
      ),
    );

    if (assigned == true && mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nowVn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final startOfWeek = _mondayOfWeek(nowVn);

    return FutureBuilder<List<RowData>>(
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
                        : 'Không tải được danh sách ca làm quản lý.',
                    textAlign: TextAlign.center,
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

        final allShifts = snapshot.data!;

        // Tính toán thống kê
        int totalAssigned = 0;
        int totalRequired = 0;
        int understaffedCount = 0;
        final nowUtc = DateTime.now().toUtc();

        for (final s in allShifts) {
          final assigned = (s['assigned_count'] as int?) ?? 0;
          final required = (s['required_staff'] as int?) ?? 1;
          totalAssigned += assigned;
          totalRequired += required;
          if (assigned < required && s['status'] != 'cancelled') {
            understaffedCount++;
          }
        }

        final fillRate = totalRequired > 0
            ? ((totalAssigned / totalRequired) * 100).round()
            : 0;

        // Lọc danh sách ca
        final filteredShifts = allShifts.where((s) {
          final dt = utcTime(s['starts_at']).add(const Duration(hours: 7));
          if (_selectedDayIndex != null) {
            final weekdayIndex = dt.weekday - 1; // 0..6
            if (weekdayIndex != _selectedDayIndex) return false;
          }

          final assigned = (s['assigned_count'] as int?) ?? 0;
          final required = (s['required_staff'] as int?) ?? 1;
          final startUtc = utcTime(s['starts_at']);
          final endUtc = utcTime(s['ends_at']);
          final isPast = endUtc.isBefore(nowUtc);
          final isInProgress = startUtc.isBefore(nowUtc) && !isPast;

          if (_statusFilter == 'understaffed') {
            return assigned < required && s['status'] != 'cancelled';
          } else if (_statusFilter == 'in_progress') {
            return isInProgress && s['status'] != 'cancelled';
          } else if (_statusFilter == 'upcoming') {
            return startUtc.isAfter(nowUtc) && s['status'] != 'cancelled';
          } else if (_statusFilter == 'completed') {
            return isPast || s['status'] == 'completed';
          }
          return true;
        }).toList();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              heading('Quản lý phân ca làm', 'THEO DÕI ĐỘI NGU & PHÂN CA'),

              // 1. Nút Tạo Ca Làm Mới
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _showCreateShiftDialog,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                  label: const Text(
                    'Tạo phân ca làm việc mới',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 2. Thẻ Thống Kê Tổng Quan
              Row(
                children: [
                  Expanded(
                    child: metric(
                      'Tổng ca phân',
                      '${allShifts.length}',
                      'ca',
                      Icons.calendar_month_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: metric(
                      'Tỷ lệ lấp đầy',
                      '$fillRate%',
                      '$totalAssigned/$totalRequired',
                      Icons.people_alt_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: metric(
                      'Ca thiếu người',
                      '$understaffedCount',
                      'ca',
                      Icons.warning_amber_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // 3. Thanh Chọn Ngày Trong Tuần
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lịch phân ca theo thứ',
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
                        'Xem tất cả ngày',
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

              // Strip Ngày T2 -> CN
              Row(
                children: [
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

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Tất cả', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('⚠️ Ca thiếu người', 'understaffed'),
                    const SizedBox(width: 8),
                    _buildFilterChip('🟢 Đang diễn ra', 'in_progress'),
                    const SizedBox(width: 8),
                    _buildFilterChip('🔵 Sắp tới', 'upcoming'),
                    const SizedBox(width: 8),
                    _buildFilterChip('⚪ Đã xong', 'completed'),
                  ],
                ),
              ),

              section(
                _selectedDayIndex == null
                    ? 'Danh sách phân ca toàn hệ thống'
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
                            Icons.calendar_today_outlined,
                            size: 36,
                            color: green,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _selectedDayIndex != null
                              ? 'Không có phân ca làm nào trong ngày được chọn.'
                              : 'Chưa có phân ca làm việc phù hợp điều kiện lọc.',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Nhấn "Tạo phân ca làm việc mới" ở trên để phân công nhân sự.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final shift in filteredShifts) ...[
                  _buildManagerShiftCard(context, shift),
                  const SizedBox(height: 16),
                ],
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

  Widget _buildManagerShiftCard(BuildContext context, RowData shift) {
    final startVn = utcTime(shift['starts_at']).add(const Duration(hours: 7));
    final endVn = utcTime(shift['ends_at']).add(const Duration(hours: 7));
    final durationMins = endVn.difference(startVn).inMinutes;
    final durationHoursStr = (durationMins / 60).toStringAsFixed(
      durationMins % 60 == 0 ? 0 : 1,
    );

    final title = _shiftTitle(startVn);
    final icon = _shiftIcon(startVn);
    final iconColor = _shiftColor(startVn);

    final shiftId = shift['id'] as int;
    final assignedCount = (shift['assigned_count'] as int?) ?? 0;
    final requiredStaff = (shift['required_staff'] as int?) ?? 1;
    final assignedStaffNames = shift['assigned_staff_names']?.toString() ?? '';
    final isUnderstaffed = assignedCount < requiredStaff;

    final nowUtc = DateTime.now().toUtc();
    final isPast = utcTime(shift['ends_at']).isBefore(nowUtc);
    final isInProgress =
        utcTime(shift['starts_at']).isBefore(nowUtc) && !isPast;

    final List<String> staffList = assignedStaffNames.isNotEmpty
        ? assignedStaffNames.split(', ').where((s) => s.trim().isNotEmpty).toList()
        : [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isUnderstaffed && shift['status'] != 'cancelled'
              ? Colors.amber.shade400
              : const Color(0xFFE8EDE7),
          width: isUnderstaffed && shift['status'] != 'cancelled' ? 1.5 : 1,
        ),
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
              // Thanh viền bên trái
              Container(width: 6, color: iconColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card
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
                                  '$title • CA #${shift['id']}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                                Text(
                                  '${shift['branch_name']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Pill nhân sự (Đủ người vs Thiếu người)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isUnderstaffed
                                  ? const Color(0xFFFEF5E7)
                                  : const Color(0xFFE8F8F5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isUnderstaffed
                                  ? '⚠️ Thiếu ($assignedCount/$requiredStaff)'
                                  : '✓ Đủ ($assignedCount/$requiredStaff)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isUnderstaffed
                                    ? const Color(0xFFD35400)
                                    : const Color(0xFF27AE60),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Giờ làm việc & Khung thời lượng
                      Row(
                        children: [
                          Text(
                            '${startVn.hour.toString().padLeft(2, '0')}:${startVn.minute.toString().padLeft(2, '0')} — ${endVn.hour.toString().padLeft(2, '0')}:${endVn.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 22,
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

                      if (shift['note'] != null &&
                          shift['note'].toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Ghi chú: ${shift['note']}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],

                      const Divider(height: 22),

                      // Danh sách nhân viên đã phân
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
                            child: staffList.isNotEmpty
                                ? Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      for (final name in staffList)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF0F5EA),
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
                                    'Chưa có nhân viên nào được phân vào ca này',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Nút hành động quản lý
                      Row(
                        children: [
                          // Nút Phân ca nhanh
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _showAssignDialog(
                                shiftId,
                                '$title • ${startVn.day}/${startVn.month}',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: isUnderstaffed ? green : ink,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Phân ca nhân viên',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Nút Xem chi tiết & Nhân viên
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ShiftPage(
                                  repository: r,
                                  shiftId: shiftId,
                                ),
                              ),
                            ).then((_) => _reload()),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                            ),
                            label: const Text(
                              'Chi tiết',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
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
}

/// Modal Phân ca thông minh (hiển thị nhân viên khả dụng & xung đột)
class _AssignEmployeeModal extends StatefulWidget {
  const _AssignEmployeeModal({
    required this.repository,
    required this.shiftId,
    required this.shiftTitle,
  });

  final WorkforceRepository repository;
  final int shiftId;
  final String shiftTitle;

  @override
  State<_AssignEmployeeModal> createState() => _AssignEmployeeModalState();
}

class _AssignEmployeeModalState extends State<_AssignEmployeeModal> {
  late Future<List<RowData>> _loading;
  String _searchQuery = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _loading = widget.repository.eligibleEmployeesForShift(widget.shiftId);
    });
  }

  Future<void> _assign(int employeeId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.assignShift(widget.shiftId, employeeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Đã phân nhân viên vào ca thành công!')),
        );
        Navigator.pop(context, true);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không phân ca được. Hãy thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Phân ca: ${widget.shiftTitle}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search field
              TextField(
                decoration: InputDecoration(
                  hintText: 'Tìm nhân viên theo tên hoặc mã...',
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 14),

              Expanded(
                child: FutureBuilder<List<RowData>>(
                  future: _loading,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData && !snapshot.hasError) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          snapshot.error is AuthException
                              ? (snapshot.error as AuthException).message
                              : 'Không tải được danh sách nhân viên.',
                        ),
                      );
                    }

                    final employees = snapshot.data!;
                    final filtered = employees.where((e) {
                      if (_searchQuery.isEmpty) return true;
                      final name = e['full_name']?.toString().toLowerCase() ?? '';
                      final code = e['employee_code']?.toString().toLowerCase() ?? '';
                      return name.contains(_searchQuery) || code.contains(_searchQuery);
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          'Không tìm thấy nhân viên phù hợp.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final emp = filtered[index];
                        final empId = emp['id'] as int;
                        final name = emp['full_name']?.toString() ?? '';
                        final code = emp['employee_code']?.toString() ?? '';
                        final isAvailable = (emp['is_available'] as bool?) ?? false;
                        final conflictReason = emp['conflict_reason']?.toString();
                        final isAssigned = (emp['is_already_assigned'] as bool?) ?? false;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isAssigned
                                ? const Color(0xFFF4F6F4)
                                : isAvailable
                                ? Colors.white
                                : const Color(0xFFFFF8F8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isAssigned
                                  ? const Color(0xFFE8EDE7)
                                  : isAvailable
                                  ? green.withValues(alpha: 0.3)
                                  : Colors.red.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isAvailable ? green : Colors.grey,
                                foregroundColor: Colors.white,
                                radius: 18,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'N',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Mã: $code',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    if (conflictReason != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '⚠️ $conflictReason',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isAssigned
                                              ? green
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isAvailable)
                                FilledButton(
                                  onPressed: _busy ? null : () => _assign(empId),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: green,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Phân ca'),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal Tạo phân ca mới
class _CreateShiftModal extends StatefulWidget {
  const _CreateShiftModal({
    required this.repository,
    required this.branches,
  });

  final WorkforceRepository repository;
  final List<RowData> branches;

  @override
  State<_CreateShiftModal> createState() => _CreateShiftModalState();
}

class _CreateShiftModalState extends State<_CreateShiftModal> {
  late int branchId;
  int templateIndex = 0; // 0=Ca Sáng, 1=Ca Chiều, 2=Ca Tối, 3=Tùy chỉnh
  DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
  int startHour = 8;
  int endHour = 16;
  final staffController = TextEditingController(text: '2');
  final noteController = TextEditingController(text: 'Khu vực Tầng 1 • Phục vụ bàn');
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    branchId = widget.branches.first['id'] as int;
  }

  @override
  void dispose() {
    staffController.dispose();
    noteController.dispose();
    super.dispose();
  }

  void _applyTemplate(int index) {
    setState(() {
      templateIndex = index;
      switch (index) {
        case 0:
          startHour = 8;
          endHour = 16;
          break;
        case 1:
          startHour = 12;
          endHour = 20;
          break;
        case 2:
          startHour = 16;
          endHour = 23;
          break;
      }
    });
  }

  Future<void> _submit() async {
    final staff = int.tryParse(staffController.text);
    if (staff == null || staff < 1) {
      setState(() => error = 'Số nhân viên cần phải lớn hơn 0.');
      return;
    }

    final start = DateTime.utc(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      startHour - 7, // Convert VN (+7) to UTC
      0,
    );
    final end = DateTime.utc(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      endHour - 7,
      0,
    );

    if (!end.isAfter(start)) {
      setState(() => error = 'Giờ kết thúc phải sau giờ bắt đầu.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await widget.repository.createShift(
        branchId: branchId,
        start: start,
        end: end,
        requiredStaff: staff,
        note: noteController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Đã tạo ca làm việc mới thành công!')),
        );
        Navigator.pop(context, true);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Không tạo được ca làm. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline_rounded, color: green),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Tạo phân ca làm việc mới',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Chọn Chi nhánh
                DropdownButtonFormField<int>(
                  value: branchId,
                  decoration: InputDecoration(
                    labelText: 'Chi nhánh',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: [
                    for (final b in widget.branches)
                      DropdownMenuItem(
                        value: b['id'] as int,
                        child: Text('${b['name']}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => branchId = v);
                  },
                ),
                const SizedBox(height: 14),

                // Chọn Ngày
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 7)),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F5EA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: green),
                        const SizedBox(width: 12),
                        Text(
                          'Ngày làm: $dateStr',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: ink,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Đổi ngày',
                          style: TextStyle(
                            color: green,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Chọn Mẫu Ca
                const Text(
                  'Mẫu ca chuẩn:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildTemplateChip('☀️ Ca Sáng', 0),
                    const SizedBox(width: 6),
                    _buildTemplateChip('🌅 Ca Chiều', 1),
                    const SizedBox(width: 6),
                    _buildTemplateChip('🌙 Ca Tối', 2),
                  ],
                ),
                const SizedBox(height: 14),

                // Giờ làm
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: '$startHour:00'),
                        decoration: InputDecoration(
                          labelText: 'Giờ bắt đầu',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        readOnly: templateIndex != 3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: '$endHour:00'),
                        decoration: InputDecoration(
                          labelText: 'Giờ kết thúc',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        readOnly: templateIndex != 3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Số lượng nhân viên cần
                TextField(
                  controller: staffController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Số nhân viên cần',
                    hintText: 'Nhập số nhân viên...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Ghi chú / Vị trí
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: 'Ghi chú / Vị trí phân công',
                    hintText: 'Ví dụ: Phục vụ tầng 1...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: busy ? null : () => Navigator.pop(context),
                        child: const Text('Hủy'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : _submit,
                        child: Text(busy ? 'Đang tạo...' : 'Tạo ca làm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateChip(String label, int index) {
    final isSelected = templateIndex == index;
    return Expanded(
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : ink,
          ),
        ),
        selected: isSelected,
        selectedColor: green,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: isSelected ? green : const Color(0xFFE8EDE7),
        ),
        onSelected: (s) {
          if (s) _applyTemplate(index);
        },
      ),
    );
  }
}
