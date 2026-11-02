import 'package:flutter/material.dart';

/// Kết quả xử lý nổi bật (đã duyệt, đã thu hồi...) hiển thị thay cho các nút thao tác.
class StatusHighlight extends StatelessWidget {
  const StatusHighlight({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  static StatusHighlight approved({Key? key}) => StatusHighlight(
    key: key,
    label: 'ĐÃ DUYỆT',
    color: Colors.green.shade700,
    icon: Icons.check_circle,
  );

  static StatusHighlight revoked({Key? key}) => StatusHighlight(
    key: key,
    label: 'ĐÃ THU HỒI',
    color: Colors.red.shade700,
    icon: Icons.block,
  );

  static StatusHighlight pending({Key? key}) => StatusHighlight(
    key: key,
    label: 'CHỜ DUYỆT',
    color: Colors.orange.shade800,
    icon: Icons.hourglass_top,
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color, width: 1.4),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  );
}
