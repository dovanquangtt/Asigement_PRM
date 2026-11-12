import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';

/// Giai đoạn của một yêu cầu đổi ca (hiển thị cho cả hai bên và quản lý).
enum SwapStage {
  waitingCounterpart,
  waitingManager,
  approved,
  rejectedByCounterpart,
  rejectedByManager,
  cancelled,
}

SwapStage swapStage(RowData r) => switch ('${r['status']}') {
  'approved' => SwapStage.approved,
  'cancelled' => SwapStage.cancelled,
  'rejected' =>
    '${r['counterpart_status']}' == 'rejected'
        ? SwapStage.rejectedByCounterpart
        : SwapStage.rejectedByManager,
  _ =>
    '${r['counterpart_status']}' == 'accepted'
        ? SwapStage.waitingManager
        : SwapStage.waitingCounterpart,
};

class SwapStageStyle {
  const SwapStageStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

SwapStageStyle swapStageStyle(SwapStage stage, String counterpartName) =>
    switch (stage) {
      SwapStage.waitingCounterpart => SwapStageStyle(
        'Chờ $counterpartName đồng ý',
        const Color(0xFFE08A1E),
        Icons.hourglass_top_rounded,
      ),
      SwapStage.waitingManager => const SwapStageStyle(
        'Hai bên đã đồng ý • chờ quản lý duyệt',
        Color(0xFF2F6FDE),
        Icons.how_to_reg_rounded,
      ),
      SwapStage.approved => const SwapStageStyle(
        'Đã đổi ca',
        Color(0xFF1E9E4A),
        Icons.check_circle_rounded,
      ),
      SwapStage.rejectedByCounterpart => SwapStageStyle(
        '$counterpartName đã từ chối',
        const Color(0xFFC0392B),
        Icons.cancel_rounded,
      ),
      SwapStage.rejectedByManager => const SwapStageStyle(
        'Quản lý đã từ chối',
        Color(0xFFC0392B),
        Icons.cancel_rounded,
      ),
      SwapStage.cancelled => const SwapStageStyle(
        'Người gửi đã hủy',
        Color(0xFF7F8C8D),
        Icons.block_rounded,
      ),
    };

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

const _weekday = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// "T4 12/11 08:00–12:00" theo giờ địa phương.
String shiftText(Object? startUtc, Object? endUtc) {
  final s = utcTime(startUtc).toLocal();
  final e = utcTime(endUtc).toLocal();
  return '${_weekday[s.weekday - 1]} ${_dm(s)} ${_hm(s)}–${_hm(e)}';
}

/// Thẻ một yêu cầu đổi ca: hai ca đổi cho nhau, lý do, trạng thái từng bước (người gửi → người nhận
/// → quản lý) và các nút phù hợp với vai trò của người đang xem.
class SwapRequestCard extends StatelessWidget {
  const SwapRequestCard({
    super.key,
    required this.row,
    required this.myUserId,
    required this.reviewer,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
    required this.onApprove,
    required this.onDeny,
  });

  final RowData row;
  final int myUserId;

  /// Quản lý/Admin có quyền duyệt đổi ca.
  final bool reviewer;
  final VoidCallback onAccept, onReject, onCancel, onApprove, onDeny;

  Widget _shiftBox(String who, String text, {required bool mine}) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFE9F2EE) : const Color(0xFFF1F8F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            who,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _step(IconData icon, Color color, String text, {Key? key}) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final id = row['id'];
    final from = '${row['from_name']}', to = '${row['to_name']}';
    final stage = swapStage(row);
    final style = swapStageStyle(stage, to);
    final counterpart = '${row['counterpart_status']}';
    final isRequester = row['requested_by'] == myUserId;
    final isCounterpart = row['target_user_id'] == myUserId;
    final pending = '${row['status']}' == 'pending';
    final canRespond = isCounterpart && stage == SwapStage.waitingCounterpart;
    final canCancel = isRequester && pending;
    final canReview =
        reviewer &&
        !isRequester &&
        !isCounterpart &&
        stage == SwapStage.waitingManager;
    final reviewerName = '${row['reviewer_name'] ?? ''}'.trim();
    const grey = Color(0xFF7F8C8D);
    const green = Color(0xFF1E9E4A);
    const red = Color(0xFFC0392B);
    const orange = Color(0xFFE08A1E);
    return Card(
      key: Key('swap-card-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: style.color.withValues(alpha: 0.5), width: 1.4),
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
                    '$from ⇄ $to',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                if (isRequester || isCounterpart)
                  Text(
                    isRequester ? 'Bạn gửi' : 'Gửi cho bạn',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _shiftBox(
                    'Ca của $from',
                    shiftText(row['from_start'], row['from_end']),
                    mine: isRequester,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.swap_horiz_rounded, color: muted),
                  ),
                  _shiftBox(
                    'Ca của $to',
                    shiftText(row['to_start'], row['to_end']),
                    mine: isCounterpart,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lý do: ${row['reason']}',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Container(
              key: Key('swap-stage-$id'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: style.color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.icon, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      style.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Trạng thái từng bước: người gửi → người nhận → quản lý.
            _step(
              Icons.check_circle_rounded,
              green,
              '$from đã gửi yêu cầu (đồng ý đổi)',
            ),
            _step(
              counterpart == 'accepted'
                  ? Icons.check_circle_rounded
                  : counterpart == 'rejected'
                  ? Icons.cancel_rounded
                  : Icons.hourglass_top_rounded,
              counterpart == 'accepted'
                  ? green
                  : counterpart == 'rejected'
                  ? red
                  : stage == SwapStage.cancelled
                  ? grey
                  : orange,
              counterpart == 'accepted'
                  ? '$to đã đồng ý'
                  : counterpart == 'rejected'
                  ? '$to đã từ chối'
                  : stage == SwapStage.cancelled
                  ? '$to chưa kịp trả lời'
                  : 'Chờ $to đồng ý hoặc từ chối',
              key: Key('swap-step-counterpart-$id'),
            ),
            _step(
              switch (stage) {
                SwapStage.approved => Icons.check_circle_rounded,
                SwapStage.rejectedByManager => Icons.cancel_rounded,
                SwapStage.waitingManager => Icons.hourglass_top_rounded,
                _ => Icons.remove_circle_outline_rounded,
              },
              switch (stage) {
                SwapStage.approved => green,
                SwapStage.rejectedByManager => red,
                SwapStage.waitingManager => orange,
                _ => grey,
              },
              switch (stage) {
                SwapStage.approved =>
                  'Quản lý${reviewerName.isEmpty ? '' : ' ($reviewerName)'} đã duyệt, lịch ca đã đổi',
                SwapStage.rejectedByManager =>
                  'Quản lý${reviewerName.isEmpty ? '' : ' ($reviewerName)'} đã từ chối',
                SwapStage.waitingManager => 'Chờ quản lý duyệt',
                SwapStage.waitingCounterpart =>
                  'Quản lý duyệt sau khi hai bên đồng ý',
                _ => 'Không cần quản lý duyệt',
              },
              key: Key('swap-step-manager-$id'),
            ),
            if (canRespond || canCancel || canReview) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canRespond) ...[
                    FilledButton.icon(
                      key: Key('swap-accept-$id'),
                      onPressed: onAccept,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Đồng ý đổi'),
                    ),
                    OutlinedButton.icon(
                      key: Key('swap-reject-$id'),
                      onPressed: onReject,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Từ chối'),
                    ),
                  ],
                  if (canCancel)
                    OutlinedButton.icon(
                      key: Key('swap-cancel-$id'),
                      onPressed: onCancel,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Hủy yêu cầu'),
                    ),
                  if (canReview) ...[
                    FilledButton.icon(
                      key: Key('swap-approve-$id'),
                      onPressed: onApprove,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Duyệt đổi'),
                    ),
                    OutlinedButton.icon(
                      key: Key('swap-deny-$id'),
                      onPressed: onDeny,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Không duyệt'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Màn "Đổi ca". Nhân viên có hai tab: **Ca có thể đổi** (chọn ca của mình rồi ca muốn đổi của đồng
/// nghiệp) và **Yêu cầu đổi ca** (trạng thái, đồng ý/từ chối, hủy). Quản lý/Admin chỉ thấy danh sách
/// yêu cầu để duyệt khi cả hai bên đã đồng ý.
class ShiftSwapScreen extends StatefulWidget {
  const ShiftSwapScreen({
    super.key,
    required this.repository,
    this.initialAssignmentId,
  });
  final WorkforceRepository repository;

  /// Phân ca của mình cần đổi: mở thẳng bước chọn ca muốn đổi (từ nút "Đổi ca" trên thẻ ca).
  final int? initialAssignmentId;

  @override
  State<ShiftSwapScreen> createState() => _ShiftSwapScreenState();
}

class _ShiftSwapScreenState extends State<ShiftSwapScreen>
    with SingleTickerProviderStateMixin {
  WorkforceRepository get r => widget.repository;
  bool get _reviewer => r.session.role != 'Nhân viên';
  late final TabController _tabs = TabController(
    length: _reviewer ? 1 : 2,
    vsync: this,
  );
  late Future<List<RowData>> _requests = r.swaps();
  Future<List<RowData>>? _mine;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!_reviewer) {
      _mine = r.swappableShifts();
      final initial = widget.initialAssignmentId;
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openInitial(initial),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _reload() {
    setState(() {
      _requests = r.swaps();
      if (!_reviewer) _mine = r.swappableShifts();
    });
  }

  Future<void> _openInitial(int assignmentId) async {
    try {
      final list = await _mine!;
      final mine = list.where((s) => s['id'] == assignmentId).firstOrNull;
      if (!mounted || mine == null) return;
      final blocker = mine['blocker'] as String?;
      if (blocker != null) {
        _snack('Ca này chưa đổi được: $blocker');
      } else if (mine['options_count'] == 0 && mine['open_count'] == 0) {
        _snack('Chưa có ca nào phù hợp để đổi với ca này.');
      } else {
        await _pick(mine);
      }
    } catch (_) {}
  }

  /// Chạy một thao tác ghi dữ liệu: hiện kết quả/lỗi rồi tải lại.
  Future<void> _run(Future<void> Function() work, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
      _snack(success);
      _reload();
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Không thực hiện được. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Không'),
            ),
            FilledButton(
              key: const Key('swap-confirm'),
              onPressed: () => Navigator.pop(c, true),
              child: Text(ok),
            ),
          ],
        ),
      ) ??
      false;

  /// Bước 2: chọn ca của đồng nghiệp muốn đổi (xếp theo ngày từ bé đến lớn), rồi xác nhận + lý do.
  Future<void> _pick(RowData mine) async {
    final List<RowData> options;
    final List<RowData> openTargets;
    try {
      options = await r.swapOptions(mine['id'] as int);
      openTargets = await r.openSwapTargets(mine['id'] as int);
    } on AuthException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    if (options.isEmpty && openTargets.isEmpty) {
      _snack('Chưa có ca nào phù hợp để đổi với ca này.');
      return;
    }
    final target = await showModalBottomSheet<RowData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text(
              'Chọn ca muốn đổi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Ca của bạn: ${shiftText(mine['starts_at'], mine['ends_at'])} • ${mine['branch_name']}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 4),
            const Text(
              'Chỉ hiện các ca sắp tới của đồng nghiệp mà hai bên đổi được cho nhau '
              '(không trùng giờ, không nghỉ phép).',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 8),
            if (openTargets.isNotEmpty) ...[
              const Text(
                'Ca còn trống (đổi ngay, không cần đồng nghiệp đồng ý)',
                style: TextStyle(fontWeight: FontWeight.w800, color: green),
              ),
              for (final o in openTargets)
                Card(
                  key: Key('swap-open-${o['id']}'),
                  elevation: 0,
                  margin: const EdgeInsets.only(top: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFD5E7E4)),
                  ),
                  child: ListTile(
                    title: Text(
                      shiftText(o['starts_at'], o['ends_at']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${o['branch_name']} • ${o['assigned_count']}/${o['required_staff']} người',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(c, {...o, 'is_open': true}),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (options.isNotEmpty)
              const Text(
                'Ca của đồng nghiệp (cần đồng nghiệp đồng ý, rồi quản lý duyệt)',
                style: TextStyle(fontWeight: FontWeight.w800, color: green),
              ),
            for (final o in options)
              Card(
                key: Key('swap-option-${o['id']}'),
                elevation: 0,
                margin: const EdgeInsets.only(top: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFD5E7E4)),
                ),
                child: ListTile(
                  title: Text(
                    shiftText(o['starts_at'], o['ends_at']),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('${o['full_name']} • ${o['branch_name']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(c, o),
                ),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    if (target['is_open'] == true) {
      final ok = await _confirm(
        'Đổi sang ca còn trống?',
        'Bạn sẽ bỏ ca ${shiftText(mine['starts_at'], mine['ends_at'])} và nhận ca '
            '${shiftText(target['starts_at'], target['ends_at'])}. Có hiệu lực ngay, quản lý được báo.',
        'Đổi ca',
      );
      if (!ok || !mounted) return;
      await _run(
        () => r.swapToOpenShift(mine['id'] as int, target['id'] as int),
        'Đã đổi sang ca mới. Ca đã có trong lịch của bạn.',
      );
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _SwapConfirmDialog(mine: mine, target: target),
    );
    if (reason == null || !mounted) return;
    await _run(
      () => r.requestSwap(mine['id'] as int, target['id'] as int, reason),
      'Đã gửi yêu cầu. Chờ ${target['full_name']} đồng ý.',
    );
    if (mounted && !_reviewer) _tabs.animateTo(1);
  }

  Widget _mineTab() => FutureBuilder<List<RowData>>(
    future: _mine,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: _reload,
            child: const Text('Không tải được danh sách ca. Thử lại.'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final list = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Chọn ca của bạn muốn nhường, rồi chọn ca của đồng nghiệp muốn đổi. Đồng nghiệp '
            'đồng ý thì quản lý mới duyệt.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Container(
              key: const Key('swap-mine-empty'),
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('Bạn chưa có ca nào sắp tới để đổi.'),
            ),
          for (final s in list) _mineCard(s),
        ],
      );
    },
  );

  Widget _mineCard(RowData s) {
    final id = s['id'];
    final blocker = s['blocker'] as String?;
    final options = (s['options_count'] as int?) ?? 0;
    final openCount = (s['open_count'] as int?) ?? 0;
    final canPick = blocker == null && (options > 0 || openCount > 0);
    final (label, color) = blocker != null
        ? (blocker, const Color(0xFF7F8C8D))
        : options + openCount == 0
        ? ('Chưa có ca phù hợp để đổi', const Color(0xFF7F8C8D))
        : (
            openCount == 0
                ? '$options ca có thể đổi'
                : [
                    if (options > 0) '$options ca của đồng nghiệp',
                    if (openCount > 0) '$openCount ca còn trống',
                  ].join(' • '),
            const Color(0xFF1E9E4A),
          );
    return Card(
      key: Key('swap-mine-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shiftText(s['starts_at'], s['ends_at']),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text('${s['branch_name']}', style: const TextStyle(color: muted)),
            const SizedBox(height: 8),
            Container(
              key: Key('swap-mine-status-$id'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: Key('swap-pick-$id'),
              onPressed: canPick && !_busy ? () => _pick(s) : null,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Chọn ca để đổi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestsTab() => FutureBuilder<List<RowData>>(
    future: _requests,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: _reload,
            child: const Text('Không tải được yêu cầu. Thử lại.'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final list = snapshot.data!;
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_reviewer)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Chỉ duyệt được khi người gửi và người nhận đều đã đồng ý.',
                  style: TextStyle(color: muted),
                ),
              ),
            if (list.isEmpty)
              Container(
                key: const Key('swap-empty'),
                padding: const EdgeInsets.all(28),
                alignment: Alignment.center,
                child: const Text('Chưa có yêu cầu đổi ca nào.'),
              ),
            for (final row in list)
              SwapRequestCard(
                row: row,
                myUserId: r.session.userId,
                reviewer: _reviewer,
                onAccept: () async {
                  if (await _confirm(
                    'Đồng ý đổi ca?',
                    'Bạn nhận ca ${shiftText(row['from_start'], row['from_end'])} của ${row['from_name']} '
                        'và nhường ca ${shiftText(row['to_start'], row['to_end'])} của bạn. '
                        'Quản lý sẽ duyệt sau khi bạn đồng ý.',
                    'Đồng ý',
                  )) {
                    await _run(
                      () => r.respondSwap(row['id'] as int, true),
                      'Đã đồng ý. Yêu cầu chuyển cho quản lý duyệt.',
                    );
                  }
                },
                onReject: () async {
                  if (await _confirm(
                    'Từ chối đổi ca?',
                    'Yêu cầu sẽ đóng lại và lịch ca được giữ nguyên.',
                    'Từ chối',
                  )) {
                    await _run(
                      () => r.respondSwap(row['id'] as int, false),
                      'Đã từ chối yêu cầu đổi ca.',
                    );
                  }
                },
                onCancel: () async {
                  if (await _confirm(
                    'Hủy yêu cầu đổi ca?',
                    'Yêu cầu sẽ bị rút lại, lịch ca được giữ nguyên.',
                    'Hủy yêu cầu',
                  )) {
                    await _run(
                      () => r.cancelSwap(row['id'] as int),
                      'Đã hủy yêu cầu đổi ca.',
                    );
                  }
                },
                onApprove: () => _run(
                  () => r.respondSwap(row['id'] as int, true, review: true),
                  'Đã duyệt đổi ca. Hai nhân viên đã được thông báo.',
                ),
                onDeny: () => _run(
                  () => r.respondSwap(row['id'] as int, false, review: true),
                  'Đã từ chối. Lịch ca được giữ nguyên.',
                ),
              ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF1F8F7),
    appBar: AppBar(
      title: const Text('Đổi ca'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
      bottom: _reviewer
          ? null
          : TabBar(
              controller: _tabs,
              tabs: const [
                Tab(key: Key('swap-tab-mine'), text: 'Ca có thể đổi'),
                Tab(key: Key('swap-tab-requests'), text: 'Yêu cầu đổi ca'),
              ],
            ),
    ),
    body: _reviewer
        ? _requestsTab()
        : TabBarView(controller: _tabs, children: [_mineTab(), _requestsTab()]),
  );
}

/// Xác nhận đổi ca: tóm tắt hai ca và nhập lý do (bắt buộc). Controller thuộc về hộp thoại để được
/// giải phóng đúng lúc.
class _SwapConfirmDialog extends StatefulWidget {
  const _SwapConfirmDialog({required this.mine, required this.target});
  final RowData mine, target;

  @override
  State<_SwapConfirmDialog> createState() => _SwapConfirmDialogState();
}

class _SwapConfirmDialogState extends State<_SwapConfirmDialog> {
  final controller = TextEditingController();
  bool showError = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gửi yêu cầu đổi ca'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bạn nhường: ${shiftText(widget.mine['starts_at'], widget.mine['ends_at'])}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Bạn nhận: ${shiftText(widget.target['starts_at'], widget.target['ends_at'])} '
            'của ${widget.target['full_name']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('swap-reason'),
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Lý do đổi ca',
              errorText: showError ? 'Nhập lý do đổi ca' : null,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        key: const Key('swap-send'),
        onPressed: () {
          final text = controller.text.trim();
          if (text.isEmpty) {
            setState(() => showError = true);
            return;
          }
          Navigator.pop(context, text);
        },
        child: const Text('Gửi yêu cầu'),
      ),
    ],
  );
}
