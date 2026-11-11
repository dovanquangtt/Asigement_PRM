import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/system_notifier.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';
import 'operations_screen.dart';
import 'notifications_screen.dart';
import 'attendance_management_screen.dart';
import 'dashboard_screen.dart';
import 'employee_attendance_history_screen.dart';
import 'shift_swap_screen.dart';
import 'employee_shift_table_screen.dart';
import 'payroll/my_payroll_screen.dart';
import 'schedule_screen.dart';
import 'closures_screen.dart';
import 'home_view.dart';

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.session,
    this.repository,
    this.auth,
  });
  final UserSession session;
  final WorkforceRepository? repository;
  final AuthService? auth;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late final WorkforceRepository repository;
  late Future<Object> loading;
  int tab = 0;
  bool signingOut = false;
  List<(String, IconData, String)> get destinations => [
    ('Trang chủ', Icons.grid_view_outlined, 'home'),
    if (widget.session.role == 'Admin')
      ('Tài khoản', Icons.admin_panel_settings_outlined, 'users'),
    if (widget.session.role != 'Nhân viên')
      ('Nhân sự', Icons.groups_outlined, 'employees'),
    if (widget.session.role != 'Admin') ...[
      ('Lịch ca', Icons.calendar_month_outlined, 'shifts'),
      (
        widget.session.role == 'Quản lý' ? 'Bảng lương' : 'Thu nhập',
        Icons.account_balance_wallet_outlined,
        'payroll',
      ),
    ],
    ('Cá nhân', Icons.person_outline, 'profile'),
  ];
  String get current => destinations[tab].$3;
  Future<void> installDemoData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nạp dữ liệu mẫu?'),
        content: const Text(
          'Bổ sung bộ tình huống DEMO vào database đang dùng. Không xóa dữ liệu, không ghi đè mật khẩu hoặc nạp lặp lại bộ mẫu đã có.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Nạp dữ liệu mẫu'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final added = await repository.installDemoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? 'Đã nạp dữ liệu mẫu cho 3 vai trò.'
                : 'Bộ mẫu đã có; giữ nguyên dữ liệu bạn đã chỉnh.',
          ),
        ),
      );
      await refresh();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không nạp được bộ mẫu vì dữ liệu trùng hoặc không tương thích. Dữ liệu hiện có được giữ nguyên.',
            ),
          ),
        );
      }
    }
  }

  Future<void> openFeature(String kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => kind == 'shift_table'
            ? EmployeeShiftTableScreen(repository: repository)
            : kind == 'dashboard'
            ? DashboardScreen(repository: repository)
            : kind == 'closures'
            ? ClosuresScreen(repository: repository)
            : kind == 'swaps'
            ? ShiftSwapScreen(repository: repository)
            : kind == 'attendance'
            ? EmployeeAttendanceHistoryScreen(repository: repository)
            : kind == 'attendance_review' || kind == 'attendance_management'
            ? AttendanceManagementScreen(
                repository: repository,
                self: widget.session.role == 'Nhân viên',
              )
            : OperationsPage(repository: repository, kind: kind),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> logout() async {
    if (signingOut) return;
    setState(() => signingOut = true);
    await (widget.auth ?? AuthService()).signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => LoginPage(auth: widget.auth)),
      (_) => false,
    );
  }

  Future<void> employeeContract(RowData row) async {
    final operation = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Thêm hợp đồng / lương cơ bản'),
              onTap: () => Navigator.pop(c, 'contract'),
            ),
            if (row['user_id'] == null)
              ListTile(
                title: const Text('Liên kết tài khoản đăng nhập'),
                onTap: () => Navigator.pop(c, 'link'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || operation == null) return;
    if (operation == 'link') {
      final accounts = await repository.unlinkedAccounts();
      if (!mounted) return;
      await featureForm(
        context,
        'Liên kết tài khoản',
        [
          InputSpec(
            'user',
            'Tài khoản chưa có hồ sơ',
            options: {
              for (final a in accounts) '${a['id']}': '${a['username']}',
            },
          ),
        ],
        (v) => repository.linkEmployee(row['id'] as int, int.parse(v['user']!)),
      );
      if (mounted) await refresh();
      return;
    }
    await featureForm(
      context,
      'Hợp đồng nhân viên',
      [
        const InputSpec('number', 'Số hợp đồng'),
        const InputSpec('salary', 'Lương tháng VND', number: true),
        const InputSpec(
          'minutes',
          'Phút chuẩn mỗi tháng',
          value: '12480',
          number: true,
        ),
        const InputSpec('start', 'Ngày hiệu lực YYYY-MM-DD'),
      ],
      (v) => repository.saveContract(
        row['id'] as int,
        v['number']!,
        int.parse(v['salary']!),
        int.parse(v['minutes']!),
        DateTime.parse(v['start']!),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? WorkforceRepository(widget.session);
    loading = load();
    SystemNotifier.instance.init().then((_) => _pollNotifications());
    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollNotifications(),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Timer? _poller;
  int? _lastNotificationId;
  int unread = 0;
  int _scheduleReload = 0;

  /// Kiểm tra thông báo mới và hiện ngay trên màn hình đang mở.
  Future<void> _pollNotifications() async {
    try {
      final rows = await repository.notifications();
      if (!mounted) return;
      final ids = [for (final r in rows) r['id'] as int];
      final newest = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
      final last = _lastNotificationId;
      final unreadRows = rows.where((r) => r['read_at'] == null).toList();
      // Lần kiểm tra đầu tiên (vừa đăng nhập): báo tất cả thông báo chưa đọc.
      final fresh = last == null
          ? unreadRows
          : unreadRows.where((r) => (r['id'] as int) > last).toList();
      setState(() {
        _lastNotificationId = newest;
        unread = unreadRows.length;
        // Có thông báo mới (ví dụ vừa được phân ca): bảng "Lịch ca" tự tải lại.
        if (fresh.isNotEmpty) _scheduleReload++;
      });
      if (fresh.isNotEmpty) {
        _announce(fresh);
        // Có phân ca / hủy ca / kết quả duyệt mới: tải lại màn hình hiện tại.
        refresh();
      }
    } catch (_) {}
  }

  /// Thông báo nổi bật: rung, âm báo và banner nổi có nút "Xem".
  void _announce(List<RowData> fresh) {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    // Đẩy lên thanh thông báo của điện thoại (tối đa 5 thông báo mới nhất mỗi lần).
    for (final n in fresh.take(5)) {
      SystemNotifier.instance.show(
        n['id'] as int,
        '${n['title']}',
        '${n['body']}',
      );
    }
    final top = fresh.first;
    final more = fresh.length > 1
        ? '\n(+${fresh.length - 1} thông báo khác)'
        : '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: green,
          duration: const Duration(seconds: 10),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${top['title']}\n${top['body']}$more',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'XEM',
            textColor: Colors.white,
            onPressed: _openNotifications,
          ),
        ),
      );
  }

  Future<void> _openNotifications() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(repository: repository),
      ),
    );
    if (mounted) await _pollNotifications();
  }

  Future<Object> load() => switch (current) {
    'users' => repository.users(),
    'employees' => repository.employees(),
    'shifts' => repository.shifts(),
    'payroll' => repository.payslips(),
    'profile' => repository.profile(),
    _ => repository.overview(),
  };

  Future<void> refresh() async {
    final future = load();
    setState(() {
      loading = future;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder displays the error. */
    }
  }

  Future<void> create(bool account) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateDialog(repository: repository, account: account),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            account
                ? 'Đã tạo tài khoản. Đăng nhập được ngay và dùng đủ chức năng.'
                : 'Đã thêm nhân viên. Sang mục Tài khoản để cấp tài khoản đăng nhập.',
          ),
        ),
      );
      await refresh();
    }
  }

  /// Tài khoản cũ chưa có hồ sơ: chọn một hồ sơ nhân viên chưa có tài khoản để liên kết.
  Future<void> linkProfile(RowData account) async {
    final candidates = await repository.employeesWithoutAccount();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chưa có hồ sơ nào để liên kết. Hãy thêm nhân viên ở mục Nhân sự trước.',
          ),
        ),
      );
      return;
    }
    await featureForm(
      context,
      'Liên kết hồ sơ cho ${account['username']}',
      [
        InputSpec(
          'employee',
          'Hồ sơ nhân viên',
          options: {
            for (final e in candidates)
              '${e['id']}': '${e['full_name']} • ${e['employee_code']}',
          },
        ),
      ],
      (v) => repository.linkEmployee(
        int.parse(v['employee']!),
        account['id'] as int,
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> editEmployee(RowData row) async {
    await featureForm(
      context,
      'Sửa nhân viên',
      [
        InputSpec(
          'code',
          'Mã nhân viên',
          value: row['employee_code']?.toString() ?? '',
        ),
        InputSpec('name', 'Họ tên', value: row['full_name']?.toString() ?? ''),
        InputSpec(
          'phone',
          'Điện thoại',
          value: row['phone']?.toString() ?? '',
          optional: true,
        ),
      ],
      (v) => repository.updateEmployee(
        row['id'] as int,
        code: v['code']!,
        name: v['name']!,
        phone: v['phone']!,
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> deleteEmployee(RowData row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa nhân viên?'),
        content: Text(
          'Xóa "${row['full_name']}"? Hồ sơ sẽ chuyển sang đã nghỉ việc (giữ lịch sử chấm công và lương), tài khoản đăng nhập bị khóa và nhân viên được gỡ khỏi các ca chưa bắt đầu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Không'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await repository.deleteEmployee(row['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã xóa nhân viên.')));
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không xóa được nhân viên. Hãy thử lại.'),
          ),
        );
      }
    }
    if (mounted) await refresh();
  }

  String value(RowData row, String key) => row[key]?.toString() ?? 'Chưa có';
  String currency(Object? amount) =>
      '${(amount ?? 0).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫';

  List<Widget> content(Object data) {
    if (current == 'home') {
      final row = data as RowData;
      final staff = widget.session.role != 'Nhân viên';
      return [
        HomeView(
          session: widget.session,
          repository: repository,
          overview: row,
          onOpen: openFeature,
          onTab: (key) {
            final index = destinations.indexWhere((d) => d.$3 == key);
            if (index >= 0) {
              setState(() {
                tab = index;
                loading = load();
              });
            }
          },
          features: [
            // Quản lý/Admin quản lý ca và phân ca; nhân viên xem lịch ở tab "Lịch ca".
            if (staff)
              const HomeFeature(
                'schedule',
                'Lịch ca, phân ca & điểm danh',
                Icons.edit_calendar_outlined,
              ),
            if (staff)
              const HomeFeature(
                'payroll',
                'Kỳ lương & tính lương',
                Icons.payments_outlined,
              ),
            const HomeFeature('swaps', 'Đổi ca', Icons.swap_horiz_rounded),
            const HomeFeature(
              'closures',
              'Ảnh & báo cáo đóng ca',
              Icons.photo_camera_outlined,
            ),
            const HomeFeature(
              'attendance',
              'Lịch sử điểm danh',
              Icons.history_rounded,
            ),
            if (staff)
              const HomeFeature(
                'attendance_review',
                'Quản lý chấm công & ngoại lệ',
                Icons.fact_check_outlined,
              ),
            if (!staff)
              const HomeFeature(
                'attendance_management',
                'Công của tôi & yêu cầu sửa công',
                Icons.timer_outlined,
              ),
            if (staff)
              const HomeFeature(
                'shift_table',
                'Bảng ca theo từng nhân viên',
                Icons.table_chart_outlined,
              ),
            if (staff)
              const HomeFeature(
                'leave_review',
                'Duyệt nghỉ phép',
                Icons.beach_access_outlined,
              ),
            if (staff)
              const HomeFeature(
                'dashboard',
                'Dashboard thống kê',
                Icons.insights_outlined,
              ),
            if (staff) ...const [
              HomeFeature(
                'devices',
                'Duyệt thiết bị nhân viên',
                Icons.phone_android_outlined,
              ),
              HomeFeature(
                'branches',
                'Cấu hình GPS & Wi-Fi chi nhánh',
                Icons.location_on_outlined,
              ),
            ],
          ],
        ),
      ];
    }
    if (current == 'profile') {
      final row = data as RowData;
      return [
        heading(
          value(row, 'full_name') == 'Chưa có'
              ? widget.session.username
              : value(row, 'full_name'),
          'HỒ SƠ CỦA BẠN',
        ),
        panel(
          child: Column(
            children: [
              money('Tài khoản', value(row, 'username')),
              money('Vai trò', widget.session.role),
              for (final field in [
                ('Mã nhân viên', 'employee_code'),
                ('Chi nhánh', 'branch_name'),
                ('Điện thoại', 'phone'),
                ('Ngày vào làm', 'hire_date'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(field.$1),
                  subtitle: Text(value(row, field.$2)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: signingOut ? null : logout,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
      ];
    }
    final rows = data as List<RowData>;
    return [
      heading(destinations[tab].$1, widget.session.role.toUpperCase()),
      if (current == 'shifts')
        OutlinedButton(
          onPressed: () => openFeature('schedule'),
          child: const Text('Quản lý ca & điểm danh'),
        ),
      if (current == 'payroll')
        OutlinedButton(
          onPressed: () => openFeature('payroll'),
          child: const Text('Kỳ lương & tính lương 6 bước'),
        ),
      if (current == 'users' || current == 'employees') ...[
        FilledButton.icon(
          onPressed: () => create(current == 'users'),
          icon: const Icon(Icons.add),
          label: Text(current == 'users' ? 'Tạo tài khoản' : 'Thêm nhân viên'),
        ),
        const SizedBox(height: 18),
      ],
      if (rows.isEmpty)
        panel(
          child: Text(switch (current) {
            'shifts' => 'Chưa có phân ca được lưu.',
            'payroll' => 'Chưa có phiếu lương được lưu.',
            _ => 'Chưa có dữ liệu.',
          }),
        ),
      for (final row in rows) ...[
        panel(
          child: switch (current) {
            'users' => ListTile(
              onTap: () async {
                await featureForm(
                  context,
                  'Gmail được phép đăng nhập',
                  [
                    InputSpec(
                      'email',
                      'Gmail của tài khoản',
                      value: row['email']?.toString() ?? '',
                    ),
                  ],
                  (v) => repository.setUserEmail(row['id'] as int, v['email']!),
                );
                if (mounted) await refresh();
              },
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline, color: green),
              title: Text(value(row, 'username')),
              subtitle: Text(
                '${value(row, 'roles')} • ${row['is_active'] == 1 ? 'Hoạt động' : 'Đã khóa'}'
                '\n${row['employee_id'] != null ? 'Hồ sơ: ${row['employee_name']}' : (value(row, 'roles').contains('Admin') ? 'Tài khoản quản trị' : 'Chưa có hồ sơ nhân viên')}',
              ),
              trailing:
                  row['employee_id'] == null &&
                      !value(row, 'roles').contains('Admin')
                  ? TextButton(
                      key: Key('link-profile-${row['id']}'),
                      onPressed: () => linkProfile(row),
                      child: const Text('Liên kết hồ sơ'),
                    )
                  : null,
            ),
            'employees' => ListTile(
              onTap: () => employeeContract(row),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined, color: green),
              title: Text(value(row, 'full_name')),
              subtitle: Text(
                '${value(row, 'employee_code')} • ${value(row, 'branch_name')}\n${value(row, 'phone')}',
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Thao tác',
                onSelected: (v) =>
                    v == 'edit' ? editEmployee(row) : deleteEmployee(row),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Sửa nhân viên')),
                  PopupMenuItem(value: 'delete', child: Text('Xóa nhân viên')),
                ],
              ),
            ),
            'shifts' => ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ShiftPage(
                    repository: repository,
                    shiftId: row['shift_id'] as int,
                    assignmentId: row['assignment_id'] as int,
                  ),
                ),
              ),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule, color: green),
              title: Text(value(row, 'full_name')),
              subtitle: Text(
                '${localTime(row['starts_at'])} — ${localTime(row['ends_at'])} (giờ VN)\n${value(row, 'branch_name')} • ${value(row, 'status')}',
              ),
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value(row, 'full_name')} • ${value(row, 'period_code')}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                money('Tổng thu nhập', currency(row['gross_pay_vnd'])),
                money('Khấu trừ', currency(row['deductions_vnd'])),
                money('Thực lĩnh', currency(row['net_pay_vnd']), bold: true),
                pill(value(row, 'status')),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PayDetailPage(
                        repository: repository,
                        id: row['id'] as int,
                      ),
                    ),
                  ),
                  child: const Text('Chi tiết & 6 bước tính lương'),
                ),
              ],
            ),
          },
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('ANH EM QUÁN • ${widget.session.role}'),
      actions: [
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: signingOut ? null : logout,
          icon: const Icon(Icons.logout),
        ),
        IconButton(
          tooltip: 'Thông báo',
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: _openNotifications,
        ),
        IconButton(
          onPressed: refresh,
          tooltip: 'Cập nhật',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: current == 'shifts'
              ? ScheduleScreen(
                  repository: repository,
                  reloadToken: _scheduleReload,
                )
              : FutureBuilder<Object>(
                  future: loading,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                snapshot.error is AuthException
                                    ? (snapshot.error as AuthException).message
                                    : 'Không đọc được dữ liệu. Hãy thử lại.',
                              ),
                              TextButton(
                                onPressed: refresh,
                                child: const Text('Thử lại'),
                              ),
                              TextButton(
                                onPressed: signingOut ? null : logout,
                                child: const Text('Về đăng nhập'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (current == 'payroll' &&
                        widget.session.role == 'Nhân viên') {
                      return MyPayrollScreen(
                        repository: repository,
                        onRefresh: refresh,
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: content(snapshot.data!),
                      ),
                    );
                  },
                ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (index) => setState(() {
        tab = index;
        loading = load();
      }),
      destinations: [
        for (final destination in destinations)
          NavigationDestination(
            icon: Icon(destination.$2),
            label: destination.$1,
          ),
      ],
    ),
  );
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog({required this.repository, required this.account});
  final WorkforceRepository repository;
  final bool account;
  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

/// Luồng thêm người gồm hai bước tách biệt:
/// 1) "Thêm nhân viên" (mục Nhân sự) tạo hồ sơ đầy đủ; 2) "Tạo tài khoản" (mục Tài khoản) chọn một
/// hồ sơ chưa có tài khoản rồi cấp tên đăng nhập, mật khẩu, vai trò. Tài khoản luôn gắn với hồ sơ có sẵn
/// nên đăng nhập là dùng được mọi chức năng.
class _CreateDialogState extends State<_CreateDialog> {
  final form = GlobalKey<FormState>();
  final code = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final salary = TextEditingController(text: '12480000');
  String role = 'employee';
  int? branchId;
  int? employeeId;
  List<RowData> branches = const [];
  List<RowData> candidates = const [];
  bool loaded = false;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = widget.account
          ? await widget.repository.employeesWithoutAccount()
          : await widget.repository.branches();
      if (!mounted) return;
      setState(() {
        loaded = true;
        if (widget.account) {
          candidates = rows;
          employeeId = rows.isEmpty ? null : rows.first['id'] as int;
        } else {
          branches = rows;
          branchId = rows.isEmpty ? null : rows.first['id'] as int;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          error = 'Không tải được dữ liệu. Hãy đóng và thử lại.';
        });
      }
    }
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    phone.dispose();
    username.dispose();
    password.dispose();
    salary.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.account) {
        await widget.repository.createAccountForEmployee(
          employeeId: employeeId!,
          username: username.text,
          password: password.text,
          role: role,
        );
      } else {
        final pay = salary.text.replaceAll(RegExp(r'[^0-9]'), '');
        await widget.repository.createEmployee(
          code: code.text,
          name: name.text,
          phone: phone.text,
          branchId: branchId,
          monthlySalary: pay.isEmpty ? null : int.parse(pay),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không lưu được dữ liệu. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Không được để trống' : null;

  List<Widget> _accountFields() {
    if (candidates.isEmpty) {
      return const [
        Text(
          'Chưa có nhân viên nào cần tài khoản. Hãy thêm nhân viên ở mục Nhân sự trước (bước 1), rồi quay lại tạo tài khoản (bước 2).',
          key: Key('account-no-employee'),
        ),
      ];
    }
    return [
      const Text('Bước 2: cấp tài khoản cho nhân viên đã có hồ sơ.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: const Key('account-employee'),
        initialValue: employeeId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Nhân viên'),
        items: [
          for (final e in candidates)
            DropdownMenuItem(
              value: e['id'] as int,
              child: Text(
                '${e['full_name']} • ${e['employee_code']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: busy ? null : (v) => setState(() => employeeId = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const Key('account-username'),
        controller: username,
        enabled: !busy,
        decoration: const InputDecoration(labelText: 'Tên đăng nhập'),
        validator: _required,
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const Key('account-password'),
        controller: password,
        enabled: !busy,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Mật khẩu (ít nhất 8 ký tự)',
        ),
        validator: _required,
      ),
      const SizedBox(height: 12),
      // Admin không tạo được tài khoản Admin: chỉ Quản lý hoặc Nhân viên.
      DropdownButtonFormField<String>(
        key: const Key('account-role'),
        initialValue: role,
        decoration: const InputDecoration(labelText: 'Vai trò tài khoản'),
        items: const [
          DropdownMenuItem(value: 'manager', child: Text('Quản lý')),
          DropdownMenuItem(value: 'employee', child: Text('Nhân viên')),
        ],
        onChanged: busy ? null : (v) => setState(() => role = v!),
      ),
    ];
  }

  List<Widget> _employeeFields() => [
    const Text(
      'Bước 1: tạo hồ sơ nhân viên. Tài khoản đăng nhập tạo sau ở mục Tài khoản.',
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('employee-name'),
      controller: name,
      enabled: !busy,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Họ tên'),
      validator: _required,
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('employee-code'),
      controller: code,
      enabled: !busy,
      decoration: const InputDecoration(
        labelText: 'Mã nhân viên (để trống để tự sinh)',
      ),
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('employee-phone'),
      controller: phone,
      enabled: !busy,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(labelText: 'Điện thoại'),
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<int>(
      key: const Key('employee-branch'),
      initialValue: branchId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Chi nhánh'),
      items: [
        for (final b in branches)
          DropdownMenuItem(value: b['id'] as int, child: Text('${b['name']}')),
      ],
      onChanged: busy ? null : (v) => setState(() => branchId = v),
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('employee-salary'),
      controller: salary,
      enabled: !busy,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Lương tháng VND',
        helperText:
            'Dùng để tạo hợp đồng và tính lương; xóa trắng nếu muốn tạo sau.',
        helperMaxLines: 2,
      ),
    ),
    const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text('Hồ sơ có sẵn 12 ngày phép năm, bộ phận Phục vụ.'),
    ),
  ];

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.account ? 'Tạo tài khoản' : 'Thêm nhân viên'),
      content: !loaded
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...(widget.account ? _accountFields() : _employeeFields()),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('create-save'),
          onPressed: busy || !loaded || (widget.account && candidates.isEmpty)
              ? null
              : save,
          child: Text(busy ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    ),
  );
}
