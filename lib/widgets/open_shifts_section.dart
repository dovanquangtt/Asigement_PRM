import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';

/// "Ca còn trống": các ca quản lý vừa tạo còn chỗ ở chi nhánh của nhân viên, kèm nút đăng ký.
class OpenShiftsSection extends StatefulWidget {
  const OpenShiftsSection({
    super.key,
    required this.repository,
    required this.onRegistered,
  });
  final WorkforceRepository repository;

  /// Gọi sau khi đăng ký thành công để lịch cá nhân tải lại.
  final VoidCallback onRegistered;

  @override
  State<OpenShiftsSection> createState() => _OpenShiftsSectionState();
}

class _OpenShiftsSectionState extends State<OpenShiftsSection> {
  late Future<List<RowData>> loading = widget.repository.openShifts();
  int? busy;

  void _reload() {
    setState(() {
      loading = widget.repository.openShifts();
    });
  }

  Future<void> _register(RowData s) async {
    setState(() => busy = s['id'] as int);
    String message;
    var ok = false;
    try {
      await widget.repository.registerForShift(s['id'] as int);
      message = 'Đã đăng ký ca. Ca đã có trong lịch của bạn.';
      ok = true;
    } on AuthException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Không đăng ký được ca.';
    }
    if (!mounted) return;
    setState(() => busy = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    _reload();
    if (ok) widget.onRegistered();
  }

  static String _label(RowData s) {
    final a = DateTime.parse('${s['starts_at']}Z').toLocal();
    final b = DateTime.parse('${s['ends_at']}Z').toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(a.day)}/${two(a.month)} • ${two(a.hour)}:${two(a.minute)}–${two(b.hour)}:${two(b.minute)}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RowData>>(
    future: loading,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <RowData>[];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Container(
        key: const Key('open-shifts'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderTint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.add_task_outlined, color: green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ca còn trống (${rows.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Quản lý vừa tạo các ca này. Đăng ký nếu bạn rảnh, ca sẽ vào lịch của bạn ngay.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final s in rows)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(s),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          Text(
                            '${s['branch_name']} • ${s['assigned_count']}/${s['required_staff']} người',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      key: Key('register-shift-${s['id']}'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: busy != null ? null : () => _register(s),
                      child: Text(
                        busy == s['id'] ? 'Đang đăng ký…' : 'Đăng ký',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
