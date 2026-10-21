import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
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
              'Đăng nhập Google bị hủy hoặc chưa cấu hình đúng OAuth/SHA-1.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
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
                    enabled: !busy,
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
                    enabled: !busy,
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
                  if (canSetup) ...[
                    const Text(
                      'Database chưa có tài khoản. Hãy tạo quản trị viên đầu tiên với mật khẩu ít nhất 8 ký tự.',
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              setup = !setup;
                              error = null;
                            }),
                      child: Text(
                        setup
                            ? 'Quay lại đăng nhập'
                            : 'Thiết lập quản trị viên đầu tiên',
                      ),
                    ),
                  ],
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : enter,
                      child: Text(
                        busy
                            ? 'Đang kiểm tra…'
                            : setup
                            ? 'Tạo quản trị viên và đăng nhập'
                            : 'Vào không gian làm việc →',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : enterGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Đăng nhập bằng Gmail'),
                    ),
                  ),
                  const Center(
                    child: Text(
                      'Đăng nhập bằng tài khoản đã được cấp.',
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
