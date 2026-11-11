import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const _responseLabels = {
  'pending': 'Chờ xác nhận',
  'accepted': 'Đã chấp nhận',
  'rejected': 'Đã từ chối',
};

const _sheetLabels = {
  'SUCCESS': 'Hoàn tất',
  'PENDING_REVIEW': 'Chờ duyệt',
  'IN_PROGRESS': 'Đang làm',
  'MISSING_CHECK_OUT': 'Thiếu giờ ra',
  'MISSING_CHECK_IN': 'Thiếu giờ vào',
  'REJECTED': 'Bị từ chối',
  'VOIDED': 'Đã hủy công',
  'NOT_STARTED': 'Chưa tới ca',
};

Color shiftResponseColor(String status) => switch (status) {
  'accepted' => Colors.green.shade700,
  'rejected' => Colors.red.shade700,
  _ => Colors.orange.shade800,
};

Color _sheetColor(String? status) => switch (status) {
  'SUCCESS' => Colors.green.shade700,
  'PENDING_REVIEW' || 'IN_PROGRESS' => Colors.orange.shade800,
  'MISSING_CHECK_OUT' ||
  'MISSING_CHECK_IN' ||
  'REJECTED' ||
  'VOIDED' => Colors.red.shade700,
  _ => Colors.blueGrey,
};

/// Thẻ một ca trong "Bảng ca theo nhân viên". Dạng thẻ (không phải bảng ngang) để quản lý
/// thấy giờ vào/ra và nút duyệt/từ chối chấm công ngay trên điện thoại, không cần cuộn ngang.
class EmployeeShiftRowCard extends StatelessWidget {
  const EmployeeShiftRowCard({
    super.key,
    required this.row,
    required this.parseTime,
    required this.onReview,
  });

  final Map<String, Object?> row;

  /// Đọc thời điểm từ dữ liệu (SQLite lưu 'yyyy-MM-dd HH:mm:ss' UTC, API trả ISO).
  final DateTime Function(Object? value) parseTime;

  /// (id sự kiện, true = duyệt / false = từ chối, nhãn "Vào" hoặc "Ra").
  final void Function(int eventId, bool approve, String label) onReview;

  String _clock(Object? value) {
    final d = parseTime(value).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _day(Object? value) {
    final d = parseTime(value).toLocal();
    const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return '${names[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  int? _id(String key) => (row[key] as num?)?.toInt();

  /// Giờ đã ghi công; chưa có thì hiện giờ nhân viên đã gửi đang chờ duyệt.
  String _punch(String key) {
    if (row[key] != null) return _clock(row[key]);
    final pending = row['pending_$key'];
    return pending == null ? '--:--' : '${_clock(pending)} (chờ duyệt)';
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  Widget _timeBox(String title, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: muted)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, color: ink),
          ),
        ],
      ),
    ),
  );

  /// Hai nút duyệt/từ chối cho một lượt điểm danh đang chờ.
  Widget _reviewRow(String label, int id, {required bool canApprove}) => Row(
    children: [
      Expanded(
        child: FilledButton.icon(
          key: Key('approve-$id'),
          onPressed: canApprove ? () => onReview(id, true, label) : null,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: Text('Duyệt $label'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          key: Key('reject-$id'),
          onPressed: () => onReview(id, false, label),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade200),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: Text('Từ chối $label'),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final response = '${row['response_status']}';
    final sheet = row['sheet_status'] as String?;
    final inId = _id('pending_check_in_id');
    final outId = _id('pending_check_out_id');
    final rejected = response == 'rejected';
    final note = rejected
        ? 'Lý do: ${row['response_note'] ?? ''}'
        : 'Phân bởi ${row['assigned_by_name'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFD5E7E4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _day(row['starts_at']),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                Text(
                  '${_clock(row['starts_at'])}-${_clock(row['ends_at'])}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${row['branch_name']}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(
                  _responseLabels[response] ?? response,
                  shiftResponseColor(response),
                ),
                if (sheet != null)
                  _chip(_sheetLabels[sheet] ?? sheet, _sheetColor(sheet)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _timeBox('Vào', _punch('check_in_at')),
                const SizedBox(width: 8),
                _timeBox('Ra', _punch('check_out_at')),
              ],
            ),
            if (inId != null || outId != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Phản hồi chấm công',
                style: TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
              const SizedBox(height: 6),
              if (inId != null) _reviewRow('Vào', inId, canApprove: true),
              if (inId != null && outId != null) const SizedBox(height: 6),
              if (outId != null)
                _reviewRow('Ra', outId, canApprove: inId == null),
              if (outId != null && inId != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Hãy duyệt vào ca trước khi duyệt ra ca.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(note, style: const TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
  }
}
