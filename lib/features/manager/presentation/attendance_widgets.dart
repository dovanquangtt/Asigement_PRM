import 'package:flutter/material.dart';

import '../../../core/errors/api_exception.dart';
import '../../../screens/attendance_sheet_screen.dart' show sheetStatusColor;

/// User-safe text for any error thrown while calling the API.
String errorText(Object error) {
  if (error is ApiException) {
    if (error.status == 403) {
      return 'Không có quyền thực hiện thao tác hoặc xem dữ liệu này.';
    }
    if (error.isUnauthorized) {
      return 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.';
    }
    return error.message;
  }
  return 'Có lỗi xảy ra. Hãy thử lại.';
}

const sheetStatusLabels = {
  'SUCCESS': 'Thành công',
  'PENDING_REVIEW': 'Chờ duyệt',
  'REJECTED': 'Bị từ chối',
  'IN_PROGRESS': 'Đang trong ca',
  'MISSING_CHECK_IN': 'Thiếu giờ vào',
  'MISSING_CHECK_OUT': 'Thiếu giờ ra',
  'NOT_STARTED': 'Chưa đến ca',
  'VOIDED': 'Đã hủy công',
};

const verificationLabels = {
  'VERIFIED': 'Đạt',
  'FAILED': 'Không đạt',
  'UNKNOWN': 'Chưa có dữ liệu xác minh',
};

String statusLabel(String s) => sheetStatusLabels[s] ?? s;

/// Local (device) wall-clock formatting of an instant.
String clock(DateTime? t) {
  if (t == null) return '--:--';
  final d = t.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String dayText(DateTime t) {
  final d = t.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String dateTimeText(DateTime? t) =>
    t == null ? 'Chưa ghi nhận' : '${dayText(t)} ${clock(t)}';

String hoursText(int minutes) =>
    '${minutes ~/ 60}g${(minutes % 60).toString().padLeft(2, '0')}';

Color verificationColor(String v) => switch (v) {
  'VERIFIED' => Colors.green.shade700,
  'FAILED' => Colors.red.shade700,
  _ => Colors.grey.shade600,
};

class StatusText extends StatelessWidget {
  const StatusText(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Text(
    statusLabel(status),
    style: TextStyle(
      color: sheetStatusColor(status),
      fontWeight: FontWeight.w700,
    ),
  );
}

class VerificationDot extends StatelessWidget {
  const VerificationDot(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$label: ${verificationLabels[value] ?? value}',
    child: Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        value == 'VERIFIED'
            ? Icons.check_circle
            : value == 'FAILED'
            ? Icons.cancel
            : Icons.help_outline,
        size: 16,
        color: verificationColor(value),
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    ),
  );
}

/// Centered error with a retry button; used when a screen cannot load.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}

void showSnack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

/// Dialog that returns a non-empty reason, or null when cancelled.
Future<String?> askReason(
  BuildContext context,
  String title, {
  String confirm = 'Xác nhận',
  String label = 'Lý do (bắt buộc)',
}) async {
  final controller = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('reason-field'),
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(labelText: label, errorText: error),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('reason-confirm'),
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                setState(() => error = 'Nhập lý do.');
              } else {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}
