import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../state/workspace_controller.dart';
import '../services/workspace_actions.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'payroll_screen.dart';
import 'profile_screen.dart';

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.role});
  final String role;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late final WorkspaceController controller;
  @override
  void initState() {
    super.initState();
    controller = WorkspaceController(role: widget.role);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final actions = WorkspaceActions(context, controller);
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: IndexedStack(
                index: controller.tab,
                children: [
                  HomeScreen(controller: controller, actions: actions),
                  ScheduleScreen(controller: controller, actions: actions),
                  PayrollScreen(controller: controller, actions: actions),
                  ProfileScreen(controller: controller, actions: actions),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: ink.withValues(alpha: .06),
                blurRadius: 24,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: NavigationBar(
            height: 72,
            selectedIndex: controller.tab,
            onDestinationSelected: (i) =>
                controller.update(() => controller.tab = i),
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFDCEFE4),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Trang chủ',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                label: 'Lịch ca',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: 'Thu nhập',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Cá nhân',
              ),
            ],
          ),
        ),
      );
    },
  );
}
