import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/review_note_dialog.dart';
import 'operations_screen.dart' show ClosurePage, closurePhotoPreview;

String _when(Object? start, Object? end) {
  String hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final s = utcTime(start).toLocal(), e = utcTime(end).toLocal();
  return '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year} • ${hm(s)}–${hm(e)}';
}

String closureStatusLabel(Object? status) => switch (status) {
  'approved' => 'Đã duyệt',
  'rejected' => 'Bị từ chối',
  _ => 'Chờ duyệt',
};

Color closureStatusColor(Object? status) => switch (status) {
  'approved' => const Color(0xFF1B7F4B),
  'rejected' => const Color(0xFFB3261E),
  _ => const Color(0xFFB45309),
};

/// Ảnh & báo cáo đóng ca. Nhân viên: "Cần đóng ca" (gửi/gửi lại báo cáo) và "Lịch sử đóng ca".
/// Quản lý/Admin: lịch sử lọc theo trạng thái, xem ảnh, duyệt hoặc từ chối kèm lý do.
class ClosuresScreen extends StatefulWidget {
  const ClosuresScreen({super.key, required this.repository});
  final WorkforceRepository repository;

  @override
  State<ClosuresScreen> createState() => _ClosuresScreenState();
}

class _ClosuresScreenState extends State<ClosuresScreen> {
  WorkforceRepository get r => widget.repository;
  bool get managing => r.session.role != 'Nhân viên';
  late Future<(List<RowData>, List<RowData>)> loading = _load();
  String filter = 'submitted';

  Future<(List<RowData>, List<RowData>)> _load() async =>
      (managing ? <RowData>[] : await r.closureTasks(), await r.closures());

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      loading = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  void _say(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _review(RowData c, bool approve) async {
    final note = await askReviewNote(
      context,
      approve: approve,
      label: '${c['full_name']}',
      subject: 'báo cáo đóng ca của',
    );
    if (note == null) return;
    try {
      await r.reviewClosure(c['id'] as int, approve, note: note);
      _say(approve ? 'Đã duyệt báo cáo đóng ca.' : 'Đã từ chối báo cáo.');
      await _refresh();
    } on AuthException catch (e) {
      _say(e.message);
    } catch (_) {
      _say('Không thực hiện được thao tác.');
    }
  }

  Future<void> _openClosure(int assignmentId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ClosurePage(repository: r, assignmentId: assignmentId),
      ),
    );
    if (mounted) await _refresh();
  }

  void _zoom(RowData photo) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: closurePhotoPreview(photo, height: 420),
            ),
          ),
          Positioned(
            right: 0,
            child: IconButton(
              tooltip: 'Đóng',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _card({required Widget child}) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFD5E7E4)),
    ),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  Widget _task(RowData t) {
    final ready = t['ready'] == true;
    final rejected = t['closure_status'] == 'rejected';
    final id = t['assignment_id'] as int;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _when(t['starts_at'], t['ends_at']),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              if (rejected)
                _chip('Cần gửi lại', closureStatusColor('rejected'))
              else
                _chip(
                  ready ? 'Sẵn sàng đóng ca' : 'Chưa ra ca',
                  ready ? const Color(0xFF1B7F4B) : const Color(0xFFB45309),
                ),
            ],
          ),
          Text('${t['branch_name']}', style: const TextStyle(color: muted)),
          if (rejected && (t['review_note'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Lý do từ chối: ${t['review_note']}'),
            ),
          if (!ready && t['blocked'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${t['blocked']}'),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: Key('closure-task-$id'),
              onPressed: ready ? () => _openClosure(id) : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(rejected ? 'Gửi lại báo cáo' : 'Chụp ảnh & đóng ca'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _history(RowData c) {
    final photos = (c['photos'] as List).cast<RowData>();
    final status = c['status'];
    final reviewNote = (c['review_note'] ?? '').toString().trim();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  managing
                      ? '${c['full_name']}'
                      : _when(c['starts_at'], c['ends_at']),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              _chip(closureStatusLabel(status), closureStatusColor(status)),
            ],
          ),
          if (managing)
            Text(
              _when(c['starts_at'], c['ends_at']),
              style: const TextStyle(color: muted),
            ),
          Text(
            '${c['branch_name']} • Gửi lúc ${_stamp(c['submitted_at'])}',
            style: const TextStyle(color: muted),
          ),
          if ((c['note'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Ghi chú: ${c['note']}'),
            ),
          if (status != 'submitted')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${status == 'approved' ? 'Duyệt' : 'Từ chối'} bởi ${c['reviewer'] ?? '—'}'
                '${c['reviewed_at'] == null ? '' : ' lúc ${_stamp(c['reviewed_at'])}'}'
                '${reviewNote.isEmpty ? '' : '\nNhận xét: $reviewNote'}',
              ),
            ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in photos)
                    GestureDetector(
                      key: Key('closure-photo-${p['id']}'),
                      onTap: () => _zoom(p),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: closurePhotoPreview(
                            p,
                            height: 96,
                            caption: false,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Text(
              'Chạm vào ảnh để xem lớn.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
          if (managing && status == 'submitted')
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: Key('closure-reject-${c['id']}'),
                  onPressed: () => _review(c, false),
                  child: const Text('Từ chối'),
                ),
                FilledButton(
                  key: Key('closure-approve-${c['id']}'),
                  onPressed: () => _review(c, true),
                  child: const Text('Duyệt'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _stamp(Object? v) {
    final t = utcTime(v).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} ${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  Widget _list(List<Widget> children, String empty) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: children.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(empty)),
              ),
            ]
          : children,
    ),
  );

  Widget _managerBody(List<RowData> all) {
    final rows = filter == 'all'
        ? all
        : all.where((c) => c['status'] == filter).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in const [
                ('submitted', 'Chờ duyệt'),
                ('approved', 'Đã duyệt'),
                ('rejected', 'Từ chối'),
                ('all', 'Tất cả'),
              ])
                ChoiceChip(
                  key: Key('closure-filter-${f.$1}'),
                  label: Text(
                    '${f.$2} (${f.$1 == 'all' ? all.length : all.where((c) => c['status'] == f.$1).length})',
                  ),
                  selected: filter == f.$1,
                  onSelected: (_) => setState(() => filter = f.$1),
                ),
            ],
          ),
        ),
        Expanded(
          child: _list([
            for (final c in rows) _history(c),
          ], 'Không có báo cáo đóng ca nào.'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(List<RowData>, List<RowData>)>(
        future: loading,
        builder: (context, snapshot) {
          Widget body;
          if (snapshot.hasError) {
            final e = snapshot.error;
            body = Center(
              child: TextButton(
                onPressed: _refresh,
                child: Text(
                  e is AuthException ? e.message : 'Không tải được. Thử lại.',
                ),
              ),
            );
          } else if (!snapshot.hasData) {
            body = const Center(child: CircularProgressIndicator());
          } else if (managing) {
            body = _managerBody(snapshot.data!.$2);
          } else {
            final (tasks, history) = snapshot.data!;
            body = TabBarView(
              children: [
                _list(
                  [for (final t in tasks) _task(t)],
                  'Không có ca nào cần đóng. Ca xuất hiện ở đây sau khi bạn điểm danh vào ca.',
                ),
                _list([
                  for (final c in history) _history(c),
                ], 'Chưa có báo cáo đóng ca nào.'),
              ],
            );
          }
          final count = snapshot.hasData && !managing
              ? snapshot.data!.$1.length
              : 0;
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Ảnh & báo cáo đóng ca'),
                bottom: managing
                    ? null
                    : TabBar(
                        tabs: [
                          Tab(
                            text: count > 0
                                ? 'Cần đóng ca ($count)'
                                : 'Cần đóng ca',
                          ),
                          const Tab(text: 'Lịch sử đóng ca'),
                        ],
                      ),
              ),
              body: body,
            ),
          );
        },
      );
}
