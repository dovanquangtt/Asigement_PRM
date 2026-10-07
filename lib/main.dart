import 'package:flutter/material.dart';

void main() => runApp(const PrmApp());
const green = Color(0xFF216653);
const ink = Color(0xFF183B32);
const muted = Color(0xFF7B8C84);
const lime = Color(0xFFDCEFAD);

class PrmApp extends StatelessWidget {
  const PrmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Mộc • Nhân sự',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFEBF0E9)),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? green : muted,
          ),
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F6F2),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F6F2),
        foregroundColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
    home: const LoginPage(),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  bool hidden = true;
  String role = 'Nhân viên';
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  void enter() {
    if (form.currentState!.validate()) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => Workspace(role: role)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      BrandMark(),
                      SizedBox(width: 10),
                      Text(
                        'mộc',
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      Spacer(),
                      Text(
                        'TEAM SPACE',
                        style: TextStyle(
                          fontSize: 10,
                          color: muted,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Container(
                    height: 225,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -45,
                          top: -50,
                          child: Container(
                            width: 230,
                            height: 230,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: .06),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: -80,
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .12),
                                width: 28,
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          right: 14,
                          top: 38,
                          child: Icon(
                            Icons.spa_rounded,
                            size: 90,
                            color: Color(0xFFB7DCA5),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'CÙNG MỘC',
                                style: TextStyle(
                                  color: lime,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Mỗi ngày,\ncùng tốt hơn.',
                                style: TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  color: Colors.white,
                                  letterSpacing: -.8,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Một đội ngũ. Một hành trình.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Chào mừng trở lại',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Đăng nhập để bắt đầu ngày làm việc của bạn.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: username,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Nhập tên đăng nhập'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: hidden,
                    onFieldSubmitted: (_) => enter(),
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Nhập mật khẩu' : null,
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(
                      labelText: 'Vai trò trải nghiệm',
                    ),
                    items: ['Nhân viên', 'Quản lý', 'Admin']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => role = v!),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: enter,
                      child: const Text('Vào không gian làm việc →'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Bản trải nghiệm • nhập tài khoản bất kỳ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.role});
  final String role;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int tab = 0;
  int selectedDay = 2;
  int month = 10;
  int stars = 12;
  bool entered = false;
  bool exited = false;
  bool closed = false;
  bool notificationsRead = false;
  DateTime? enteredAt;
  final List<String> requests = [];
  bool get manager => widget.role != 'Nhân viên';
  void toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
  String clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<bool> request(String title) async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Nội dung / lý do',
            hintText: 'Nhập ngày, ca và lý do yêu cầu',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (note.text.trim().isNotEmpty)
                Navigator.pop(ctx, note.text.trim());
            },
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    // The controller is released after the dialog transition finishes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    note.dispose();
    if (!mounted || result == null) return false;
    setState(() => requests.add('$title: $result'));
    toast('Đã lưu yêu cầu trong phiên trải nghiệm');
    return true;
  }

  Future<void> attendance() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entered ? 'Xác nhận ra ca?' : 'Xác nhận vào ca?'),
        content: const Text(
          'Điểm danh mô phỏng. Thiết bị, GPS và Wi-Fi chưa được xác thực thực tế.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      if (!entered) {
        entered = true;
        enteredAt = DateTime.now();
      } else {
        exited = true;
      }
    });
    toast(exited ? 'Đã ghi nhận ra ca mẫu' : 'Đã ghi nhận vào ca mẫu');
  }

  void detail(String title, List<(String, String)> rows) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            panel(
              child: Column(
                children: rows
                    .map(
                      (r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          r.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        subtitle: Text(
                          r.$2,
                          style: const TextStyle(fontSize: 16, color: ink),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void roster() => detail('Nhân viên trong ca', [
    ('Nguyễn Linh', 'NV001 • Phục vụ'),
    ('Trần Minh', 'NV002 • Phục vụ'),
    ('Lê An', 'NV003 • Thu ngân'),
    ('Phạm Huy', 'NV004 • Bếp'),
  ]);
  void requestList() => detail(
    'Yêu cầu đã gửi',
    requests.isEmpty
        ? [('Chưa có yêu cầu', 'Tạo yêu cầu từ trang chủ hoặc lịch ca.')]
        : requests.map((r) => (r, 'Chờ duyệt • dữ liệu mẫu')).toList(),
  );
  void notifications() {
    setState(() => notificationsRead = true);
    detail('Thông báo', [
      (
        'Lịch làm tuần này đã sẵn sàng',
        'Kiểm tra lịch ca để chuẩn bị cho tuần mới.',
      ),
      ('Phiếu lương tháng 9', 'Xem chi tiết trong mục Thu nhập.'),
      ('Dữ liệu trải nghiệm', 'Các thông báo trên là dữ liệu mẫu.'),
    ]);
  }

  Future<void> closeShift() async {
    if (!exited) {
      toast('Hãy điểm danh ra ca trước khi đóng ca');
      return;
    }
    if (closed) {
      toast('Bạn đã gửi báo cáo đóng ca');
      return;
    }
    if (await request('Báo cáo đóng ca') && mounted) {
      setState(() => closed = true);
      toast('Đã lưu ghi chú mẫu. Chụp ảnh sẽ được tích hợp sau.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: IndexedStack(
            index: tab,
            children: [home(), schedule(), payroll(), profile()],
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
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
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
  Widget page(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
    children: children,
  );
  Widget heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        subtitle,
        style: const TextStyle(
          color: green,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
      const SizedBox(height: 22),
    ],
  );
  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        letterSpacing: -.3,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
  );
  Widget metric(String title, String value, String unit, IconData icon) =>
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: icon == Icons.star_outline_rounded
                        ? const Color(0xFFFFF3D8)
                        : const Color(0xFFEAF2E4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: icon == Icons.star_outline_rounded
                        ? const Color(0xFFB58A34)
                        : green,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.north_east, color: muted, size: 14),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 32,
                    letterSpacing: -1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    unit,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      );
  Widget quick(IconData icon, String text, VoidCallback action) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5EA),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: green, size: 20),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget home() => page([
    Row(
      children: [
        const BrandMark(),
        const SizedBox(width: 10),
        const Text(
          'mộc',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: notifications,
          tooltip: 'Thông báo',
          icon: Badge(
            isLabelVisible: !notificationsRead,
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => tab = 3),
          child: const CircleAvatar(
            backgroundColor: Color(0xFFE0EBD4),
            child: Text(
              'LH',
              style: TextStyle(
                color: green,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 28),
    const Text(
      'Chào Linh',
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
    ),
    const SizedBox(height: 5),
    const Text(
      'Sẵn sàng cho một ngày thật tốt?',
      style: TextStyle(color: muted, fontSize: 13),
    ),
    const SizedBox(height: 22),
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF245B49), Color(0xFF153D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: green.withValues(alpha: .16),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -65,
            top: -70,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .04),
                  width: 35,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CA LÀM HÔM NAY',
                        style: TextStyle(
                          color: Color(0xFFC1D7C7),
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    pill(
                      exited
                          ? 'Hoàn thành'
                          : entered
                          ? 'Trong ca'
                          : 'Sắp bắt đầu',
                      dark: true,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '08:00',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              letterSpacing: -1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'BẮT ĐẦU',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF9ABAA9),
                        size: 23,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '16:00',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              letterSpacing: -1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'KẾT THÚC',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFF496D5E), height: 1),
                const SizedBox(height: 15),
                const Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: Color(0xFFC1D7C7),
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Trung tâm • Phục vụ • Ca sáng',
                        style: TextStyle(
                          color: Color(0xFFC1D7C7),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Icon(Icons.wb_sunny_outlined, color: lime, size: 18),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: lime,
                      foregroundColor: ink,
                      disabledBackgroundColor: const Color(0xFF4B6D59),
                      disabledForegroundColor: Colors.white70,
                    ),
                    onPressed: exited ? null : attendance,
                    icon: Icon(
                      entered ? Icons.logout_rounded : Icons.fingerprint,
                      size: 22,
                    ),
                    label: Text(
                      exited
                          ? 'Đã kết thúc ca'
                          : entered
                          ? 'Điểm danh ra ca'
                          : 'Điểm danh vào ca',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (enteredAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Vào ca lúc ' + clock(enteredAt!) + ' • dữ liệu mẫu',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(child: metric('Công tháng này', '18', 'ngày', Icons.schedule)),
        const SizedBox(width: 12),
        Expanded(
          child: metric(
            'Sao tích lũy',
            '$stars',
            'ngôi sao',
            Icons.star_outline_rounded,
          ),
        ),
      ],
    ),
    section('Thao tác nhanh'),
    Row(
      children: [
        Expanded(
          child: quick(
            Icons.event_available_outlined,
            'Xin nghỉ phép',
            () => request('Xin nghỉ phép'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: quick(Icons.swap_horiz, 'Đổi ca', () => request('Đổi ca')),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: quick(
            Icons.edit_calendar_outlined,
            'Điều chỉnh công',
            () => request('Điều chỉnh công'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: quick(Icons.task_alt, 'Đóng ca', closeShift)),
      ],
    ),
    section('Kiểm tra điểm danh'),
    panel(
      child: const Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_android, color: green),
            title: Text('Thiết bị Pixel'),
            subtitle: Text('Mô phỏng thiết bị'),
          ),
          Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.my_location, color: green),
            title: Text('Vị trí nhà hàng'),
            subtitle: Text('Chưa xác thực GPS thực tế'),
          ),
          Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.wifi, color: green),
            title: Text('Wi-Fi nhà hàng'),
            subtitle: Text('Chưa xác thực mạng thực tế'),
          ),
        ],
      ),
    ),
    if (manager) ...[
      section(
        widget.role == 'Admin' ? 'Quản trị hệ thống' : 'Không gian quản lý',
      ),
      panel(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: green),
              title: const Text('Nhân viên trong ca'),
              subtitle: const Text('4 nhân viên • ca sáng'),
              trailing: const Icon(Icons.chevron_right),
              onTap: roster,
            ),
            ListTile(
              leading: const Icon(Icons.approval_outlined, color: green),
              title: const Text('Yêu cầu đã gửi'),
              subtitle: Text('${requests.length} yêu cầu mẫu'),
              trailing: const Icon(Icons.chevron_right),
              onTap: requestList,
            ),
            ListTile(
              leading: const Icon(Icons.star_outline, color: green),
              title: const Text('Tặng sao cho Linh'),
              onTap: () {
                setState(() => stars++);
                toast('Đã tặng 1 sao mẫu');
              },
            ),
            if (widget.role == 'Admin')
              ListTile(
                leading: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: green,
                ),
                title: const Text('Tài khoản và phân quyền'),
                onTap: () => detail('Phân quyền', [
                  ('Admin', 'Quản trị hệ thống'),
                  ('Manager', 'Quản lý nghiệp vụ'),
                  ('Employee', 'Dữ liệu cá nhân'),
                ]),
              ),
          ],
        ),
      ),
    ],
    const SizedBox(height: 24),
    const Text(
      'DỮ LIỆU TRẢI NGHIỆM • CHƯA ĐỒNG BỘ',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.black45),
    ),
  ]);

  Widget schedule() => page([
    heading('Lịch làm của bạn', 'SẮP XẾP MỘT TUẦN THẬT TỐT'),
    const Text(
      '05 — 11 tháng 10, 2026 • tuần mẫu',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: 20),
    Row(
      children: List.generate(
        7,
        (i) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: selectedDay == i ? green : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => setState(() => selectedDay = i),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i],
                        style: TextStyle(
                          fontSize: 11,
                          color: selectedDay == i
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${5 + i}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selectedDay == i ? Colors.white : ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    section('Ca ngày ${5 + selectedDay}/10'),
    if (selectedDay == 6)
      panel(
        child: const Column(
          children: [
            Icon(Icons.weekend_outlined, size: 48, color: green),
            SizedBox(height: 12),
            Text('Hôm nay bạn được nghỉ'),
            SizedBox(height: 6),
            Text(
              'Dành một chút thời gian cho bản thân.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      )
    else
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny_outlined, color: Color(0xFFB48031)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ca sáng',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                pill('Đã phân ca'),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              '08:00 — 16:00',
              style: TextStyle(
                fontSize: 26,
                color: ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Phục vụ • Khu vực tầng 1\nNghỉ giữa ca: 30 phút',
              style: TextStyle(color: Colors.black54, height: 1.7),
            ),
            const Divider(height: 30),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cùng ca với 3 đồng nghiệp',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(onPressed: roster, child: const Text('Xem')),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => request('Đổi ca ngày ${5 + selectedDay}/10'),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Yêu cầu đổi ca'),
              ),
            ),
          ],
        ),
      ),
    section('Yêu cầu của bạn'),
    if (requests.isEmpty)
      panel(
        child: const Text(
          'Chưa có yêu cầu trong phiên này.',
          style: TextStyle(color: Colors.black54),
        ),
      )
    else
      ...requests.map(
        (r) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r),
                const SizedBox(height: 10),
                pill('Chờ duyệt'),
              ],
            ),
          ),
        ),
      ),
    const SizedBox(height: 20),
    OutlinedButton.icon(
      onPressed: () => request('Xin nghỉ phép'),
      icon: const Icon(Icons.add),
      label: const Text('Tạo yêu cầu nghỉ phép'),
    ),
    if (manager)
      FilledButton.icon(
        onPressed: () => request('Phân ca mới'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Tạo phân ca mẫu'),
      ),
  ]);

  Widget money(String name, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: bold ? ink : Colors.black54,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: bold ? green : ink,
          ),
        ),
      ],
    ),
  );
  Widget payroll() => page([
    heading('Thu nhập', 'MỖI ĐÓNG GÓP ĐỀU ĐƯỢC GHI NHẬN'),
    Row(
      children: [
        const Text('Kỳ lương', style: TextStyle(color: Colors.black54)),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButton<int>(
            isExpanded: true,
            style: const TextStyle(fontSize: 15, color: ink),
            value: month,
            underline: const SizedBox(),
            items: [9, 10]
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text('Tháng $m / 2026'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => month = v!),
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: green,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            month == 10 ? 'THU NHẬP DỰ KIẾN' : 'THU NHẬP THỰC NHẬN',
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            child: Text(
              month == 10 ? '10.600.000 ₫' : '10.200.000 ₫',
              style: const TextStyle(
                fontSize: 31,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          pill(
            month == 10 ? 'Tạm tính • dữ liệu mẫu' : 'Đã trả • dữ liệu mẫu',
            dark: true,
          ),
        ],
      ),
    ),
    section('Chi tiết bảng lương'),
    panel(
      child: Column(
        children: [
          money('Lương cơ bản', '10.000.000 ₫'),
          money('Lương tăng ca', month == 10 ? '+500.000 ₫' : '+100.000 ₫'),
          money('Phụ cấp', '+200.000 ₫'),
          money('Khấu trừ', '−100.000 ₫'),
          const Divider(height: 28),
          money(
            'Thực nhận',
            month == 10 ? '10.600.000 ₫' : '10.200.000 ₫',
            bold: true,
          ),
        ],
      ),
    ),
    section('Tổng hợp công'),
    Row(
      children: [
        Expanded(
          child: metric('Công được tính', '18', 'ngày', Icons.event_available),
        ),
        const SizedBox(width: 12),
        Expanded(child: metric('Tăng ca', '5', 'giờ', Icons.more_time)),
      ],
    ),
    const SizedBox(height: 20),
    OutlinedButton.icon(
      onPressed: () => detail('Phiếu lương tháng $month', [
        ('Nhân viên', 'Nguyễn Linh • NV001'),
        ('Hợp đồng', 'HĐ001 • Toàn thời gian'),
        ('Kỳ lương', 'Tháng $month/2026'),
        ('Trạng thái', month == 10 ? 'Tạm tính' : 'Đã thanh toán'),
        ('Dữ liệu', 'Phiếu mẫu, chưa lấy từ MySQL'),
      ]),
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Mở phiếu lương'),
    ),
    if (manager) ...[
      section('Thao tác quản lý lương'),
      FilledButton.icon(
        onPressed: () => request('Yêu cầu tính lương'),
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Tạo yêu cầu tính lương mẫu'),
      ),
    ],
  ]);

  Widget profile() => page([
    heading('Không gian cá nhân', 'HỒ SƠ CỦA BẠN'),
    panel(
      child: Column(
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: Color(0xFFDCEFE4),
            child: Text(
              'LH',
              style: TextStyle(
                fontSize: 24,
                color: green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Nguyễn Linh',
            style: TextStyle(
              fontSize: 23,
              color: ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'NV001 • ${widget.role}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          pill('Đang làm việc'),
        ],
      ),
    ),
    section('Thông tin & tiện ích'),
    panel(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined, color: green),
            title: const Text('Hồ sơ nhân viên'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => detail('Hồ sơ nhân viên', [
              ('Họ tên', 'Nguyễn Linh'),
              ('Mã nhân viên', 'NV001'),
              ('Bộ phận', 'Phục vụ'),
              ('Chi nhánh', 'Trung tâm'),
              ('Ngày vào làm', '01/06/2026'),
              ('Email', 'linh@example.com'),
            ]),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: green),
            title: const Text('Hợp đồng lao động'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => detail('Hợp đồng lao động', [
              ('Mã hợp đồng', 'HĐ001'),
              ('Loại', 'Có thời hạn'),
              ('Hiệu lực', '01/06/2026 — 31/05/2027'),
              ('Lương cơ bản', '10.000.000 ₫'),
            ]),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.beach_access_outlined, color: green),
            title: const Text('Nghỉ phép'),
            subtitle: const Text('Còn 8 ngày • dữ liệu mẫu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => request('Xin nghỉ phép'),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inbox_outlined, color: green),
            title: const Text('Yêu cầu đã gửi'),
            subtitle: Text('${requests.length} yêu cầu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: requestList,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined, color: green),
            title: const Text('Thông báo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: notifications,
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    OutlinedButton.icon(
      onPressed: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      ),
      icon: const Icon(Icons.logout),
      label: const Text('Đăng xuất'),
    ),
    const SizedBox(height: 20),
    const Text(
      'Mộc • Phiên bản trải nghiệm 1.0\nDữ liệu chỉ lưu trong phiên sử dụng.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.7),
    ),
  ]);
}

Widget panel({required Widget child}) => Material(
  color: Colors.white,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
    side: const BorderSide(color: Color(0xFFE8EDE7)),
  ),
  child: Padding(padding: const EdgeInsets.all(18), child: child),
);
Widget pill(String text, {bool dark = false}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: dark ? Colors.white.withValues(alpha: .12) : const Color(0xFFE8F2E9),
    borderRadius: BorderRadius.circular(30),
  ),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 10,
      color: dark ? Colors.white : green,
      fontWeight: FontWeight.w600,
    ),
  ),
);

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 39,
    height: 39,
    decoration: BoxDecoration(
      color: green,
      borderRadius: BorderRadius.circular(13),
    ),
    child: const Icon(Icons.spa_rounded, color: lime, size: 23),
  );
}
