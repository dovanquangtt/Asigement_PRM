import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../manager/data/attendance_models.dart';
import '../../manager/data/attendance_repository.dart';
import '../../manager/presentation/attendance_dashboard_view.dart';
import '../data/admin_repository.dart';
import 'attendance_report_view.dart';
import 'device_management_view.dart';

/// Admin dashboard: system-wide attendance, device management and reports.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.client});

  /// Defaults to [ApiClient.instance]; tests inject a client with a mock transport.
  final ApiClient? client;
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final ApiClient _api = widget.client ?? ApiClient.instance;
  late final admin = AdminRepository(_api);
  late final attendance = ManagerAttendanceRepository(_api, admin: true);
  List<BranchOption> branches = const [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  /// The branch filter is optional: when the call fails the dashboard still works for all branches.
  Future<void> _loadBranches() async {
    try {
      final list = await admin.branches();
      if (mounted) setState(() => branches = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Quản trị chấm công'),
        bottom: const TabBar(
          tabs: [
            Tab(key: Key('tab-attendance'), text: 'Chấm công'),
            Tab(key: Key('tab-devices'), text: 'Thiết bị'),
            Tab(key: Key('tab-reports'), text: 'Báo cáo'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          AttendanceDashboardView(repository: attendance, branches: branches),
          DeviceManagementView(repository: admin),
          AttendanceReportView(repository: admin, branches: branches),
        ],
      ),
    ),
  );
}
