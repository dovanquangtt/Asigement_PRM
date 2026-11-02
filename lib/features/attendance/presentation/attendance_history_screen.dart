import 'package:flutter/material.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../theme/app_colors.dart';
import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';
import 'attendance_ui.dart';

/// Personal attendance history: month navigation or a custom date range, paged.
class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key, this.client, this.pageSize = 20});
  final ApiClient? client;
  final int pageSize;
  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late final AttendanceRepository repo = AttendanceRepository(widget.client);
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTimeRange? custom;
  final List<HistoryItem> items = [];
  int page = 0;
  bool hasMore = false, loading = true, loadingMore = false;
  int total = 0;
  String? error;
  int _generation = 0;

  DateTime get from => custom?.start ?? month;
  DateTime get to => custom?.end ?? DateTime(month.year, month.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      loading = true;
      error = null;
      items.clear();
      page = 0;
    });
    try {
      final result = await repo.history(from: from, to: to, size: widget.pageSize);
      if (!mounted || generation != _generation) return;
      setState(() {
        items.addAll(result.items);
        hasMore = result.hasMore;
        total = result.totalItems;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        error = attendanceErrorMessage(e);
        loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (loadingMore || !hasMore) return;
    final generation = _generation;
    setState(() => loadingMore = true);
    try {
      final result = await repo.history(
        from: from,
        to: to,
        page: page + 1,
        size: widget.pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        page = result.page;
        items.addAll(result.items);
        hasMore = result.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(attendanceErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  void _shiftMonth(int delta) {
    custom = null;
    month = DateTime(month.year, month.month + delta);
    _reload();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: custom ?? DateTimeRange(start: from, end: to),
      helpText: 'Chọn khoảng ngày',
    );
    if (picked == null || !mounted) return;
    custom = picked;
    _reload();
  }

  Widget _tile(HistoryItem item) {
    final start = item.shift?.startsAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AttendanceDetailScreen(
              attendanceId: item.attendanceId,
              client: widget.client,
            ),
          ),
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
                      start == null ? item.date : fmtWeekday(start),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Badge2(statusLabel(item.status), statusColor(item.status)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Ca: ${fmtShift(item.shift)}', style: const TextStyle(color: muted)),
              const SizedBox(height: 4),
              Text(
                'Vào ${fmtTime(item.checkInAt)} · Ra ${fmtTime(item.checkOutAt)}'
                '${item.workedMinutes > 0 ? ' · ${fmtMinutes(item.workedMinutes)}' : ''}',
              ),
              if (item.late)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Badge2(
                    item.lateMinutes > 0 ? 'Đi muộn ${item.lateMinutes} phút' : 'Đi muộn',
                    Colors.orange.shade800,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Lịch sử chấm công'),
      actions: [
        IconButton(
          tooltip: 'Chọn khoảng ngày',
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  custom == null
                      ? 'Tháng ${month.month}/${month.year}'
                      : '${fmtDate(custom!.start)} – ${fmtDate(custom!.end)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        TextButton(onPressed: _reload, child: const Text('Thử lại')),
                      ],
                    ),
                  ),
                )
              : items.isEmpty
              ? const Center(child: Text('Không có dữ liệu chấm công trong khoảng này.'))
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('$total ca làm'),
                      ),
                      for (final item in items) _tile(item),
                      if (hasMore)
                        TextButton(
                          onPressed: loadingMore ? null : _more,
                          child: Text(loadingMore ? 'Đang tải…' : 'Tải thêm'),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

/// One shift's attendance: timestamps, every check-in/out event with its verification, exceptions.
class AttendanceDetailScreen extends StatefulWidget {
  const AttendanceDetailScreen({super.key, required this.attendanceId, this.client});
  final int attendanceId;
  final ApiClient? client;
  @override
  State<AttendanceDetailScreen> createState() => _AttendanceDetailScreenState();
}

class _AttendanceDetailScreenState extends State<AttendanceDetailScreen> {
  late final AttendanceRepository repo = AttendanceRepository(widget.client);
  late Future<AttendanceDetail> future = repo.detail(widget.attendanceId);

  void _retry() => setState(() => future = repo.detail(widget.attendanceId));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết chấm công')),
    body: FutureBuilder<AttendanceDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final e = snapshot.error;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is ApiException ? attendanceErrorMessage(e) : 'Không tải được chi tiết.'),
                TextButton(onPressed: _retry, child: const Text('Thử lại')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snapshot.data!;
        final item = d.item;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: item.shift == null ? 'Ca làm' : fmtWeekday(item.shift!.startsAt),
              children: [
                InfoRow('Ca làm', fmtShift(item.shift)),
                InfoRow('Chi nhánh', item.shift?.branchName ?? '—'),
                InfoRow('Giờ vào', fmtDateTime(item.checkInAt)),
                InfoRow('Giờ ra', fmtDateTime(item.checkOutAt)),
                InfoRow('Giờ làm', item.workedMinutes > 0 ? fmtMinutes(item.workedMinutes) : '—'),
                if (item.late)
                  InfoRow('Đi muộn', item.lateMinutes > 0 ? '${item.lateMinutes} phút' : 'Có'),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 118,
                        child: Text('Trạng thái', style: TextStyle(color: muted)),
                      ),
                      Badge2(statusLabel(item.status), statusColor(item.status)),
                    ],
                  ),
                ),
              ],
            ),
            SectionCard(
              title: 'Xác minh GPS và thiết bị',
              children: [VerificationBlock(d.verification)],
            ),
            if (d.exceptions.isNotEmpty)
              SectionCard(
                title: 'Ngoại lệ',
                children: [
                  for (final e in d.exceptions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e)),
                        ],
                      ),
                    ),
                ],
              ),
            SectionCard(
              title: 'Các lần chấm công',
              children: [
                if (d.events.isEmpty)
                  const Text('Chưa có lần chấm công nào.', style: TextStyle(color: muted)),
                for (final ev in d.events) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${eventTypeLabel(ev.type)} · ${fmtDateTime(ev.occurredAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Badge2(
                        eventResultLabel(ev.result),
                        ev.result == 'ACCEPTED'
                            ? Colors.green.shade700
                            : ev.result == 'REJECTED'
                            ? Colors.red.shade700
                            : Colors.orange.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (ev.accuracyMeters != null)
                    Text('Độ chính xác GPS: ±${ev.accuracyMeters!.round()} m'),
                  if (ev.distanceMeters != null && ev.verification?.distanceMeters == null)
                    Text('Cách chi nhánh: ${ev.distanceMeters!.round()} m'),
                  VerificationBlock(ev.verification),
                  if (ev.rejectionReason != null && ev.rejectionReason!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Lý do: ${ev.rejectionReason}'),
                    ),
                  const Divider(height: 22),
                ],
              ],
            ),
          ],
        );
      },
    ),
  );
}
