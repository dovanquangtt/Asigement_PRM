import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../data/attendance_repository.dart';
import 'attendance_dashboard_view.dart';

/// Manager dashboard: branch-scoped summary, attendance list, exceptions and detail screens.
class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key, this.client});

  /// Defaults to [ApiClient.instance]; tests inject a client with a mock transport.
  final ApiClient? client;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chấm công chi nhánh')),
    body: AttendanceDashboardView(
      repository: ManagerAttendanceRepository(client ?? ApiClient.instance),
    ),
  );
}
