import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/network/api_client.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/attendance/presentation/attendance_home_screen.dart';
import '../features/attendance/presentation/upcoming_shifts_screen.dart';
import '../features/manager/presentation/manager_dashboard_screen.dart';
import '../features/notifications/notifications_api_screen.dart';
import '../features/schedule/presentation/schedule_management_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../services/system_notifier.dart';

/// Home of the app when it runs against the Spring Boot API: a role based first tab
/// (employee attendance, manager or admin dashboard) and an account tab with sign-out.
/// An expired token (HTTP 401) sends the user back to the login screen.
class BackendShell extends StatefulWidget {
  const BackendShell({super.key, required this.session, this.auth});
  final UserSession session;
  final AuthService? auth;
  @override
  State<BackendShell> createState() => _BackendShellState();
}

class _BackendShellState extends State<BackendShell> {
  int tab = 0;
  bool signingOut = false;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.onUnauthorized = () =>
        _leave('Phiên đăng nhập đã hết hạn.');
    SystemNotifier.instance.init().then((_) => _pollNotifications());
    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollNotifications(),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    ApiClient.instance.onUnauthorized = null;
    super.dispose();
  }

  Timer? _poller;
  int? _lastNotificationId;
  int _unread = 0;
  bool _polling = false;

  /// Số tăng mỗi khi có thông báo mới; dùng làm key để các tab tải lại dữ liệu.
  int _refreshTick = 0;

  /// Hỏi server thông báo mới; có thì đẩy lên thanh trạng thái điện thoại và tải lại các tab.
  Future<void> _pollNotifications() async {
    if (_polling || signingOut || !mounted) return;
    _polling = true;
    try {
      final rows = (await ApiClient.instance.getList('/api/notifications'))
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      final unreadRows = rows.where((r) => r['read_at'] == null).toList();
      final ids = [for (final r in rows) (r['id'] as num).toInt()];
      final newest = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
      final last = _lastNotificationId;
      final fresh = last == null
          ? unreadRows
          : unreadRows.where((r) => (r['id'] as num).toInt() > last).toList();
      setState(() {
        _lastNotificationId = newest;
        _unread = unreadRows.length;
        if (fresh.isNotEmpty) _refreshTick++;
      });
      if (fresh.isNotEmpty) _announce(fresh);
    } catch (_) {
      // Mất mạng hoặc token hết hạn được xử lý ở nơi khác; thử lại ở lần sau.
    } finally {
      _polling = false;
    }
  }

  void _announce(List<Map<String, dynamic>> fresh) {
    HapticFeedback.heavyImpact();
    for (final n in fresh.take(5)) {
      SystemNotifier.instance.show(
        (n['id'] as num).toInt(),
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
          duration: const Duration(seconds: 8),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('${top['title']}\n${top['body']}$more')),
            ],
          ),
        ),
      );
  }

  Future<void> _leave([String? notice]) async {
    if (signingOut || !mounted) return;
    setState(() => signingOut = true);
    await (widget.auth ?? AuthService()).signOut();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => LoginPage(auth: widget.auth)),
      (_) => false,
    );
    if (notice != null) {
      messenger.showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Widget get _work {
    final permissions = widget.session.permissions;
    if (permissions.contains('users.manage')) {
      return const AdminDashboardScreen();
    }
    if (permissions.contains('attendance.review')) {
      return const ManagerDashboardScreen();
    }
    return const AttendanceHomeScreen();
  }

  String get _workLabel {
    final permissions = widget.session.permissions;
    if (permissions.contains('users.manage')) return 'Quản trị';
    if (permissions.contains('attendance.review')) return 'Quản lý';
    return 'Chấm công';
  }

  bool get _isEmployee =>
      !widget.session.permissions.contains('attendance.review') &&
      !widget.session.permissions.contains('users.manage');

  Widget _account() {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(s.displayName),
            subtitle: Text('${s.role} · ${s.username}'),
          ),
          if (s.profile['employee_code'] != null)
            ListTile(
              title: const Text('Mã nhân viên'),
              subtitle: Text('${s.profile['employee_code']}'),
            ),
          if (s.profile['branch_name'] != null)
            ListTile(
              title: const Text('Chi nhánh'),
              subtitle: Text('${s.profile['branch_name']}'),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: signingOut ? null : _leave,
            icon: const Icon(Icons.logout),
            label: Text(signingOut ? 'Đang đăng xuất…' : 'Đăng xuất'),
          ),
        ],
      ),
    );
  }

  /// Tabs shown for this role, in order: (screen, destination). Indices stay consistent because
  /// the body and the navigation bar are both built from this one list.
  List<(Widget, NavigationDestination)> get _tabs => [
    (
      _work,
      NavigationDestination(
        icon: const Icon(Icons.how_to_reg_outlined),
        selectedIcon: const Icon(Icons.how_to_reg),
        label: _workLabel,
      ),
    ),
    if (widget.session.permissions.contains('shifts.manage'))
      (
        const ScheduleManagementScreen(),
        const NavigationDestination(
          icon: Icon(Icons.calendar_view_week_outlined),
          selectedIcon: Icon(Icons.calendar_view_week),
          label: 'Phân ca',
        ),
      ),
    if (_isEmployee)
      (
        const UpcomingShiftsScreen(),
        const NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: 'Lịch ca',
        ),
      ),
    (
      const NotificationsApiScreen(),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: _unread > 0,
          label: Text('$_unread'),
          child: const Icon(Icons.notifications_none),
        ),
        selectedIcon: const Icon(Icons.notifications),
        label: 'Thông báo',
      ),
    ),
    (
      _account(),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Tài khoản',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          // Key đổi khi có thông báo mới để ca làm, lịch phân ca và thông báo tự tải lại.
          for (final t in tabs)
            KeyedSubtree(
              key: ValueKey('${t.$1.runtimeType}-$_refreshTick'),
              child: t.$1,
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [for (final t in tabs) t.$2],
      ),
    );
  }
}
