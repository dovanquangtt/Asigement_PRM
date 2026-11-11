import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../theme/app_colors.dart';
import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';
import '../data/evidence_collector.dart';
import 'attendance_history_screen.dart';
import 'attendance_success_screens.dart';
import 'attendance_ui.dart';

/// Employee attendance home: today's shift, the right action for the current state, and results
/// that come only from the Spring Boot API.
class AttendanceHomeScreen extends StatefulWidget {
  const AttendanceHomeScreen({
    super.key,
    this.client,
    this.collector,
    this.clock,
    this.enableTicker = true,
  });

  /// Defaults to [ApiClient.instance].
  final ApiClient? client;

  /// GPS / device evidence source. Defaults to the real phone sensors.
  final EvidenceCollector? collector;

  /// Current time for the elapsed counter (UI only); defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Disable the 1-second elapsed timer (tests).
  final bool enableTicker;

  @override
  State<AttendanceHomeScreen> createState() => _AttendanceHomeScreenState();
}

class _AttendanceHomeScreenState extends State<AttendanceHomeScreen> {
  late final AttendanceRepository repo = AttendanceRepository(widget.client);
  late final EvidenceCollector collector =
      widget.collector ?? DeviceEvidenceCollector();
  TodayResponse? data;
  String? error;
  bool loading = true;

  /// Synchronous guard so a second tap cannot start a second request.
  bool _busy = false;
  bool busy = false;
  Timer? _ticker;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result = await repo.today();
      if (!mounted) return;
      setState(() {
        data = result;
        error = null;
        loading = false;
      });
      _syncTicker();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        // Keep the last confirmed data on screen when only a refresh failed.
        if (data == null) error = attendanceErrorMessage(e);
      });
      if (data != null) _snack(attendanceErrorMessage(e));
    }
  }

  void _syncTicker() {
    final working = data?.state == AttendanceState.working;
    if (working && widget.enableTicker) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform({required bool checkIn}) async {
    if (_busy) return;
    _busy = true;
    setState(() => busy = true);
    Object? problem;
    try {
      final request = await collector.collect(
        assignmentId: data?.shift?.assignmentId,
      );
      final response = checkIn
          ? await repo.checkIn(request)
          : await repo.checkOut(request);
      if (!mounted) return;
      unawaited(_load(silent: true));
      final next = await Navigator.push<SuccessNext>(
        context,
        MaterialPageRoute<SuccessNext>(
          builder: (_) => checkIn
              ? CheckInSuccessScreen(response: response)
              : CheckOutSuccessScreen(response: response),
        ),
      );
      if (!mounted) return;
      switch (next) {
        case SuccessNext.history:
          await _openHistory();
        case SuccessNext.detail:
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AttendanceDetailScreen(
                attendanceId: response.attendanceId,
                client: widget.client,
              ),
            ),
          );
        case SuccessNext.home || null:
          break;
      }
    } on LocationProblem catch (e) {
      problem = e;
    } on ApiException catch (e) {
      problem = e;
    } finally {
      _busy = false;
      if (mounted) setState(() => busy = false);
    }
    // Dialogs open after the busy state is cleared so the screen is not stuck on a spinner.
    if (problem is LocationProblem) await _locationProblem(problem);
    if (problem is ApiException) await _apiProblem(problem);
  }

  Future<void> _locationProblem(LocationProblem e) async {
    if (!mounted) return;
    if (e.kind == LocationProblemKind.permanentlyDenied) {
      final open = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cần quyền vị trí'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Mở cài đặt'),
            ),
          ],
        ),
      );
      if (open == true) await collector.openAppSettings();
    } else {
      _snack(e.message);
    }
  }

  Future<void> _apiProblem(ApiException e) async {
    if (!mounted) return;
    if (e.code == 'DEVICE_NOT_REGISTERED') {
      final register = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Thiết bị chưa đăng ký'),
          content: Text(attendanceErrorMessage(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Đăng ký thiết bị'),
            ),
          ],
        ),
      );
      if (register == true) await _registerDevice();
      return;
    }
    _snack(attendanceErrorMessage(e));
    // The server state differs from what is on screen: show what is really recorded.
    if (e.code == 'DUPLICATE_ATTENDANCE' || e.code == 'ATTENDANCE_VOIDED') {
      unawaited(_load(silent: true));
    }
  }

  Future<void> _registerDevice() async {
    try {
      final device = await collector.deviceIdentity();
      await repo.registerDevice(
        deviceIdentifier: device.id,
        platform: device.platform,
      );
      _snack(
        'Đã gửi đăng ký thiết bị. Quản lý cần duyệt thiết bị trước khi bạn chấm công.',
      );
    } on ApiException catch (e) {
      _snack(attendanceErrorMessage(e));
    }
  }

  Future<void> _openHistory() => Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AttendanceHistoryScreen(client: widget.client),
    ),
  );

  Widget _employeeCard(EmployeeInfo e) => SectionCard(
    children: [
      Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFE0EBD4),
            child: Text(
              e.initials,
              style: const TextStyle(
                color: green,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Mã NV: ${e.employeeCode}',
                  style: const TextStyle(color: muted),
                ),
                if (e.position != null) Text(e.position!),
                Text(e.branchName ?? '—', style: const TextStyle(color: muted)),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  Widget _actionCard(TodayResponse d) {
    final showIn =
        d.canCheckIn &&
        (d.state == AttendanceState.notCheckedIn ||
            d.state == AttendanceState.exception);
    final showOut =
        d.canCheckOut &&
        (d.state == AttendanceState.working ||
            d.state == AttendanceState.exception);
    final inAt = d.attendance?.checkInAt;
    final elapsed = d.state == AttendanceState.working && inAt != null
        ? _now().difference(inAt)
        : null;
    return SectionCard(
      title: 'Trạng thái',
      children: [
        Row(
          children: [
            Badge2(stateLabel(d.state), stateColor(d.state)),
            const Spacer(),
            if (elapsed != null)
              Text(
                fmtElapsed(elapsed),
                key: const Key('elapsed'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
          ],
        ),
        if (d.state == AttendanceState.noShift)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Bạn chưa được phân ca hôm nay. Hãy liên hệ quản lý nếu có nhầm lẫn.',
            ),
          ),
        if (d.state == AttendanceState.completed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Bạn đã hoàn thành ca. Giờ công: ${fmtMinutes(d.attendance?.workedMinutes ?? 0)}.',
            ),
          ),
        if (d.state == AttendanceState.notCheckedIn && !showIn)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Hiện chưa thể chấm công vào ca này.'),
          ),
        for (final x in d.pendingExceptions)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${eventTypeLabel(x.eventType)}: ${x.message}'),
                ),
              ],
            ),
          ),
        if (showIn || showOut) const SizedBox(height: 14),
        if (showIn)
          _actionButton(
            key: const Key('checkInButton'),
            icon: Icons.login_rounded,
            label: 'Chấm công vào',
            onPressed: () => _perform(checkIn: true),
          ),
        if (showOut)
          Padding(
            padding: EdgeInsets.only(top: showIn ? 10 : 0),
            child: _actionButton(
              key: const Key('checkOutButton'),
              icon: Icons.logout_rounded,
              label: 'Chấm công ra',
              onPressed: () => _perform(checkIn: false),
            ),
          ),
      ],
    );
  }

  Widget _actionButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      key: key,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(busy ? 'Đang xử lý…' : label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chấm công'),
        actions: [
          IconButton(
            tooltip: 'Lịch sử chấm công',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : error != null && d == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: muted),
                    const SizedBox(height: 10),
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _employeeCard(d!.employee),
                  SectionCard(
                    title: 'Ca làm hôm nay',
                    children: [
                      InfoRow(
                        'Ngày',
                        d.date.isEmpty ? fmtDate(d.serverTime) : d.date,
                      ),
                      InfoRow('Ca', fmtShift(d.shift)),
                      if (d.shift?.branchName != null)
                        InfoRow('Chi nhánh', d.shift!.branchName!),
                      if (d.shifts.length > 1)
                        InfoRow(
                          'Các ca khác',
                          d.shifts
                              .where(
                                (s) => s.assignmentId != d.shift?.assignmentId,
                              )
                              .map(fmtShift)
                              .join(', '),
                        ),
                    ],
                  ),
                  _actionCard(d),
                  if (d.attendance != null)
                    SectionCard(
                      title: 'Giờ chấm công',
                      children: [
                        InfoRow(
                          'Giờ vào',
                          fmtDateTime(d.attendance!.checkInAt),
                        ),
                        InfoRow(
                          'Giờ ra',
                          fmtDateTime(d.attendance!.checkOutAt),
                        ),
                        if (d.attendance!.lateMinutes > 0)
                          InfoRow(
                            'Đi muộn',
                            '${d.attendance!.lateMinutes} phút',
                          ),
                      ],
                    ),
                  SectionCard(
                    title: 'Xác minh GPS và thiết bị',
                    children: [VerificationBlock(d.verification)],
                  ),
                  OutlinedButton.icon(
                    onPressed: _openHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('Xem lịch sử chấm công'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
