import 'package:flutter/material.dart';

/// Hỏi nhận xét/lý do khi duyệt hoặc từ chối một lượt điểm danh. Trả về nội dung đã trim,
/// hoặc null nếu hủy. Từ chối bắt buộc có lý do (nút xác nhận không đóng hộp thoại khi trống).
Future<String?> askReviewNote(
  BuildContext context, {
  required bool approve,
  required String label,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReviewNoteDialog(approve: approve, label: label),
);

class _ReviewNoteDialog extends StatefulWidget {
  const _ReviewNoteDialog({required this.approve, required this.label});
  final bool approve;
  final String label;

  @override
  State<_ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState extends State<_ReviewNoteDialog> {
  // Sở hữu controller trong State để dispose đúng lúc hộp thoại đã gỡ khỏi cây widget.
  final controller = TextEditingController();
  bool showError = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.approve ? 'Duyệt' : 'Từ chối'} điểm danh ${widget.label}',
    ),
    content: TextField(
      key: const Key('review-note'),
      controller: controller,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: widget.approve ? 'Nhận xét (nếu có)' : 'Lý do từ chối',
        errorText: showError ? 'Nhập lý do từ chối' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        key: const Key('review-confirm'),
        onPressed: () {
          final note = controller.text.trim();
          if (!widget.approve && note.isEmpty) {
            setState(() => showError = true);
            return;
          }
          Navigator.pop(context, note);
        },
        child: Text(widget.approve ? 'Duyệt' : 'Từ chối'),
      ),
    ],
  );
}
