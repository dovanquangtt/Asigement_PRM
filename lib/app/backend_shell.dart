import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/attendance/presentation/attendance_home_screen.dart';
import '../features/attendance/presentation/upcoming_shifts_screen.dart';
import '../features/manager/presentation/manager_dashboard_screen.dart';
import '../features/notifications/notifications_api_screen.dart';
import '../features/schedule/presentation/schedule_management_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';

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
    ApiClient.instance.onUnauthorized = () => _leave('Phiên đăng nhập đã hết hạn.');
  }

  @override
  void dispose() {
    ApiClient.instance.onUnauthorized = null;
    super.dispose();
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
      const NavigationDestination(
        icon: Icon(Icons.notifications_none),
        selectedIcon: Icon(Icons.notifications),
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
      body: IndexedStack(index: tab, children: [for (final t in tabs) t.$1]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [for (final t in tabs) t.$2],
      ),
    );
  }
}
