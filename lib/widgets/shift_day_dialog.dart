import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Nhãn trạng thái nhỏ ở cuối thẻ ca (ví dụ "CHƯA ĐIỂM DANH").
class ShiftChip {
  const ShiftChip(this.label, this.background, this.foreground, {this.onTap});
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
}

/// Một ca trong hộp thoại thông tin theo ngày.
class ShiftDayItem {
  const ShiftDayItem({
    required this.slot,
    required this.color,
    required this.start,
    required this.end,
    required this.branch,
    required this.code,
    required this.title,
    this.lines = const [],
    this.chips = const [],
    this.highlighted = false,
    this.boxLabel = 'Chi nhánh',
  });

  /// Nhãn ca trong ngày, ví dụ "Ca 1".
  final String slot;
  final Color color;
  final DateTime start;
  final DateTime end;
  final String branch;
  final String code;
  final String title;

  /// Các dòng "Nhãn: giá trị" hiển thị dưới tiêu đề.
  final List<MapEntry<String, String>> lines;
  final List<ShiftChip> chips;

  /// Ca người dùng vừa bấm xem (viền đậm hơn).
  final bool highlighted;

  /// Nhãn nhỏ của ô thông tin đầu thẻ (mặc định "Chi nhánh"; ngày nghỉ phép dùng "Loại nghỉ").
  final String boxLabel;
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Hiện bảng thông tin chi tiết của toàn bộ ca trong một ngày.
Future<void> showShiftDayDialog(
  BuildContext context, {
  required DateTime day,
  required List<ShiftDayItem> items,
}) => showDialog<void>(
  context: context,
  builder: (_) => ShiftDayDialog(day: day, items: items),
);

class ShiftDayDialog extends StatelessWidget {
  const ShiftDayDialog({super.key, required this.day, required this.items});
  final DateTime day;
  final List<ShiftDayItem> items;

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('shift-day-dialog'),
    backgroundColor: const Color(0xFFF1F8F7),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: ink,
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dmy(day),
                    key: const Key('shift-day-title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                InkWell(
                  key: const Key('shift-day-close'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3A5A52),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Không có ca nào trong ngày này.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ShiftCard(item: items[i]),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.item});
  final ShiftDayItem item;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: item.highlighted ? item.color : const Color(0xFFD5E7E4),
        width: item.highlighted ? 1.6 : 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 5, color: item.color),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
            child: SizedBox(
              width: 54,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.slot,
                      style: TextStyle(
                        color: item.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hm(item.start),
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFD5DBD8),
                    ),
                  ),
                  Text(
                    _hm(item.end),
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.boxLabel,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                        Text(
                          item.branch,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.code,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final line in item.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${line.key}: ${line.value}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  if (item.chips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final c in item.chips) _Chip(chip: c)],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.chip});
  final ShiftChip chip;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chip.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        chip.label,
        style: TextStyle(
          color: chip.foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (chip.onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: chip.onTap,
      child: body,
    );
  }
}
