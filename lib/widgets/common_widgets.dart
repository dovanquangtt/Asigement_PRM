import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
Widget metric(String title, String value, String unit, IconData icon) => panel(
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
