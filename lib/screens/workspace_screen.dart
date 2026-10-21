import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';
import 'operations_screen.dart';
import 'schedule_screen.dart';

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
        title: const Text('Nạp dữ liệu mẫu M01–M07?'),
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
        builder: (_) => OperationsPage(repository: repository, kind: kind),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> logout() async {
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
    if (saved == true && mounted) await refresh();
  }

  String value(RowData row, String key) => row[key]?.toString() ?? 'Chưa có';
  String currency(Object? amount) =>
      '${(amount ?? 0).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫';

  List<Widget> content(Object data) {
    if (current == 'home') {
      final row = data as RowData;
      return [
        heading(
          'Chào ${widget.session.displayName}',
          widget.session.role.toUpperCase(),
        ),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (widget.session.role) {
                  'Admin' => 'Quản trị tài khoản và nhân sự nhà hàng',
                  'Quản lý' => 'Theo dõi đội ngũ, lịch ca và bảng lương',
                  _ => 'Lịch làm việc và thu nhập của bạn',
                },
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              if (row['employees'] != null)
                money('Nhân viên đang làm', value(row, 'employees')),
              money(
                widget.session.role == 'Nhân viên'
                    ? 'Phân ca của bạn'
                    : 'Phân ca đã lưu',
                value(row, 'shifts'),
              ),
              money(
                widget.session.role == 'Nhân viên'
                    ? 'Phiếu lương của bạn'
                    : 'Phiếu lương đã lưu',
                value(row, 'payslips'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        section('Chức năng'),
        if (widget.session.role == 'Admin')
          OutlinedButton.icon(
            onPressed: installDemoData,
            icon: const Icon(Icons.dataset_outlined),
            label: const Text('Nạp dữ liệu mẫu M01–M07'),
          ),
        for (final feature in [
          ('schedule', 'M01 / M03 / M04 • Lịch ca, phân ca & điểm danh'),
          ('payroll', 'M02 • Tính lương & kiểm tra 6 bước'),
          ('swaps', 'M05 • Đổi ca'),
          ('stars', 'M06 • Sao nhân viên'),
          ('closures', 'M07 • Ảnh & báo cáo đóng ca'),
          ('attendance', 'Lịch sử điểm danh'),
          if (widget.session.role != 'Nhân viên') ...[
            ('devices', 'Duyệt thiết bị nhân viên'),
            ('branches', 'Cấu hình GPS & Wi-Fi chi nhánh'),
          ],
        ])
          ListTile(
            title: Text(feature.$2),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openFeature(feature.$1),
          ),
        const Text(
          'Kéo xuống để cập nhật dữ liệu.',
          style: TextStyle(color: muted),
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
          onPressed: logout,
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
                '${value(row, 'roles')} • ${row['is_active'] == 1 ? 'Hoạt động' : 'Đã khóa'}',
              ),
            ),
            'employees' => ListTile(
              onTap: () => employeeContract(row),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined, color: green),
              title: Text(value(row, 'full_name')),
              subtitle: Text(
                '${value(row, 'employee_code')} • ${value(row, 'branch_name')}\n${value(row, 'phone')}',
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
      title: Text('Mộc • ${widget.session.role}'),
      actions: [
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
              ? ScheduleScreen(repository: repository)
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
                                onPressed: () =>
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            LoginPage(auth: widget.auth),
                                      ),
                                      (_) => false,
                                    ),
                                child: const Text('Về đăng nhập'),
                              ),
                            ],
                          ),
                        ),
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

class _CreateDialogState extends State<_CreateDialog> {
  final form = GlobalKey<FormState>();
  final first = TextEditingController();
  final second = TextEditingController();
  final phone = TextEditingController();
  String role = 'employee';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    phone.dispose();
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
        await widget.repository.createUser(
          username: first.text,
          password: second.text,
          role: role,
        );
      } else {
        await widget.repository.createEmployee(
          code: first.text,
          name: second.text,
          phone: phone.text,
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.account ? 'Tạo tài khoản' : 'Thêm nhân viên'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: first,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: widget.account ? 'Tên đăng nhập' : 'Mã nhân viên',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Không được để trống'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: second,
                enabled: !busy,
                obscureText: widget.account,
                decoration: InputDecoration(
                  labelText: widget.account
                      ? 'Mật khẩu (ít nhất 8 ký tự)'
                      : 'Họ tên',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Không được để trống'
                    : null,
              ),
              const SizedBox(height: 12),
              if (widget.account)
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Vai trò tài khoản mới',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Quản lý')),
                    DropdownMenuItem(
                      value: 'employee',
                      child: Text('Nhân viên'),
                    ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => role = v!),
                )
              else
                TextFormField(
                  controller: phone,
                  enabled: !busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Điện thoại'),
                ),
              if (!widget.account)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Hồ sơ mới được tạo tại chi nhánh đầu tiên. Hồ sơ chưa liên kết tài khoản đăng nhập.',
                  ),
                ),
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
          onPressed: busy ? null : save,
          child: Text(busy ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    ),
  );
}
