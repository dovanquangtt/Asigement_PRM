import 'package:flutter/material.dart';

/// Bảng màu riêng của mục Bảng lương: teal, tự chuyển chế độ tối theo hệ thống.
class PayrollColors {
  const PayrollColors._(this.dark);
  final bool dark;

  static PayrollColors of(BuildContext context) =>
      PayrollColors._(Theme.of(context).brightness == Brightness.dark);

  Color get primary => dark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E);
  Color get onPrimary => dark ? const Color(0xFF042F2B) : Colors.white;
  Color get background =>
      dark ? const Color(0xFF0B1F1D) : const Color(0xFFF1F8F7);
  Color get surface => dark ? const Color(0xFF12302D) : Colors.white;
  Color get border => dark ? const Color(0xFF1F4A45) : const Color(0xFFD5E7E4);
  Color get text => dark ? const Color(0xFFE6F4F2) : const Color(0xFF10302D);
  Color get muted => dark ? const Color(0xFF93B7B2) : const Color(0xFF5E7C78);
  Color get good => dark ? const Color(0xFF6EE7B7) : const Color(0xFF1B7F4B);
  Color get warn => dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  Color get bad => dark ? const Color(0xFFFCA5A5) : const Color(0xFFB3261E);
}

/// Bọc một màn hình bằng theme teal (sáng/tối theo hệ thống) chỉ cho các màn Bảng lương.
class PayrollThemed extends StatelessWidget {
  const PayrollThemed({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final c = PayrollColors._(dark);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(primary: c.primary, onPrimary: c.onPrimary, surface: c.surface);
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        brightness: dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: c.background,
        appBarTheme: AppBarTheme(
          backgroundColor: c.background,
          foregroundColor: c.text,
          elevation: 0,
        ),
        dividerColor: c.border,
        textTheme: Typography.material2021().black.apply(
          bodyColor: c.text,
          displayColor: c.text,
        ),
      ),
      child: child,
    );
  }
}

/// Thẻ nội dung của các màn Bảng lương.
class PayrollCard extends StatelessWidget {
  const PayrollCard({super.key, required this.child, this.padding = 16});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final c = PayrollColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

/// Nhãn trạng thái bo tròn.
class PayrollChip extends StatelessWidget {
  const PayrollChip(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

/// Một dòng "tên — số tiền".
class PayrollLine extends StatelessWidget {
  const PayrollLine(
    this.label,
    this.value, {
    super.key,
    this.bold = false,
    this.sub,
    this.color,
  });
  final String label;
  final String value;
  final String? sub;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PayrollColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: bold ? c.text : c.muted,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                if (sub != null)
                  Text(sub!, style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: bold ? 18 : 15,
              color: color ?? (bold ? c.primary : c.text),
            ),
          ),
        ],
      ),
    );
  }
}
