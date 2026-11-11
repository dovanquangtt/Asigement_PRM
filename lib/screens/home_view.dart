import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/money.dart';

/// Lối tắt ở trang chủ: khóa chức năng, nhãn, biểu tượng.
class HomeFeature {
  const HomeFeature(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const _weekdays = [
  'Thứ hai',
  'Thứ ba',
  'Thứ tư',
  'Thứ năm',
  'Thứ sáu',
  'Thứ bảy',
  'Chủ nhật',
];

String _today() {
  final n = DateTime.now();
  return '${_weekdays[n.weekday - 1]}, ${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final list = parts.toList();
  final last = list.last.characters.first.toUpperCase();
  return list.length == 1
      ? last
      : '${list.first.characters.first.toUpperCase()}$last';
}

/// Trang chủ theo vai trò: thẻ chào, số liệu nổi bật, việc cần xử lý và lưới chức năng.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.session,
    required this.repository,
    required this.overview,
    required this.features,
    required this.onOpen,
    required this.onTab,
  });
  final UserSession session;
  final WorkforceRepository repository;
  final RowData overview;
  final List<HomeFeature> features;
  final void Function(String feature) onOpen;
  final void Function(String tab) onTab;

  bool get isEmployee => session.role == 'Nhân viên';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Hero(session: session),
      const SizedBox(height: 14),
      // Làm mới số liệu mỗi lần tải lại trang chủ (overview là đối tượng mới).
      isEmployee
          ? _EmployeeHighlights(
              key: ValueKey(overview),
              repository: repository,
              onTab: onTab,
              onOpen: onOpen,
            )
          : _ManagerHighlights(
              key: ValueKey(overview),
              repository: repository,
              overview: overview,
              admin: session.role == 'Admin',
              onOpen: onOpen,
              onTab: onTab,
            ),
      const Padding(
        padding: EdgeInsets.only(top: 22, bottom: 12),
        child: Text(
          'Chức năng',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 140,
        ),
        children: [
          for (final f in features)
            _FeatureTile(feature: f, onTap: () => onOpen(f.key)),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 18),
        child: Center(
          child: Text(
            'Kéo xuống để cập nhật dữ liệu.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.session});
  final UserSession session;

  @override
  Widget build(BuildContext context) {
    final name = session.displayName;
    final subtitle = switch (session.role) {
      'Admin' => 'Quản trị tài khoản và nhân sự nhà hàng',
      'Quản lý' => 'Theo dõi đội ngũ, lịch ca và bảng lương',
      _ => 'Lịch làm việc và thu nhập của bạn',
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF14948A)],
        ),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: .25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: .2),
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _today(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Chào $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    session.role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.feature, required this.onTap});
  final HomeFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: borderTint),
    ),
    child: InkWell(
      key: Key('home-${feature.key}'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: softTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(feature.icon, color: green),
            ),
            const SizedBox(height: 8),
            Text(
              feature.label,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ink,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Ô số liệu nhỏ (giá trị lớn + nhãn), có thể chạm.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
    this.alert = false,
    super.key,
  });
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? const Color(0xFFB45309) : green;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: alert ? const Color(0xFFF5D7A8) : borderTint),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _grid(List<Widget> children) => GridView(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    mainAxisExtent: 136,
  ),
  children: children,
);

Future<T> _safe<T>(Future<T> Function() call, T fallback) async {
  try {
    return await call();
  } catch (_) {
    return fallback;
  }
}

class _ManagerHighlights extends StatefulWidget {
  const _ManagerHighlights({
    super.key,
    required this.repository,
    required this.overview,
    required this.admin,
    required this.onOpen,
    required this.onTab,
  });
  final WorkforceRepository repository;
  final RowData overview;
  final bool admin;
  final void Function(String) onOpen;
  final void Function(String) onTab;

  @override
  State<_ManagerHighlights> createState() => _ManagerHighlightsState();
}

class _ManagerHighlightsState extends State<_ManagerHighlights> {
  late final Future<Map<String, int>> loading = _load();

  Future<Map<String, int>> _load() async {
    final r = widget.repository;
    int pending(
      List<RowData> rows, [
      String key = 'status',
      String v = 'pending',
    ]) => rows.where((e) => e[key] == v).length;
    return {
      'leave': await _safe(
        () async => pending(await r.leaveRequestsForReview()),
        0,
      ),
      'attendance': await _safe(
        () async => (await r.attendanceSubmissions()).length,
        0,
      ),
      'closures': await _safe(
        () async => pending(await r.closures(), 'status', 'submitted'),
        0,
      ),
      'disputes': await _safe(
        () async => (await r.payrollDisputes(status: 'pending')).length,
        0,
      ),
      'devices': await _safe(
        () async => pending(await r.devices(), 'status', 'pending'),
        0,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final employees = '${widget.overview['employees'] ?? 0}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grid([
          _Stat(
            key: const Key('stat-employees'),
            icon: Icons.groups_outlined,
            value: employees,
            label: 'Nhân viên đang làm',
            onTap: () => widget.admin
                ? widget.onTab('employees')
                : widget.onOpen('shift_table'),
          ),
          _Stat(
            icon: Icons.calendar_month_outlined,
            value: '${widget.overview['shifts'] ?? 0}',
            label: 'Phân ca đã lưu',
            onTap: () => widget.onOpen('schedule'),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 20, bottom: 12),
          child: Text(
            'Cần xử lý',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ),
        FutureBuilder<Map<String, int>>(
          future: loading,
          builder: (context, snapshot) {
            final d = snapshot.data;
            String v(String k) => d == null ? '…' : '${d[k]}';
            bool alert(String k) => (d?[k] ?? 0) > 0;
            return _grid([
              _Stat(
                key: const Key('todo-leave'),
                icon: Icons.beach_access_outlined,
                value: v('leave'),
                label: 'Nghỉ phép chờ duyệt',
                alert: alert('leave'),
                onTap: () => widget.onOpen('leave_review'),
              ),
              _Stat(
                key: const Key('todo-attendance'),
                icon: Icons.fingerprint,
                value: v('attendance'),
                label: 'Điểm danh cần duyệt',
                alert: alert('attendance'),
                onTap: () => widget.onOpen('attendance_review'),
              ),
              _Stat(
                key: const Key('todo-closures'),
                icon: Icons.photo_camera_outlined,
                value: v('closures'),
                label: 'Báo cáo đóng ca',
                alert: alert('closures'),
                onTap: () => widget.onOpen('closures'),
              ),
              _Stat(
                key: const Key('todo-disputes'),
                icon: Icons.flag_outlined,
                value: v('disputes'),
                label: 'Báo sai lương',
                alert: alert('disputes'),
                onTap: () => widget.onOpen('payroll'),
              ),
            ]);
          },
        ),
      ],
    );
  }
}

class _EmployeeHighlights extends StatefulWidget {
  const _EmployeeHighlights({
    super.key,
    required this.repository,
    required this.onTab,
    required this.onOpen,
  });
  final WorkforceRepository repository;
  final void Function(String) onTab;
  final void Function(String) onOpen;

  @override
  State<_EmployeeHighlights> createState() => _EmployeeHighlightsState();
}

class _EmployeeHighlightsState extends State<_EmployeeHighlights> {
  late final Future<RowData> loading = _load();

  Future<RowData> _load() async {
    final r = widget.repository;
    final schedule = await _safe(() => r.employeeSchedule(), <RowData>[]);
    final now = DateTime.now().toUtc();
    final upcoming =
        schedule
            .where(
              (s) =>
                  s['assignment_status'] == 'assigned' &&
                  s['shift_status'] != 'cancelled' &&
                  utcTime(s['ends_at']).isAfter(now),
            )
            .toList()
          ..sort(
            (a, b) =>
                utcTime(a['starts_at']).compareTo(utcTime(b['starts_at'])),
          );
    final balances = await _safe(() => r.leaveBalances(), <RowData>[]);
    final annual = balances.where((b) => b['code'] == 'ANNUAL').firstOrNull;
    final pay = await _safe(() => r.myPayrolls(), <RowData>[]);
    return {
      'next': upcoming.firstOrNull,
      'pending': upcoming
          .where((s) => s['response_status'] == 'pending')
          .length,
      'leave': annual == null
          ? null
          : (annual['remaining_minutes'] as num) / 480,
      'pay': pay.firstOrNull,
    };
  }

  static String _hm(Object? v) {
    final t = utcTime(v).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  static String _day(Object? v) {
    final t = utcTime(v).toLocal();
    final now = DateTime.now();
    final same = t.year == now.year && t.month == now.month && t.day == now.day;
    return same
        ? 'Hôm nay'
        : '${_weekdays[t.weekday - 1]}, ${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RowData>(
    future: loading,
    builder: (context, snapshot) {
      final d = snapshot.data;
      final next = d?['next'] as RowData?;
      final pending = (d?['pending'] as int?) ?? 0;
      final leave = d?['leave'] as num?;
      final pay = d?['pay'] as RowData?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: const Color(0xFFFFF4E0),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: const Key('home-pending-shifts'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onTab('shifts'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          color: Color(0xFFB45309),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Có $pending ca chờ bạn xác nhận',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A4B08),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFFB45309),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: borderTint),
            ),
            child: InkWell(
              key: const Key('home-next-shift'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => widget.onTab('shifts'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: softTint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.schedule, color: green),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CA LÀM SẮP TỚI',
                            style: TextStyle(
                              color: muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            snapshot.connectionState != ConnectionState.done
                                ? 'Đang tải…'
                                : next == null
                                ? 'Chưa có ca nào sắp tới'
                                : '${_day(next['starts_at'])} • ${_hm(next['starts_at'])}–${_hm(next['ends_at'])}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          if (next != null)
                            Text(
                              '${next['branch_name'] ?? ''}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _grid([
            _Stat(
              key: const Key('home-leave'),
              icon: Icons.beach_access_outlined,
              value: leave == null
                  ? '—'
                  : '${leave.toStringAsFixed(leave % 1 == 0 ? 0 : 1)} ngày',
              label: 'Phép năm còn lại',
              onTap: () => widget.onTab('shifts'),
            ),
            _Stat(
              key: const Key('home-pay'),
              icon: Icons.account_balance_wallet_outlined,
              value: pay == null ? '—' : formatVnd(pay['net_pay_vnd'] as num),
              label: pay == null
                  ? 'Chưa có phiếu lương'
                  : 'Thực lĩnh kỳ ${pay['period_code']}',
              onTap: () => widget.onTab('payroll'),
            ),
          ]),
        ],
      );
    },
  );
}
