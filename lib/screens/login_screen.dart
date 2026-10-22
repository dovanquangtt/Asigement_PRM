import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import 'workspace_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.auth});
  final AuthService? auth;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  bool hidden = true;
  late final AuthService auth = widget.auth ?? AuthService();
  bool busy = false;
  bool canSetup = false;
  bool setup = false;
  String? error;
  static const _teamQuotes = [
    'Một người tận tâm, cả đội vững vàng.',
    'Món ngon giữ vị, sự tử tế giữ lòng.',
    'Cùng nhau làm tốt những điều nhỏ mỗi ngày.',
    'Một ca làm trọn vẹn bắt đầu từ một nụ cười.',
    'Bếp có lửa, đội có tâm, quán có tình.',
    'Mỗi người một việc, chung một niềm tự hào.',
    'Khách nhớ món ngon, thương người phục vụ.',
  ];

  String get teamQuote {
    final now = DateTime.now();
    return _teamQuotes[DateTime.utc(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime.utc(2026)).inDays %
        _teamQuotes.length];
  }

  @override
  void initState() {
    super.initState();
    checkSetup();
  }

  Future<void> checkSetup() async {
    try {
      final exists = await auth.hasUsers();
      if (mounted) setState(() => canSetup = !exists);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không đọc được database. Hãy thử lại.');
      }
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> enter() async {
    if (busy || !form.currentState!.validate()) return;
    final name = username.text.trim();
    final secret = password.text;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (setup) await auth.createFirstAdmin(name, secret);
      final session = await auth.signIn(name, secret);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Workspace(
            session: session,
            auth: auth,
            repository: WorkforceRepository(
              session,
              openDatabase: () => auth.database,
            ),
          ),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không thể kết nối database. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enterGoogle() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = await auth.signInGoogle();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Workspace(
            session: session,
            auth: auth,
            repository: WorkforceRepository(
              session,
              openDatabase: () => auth.database,
            ),
          ),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không hoàn tất đăng nhập Gmail. Kiểm tra Internet hoặc thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF243E36);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: dark),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F3EE),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          labelStyle: const TextStyle(color: Color(0xFF74726D), fontSize: 14),
          prefixIconColor: const Color(0xFF777368),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFB5883A), width: 1.5),
          ),
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: dark,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF3F0E8),
                  Color(0xFFF8FAF7),
                  Color(0xFFE9F0EA),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/branding/anh_em_quan.jpg',
                                width: 84,
                                height: 84,
                                fit: BoxFit.cover,
                                semanticLabel: 'Logo ANH EM QUÁN',
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ANH EM QUÁN',
                                    style: TextStyle(
                                      color: dark,
                                      fontSize: 20,
                                      letterSpacing: .6,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'ẨM THỰC VIỆT · THÁI',
                                    style: TextStyle(
                                      color: Color(0xFF947348),
                                      fontSize: 10,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Một đội ngũ. Một tấm lòng.',
                                    style: TextStyle(
                                      color: Color(0xFF7C827B),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE4E9E1)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0D243E36),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: AutofillGroup(
                            child: Form(
                              key: form,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'KHÔNG GIAN NHÂN SỰ',
                                    style: TextStyle(
                                      color: Color(0xFF9B742F),
                                      fontSize: 10,
                                      letterSpacing: 1.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Chào mừng trở lại',
                                    style: TextStyle(
                                      color: dark,
                                      fontSize: 23,
                                      letterSpacing: -.8,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  const Text(
                                    'Mỗi ngày cùng nhau, mỗi ca thêm gắn kết.',
                                    style: TextStyle(
                                      color: Color(0xFF77736C),
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    enabled: !busy,
                                    controller: username,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Tên đăng nhập',
                                      prefixIcon: Icon(
                                        Icons.person_outline_rounded,
                                        size: 21,
                                      ),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'Nhập tên đăng nhập'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    enabled: !busy,
                                    controller: password,
                                    obscureText: hidden,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => enter(),
                                    decoration: InputDecoration(
                                      labelText: 'Mật khẩu',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 21,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: hidden
                                            ? 'Hiện mật khẩu'
                                            : 'Ẩn mật khẩu',
                                        onPressed: busy
                                            ? null
                                            : () => setState(
                                                () => hidden = !hidden,
                                              ),
                                        icon: Icon(
                                          hidden
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Nhập mật khẩu'
                                        : null,
                                  ),
                                  if (canSetup) ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Tạo quản trị viên đầu tiên với mật khẩu ít nhất 8 ký tự.',
                                    ),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => setState(() {
                                              setup = !setup;
                                              error = null;
                                            }),
                                      child: Text(
                                        setup ? 'Quay lại đăng nhập' : 'Thiết lập quản trị viên đầu tiên',
                                      ),
                                    ),
                                  ],
                                  if (error != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFEDE9),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        error!,
                                        style: const TextStyle(
                                          color: Color(0xFFA73125),
                                          fontSize: 12,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: dark,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 50),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      onPressed: busy ? null : enter,
                                      child: Text(
                                        busy
                                            ? 'Đang kiểm tra…'
                                            : setup
                                            ? 'Tạo quản trị viên và đăng nhập'
                                            : 'Vào không gian làm việc →',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: Color(0xFFE7E1D7),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            'hoặc tiếp tục với',
                                            style: TextStyle(
                                              color: Color(0xFF938D83),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: Color(0xFFE7E1D7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: dark,
                                        minimumSize: const Size(0, 52),
                                        side: const BorderSide(
                                          color: Color(0xFFDDD5C8),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      onPressed: busy ? null : enterGoogle,
                                      icon: const Icon(
                                        Icons.account_circle_outlined,
                                        size: 22,
                                      ),
                                      label: const Text(
                                        'Đăng nhập bằng Gmail',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.format_quote_rounded,
                              color: Color(0xFFAD8545),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'MỘT CHÚT CẢM HỨNG MỖI NGÀY',
                                    style: TextStyle(
                                      color: Color(0xFF947348),
                                      fontSize: 9,
                                      letterSpacing: 1.3,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    teamQuote,
                                    style: const TextStyle(
                                      color: Color(0xFF52665B),
                                      fontSize: 12,
                                      height: 1.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: Color(0xFF727D73),
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Đăng nhập bằng tài khoản đã được cấp.',
                                style: TextStyle(
                                  color: Color(0xFF727D73),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}
