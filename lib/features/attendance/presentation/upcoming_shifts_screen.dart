import 'package:flutter/material.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../../schedule/data/schedule_repository.dart';

/// Ca làm sắp tới của nhân viên (GET /api/employees/me/shifts, 30 ngày tới).
/// Nhân viên chỉ thấy ca sau khi quản lý phân công cho mình.
class UpcomingShiftsScreen extends StatefulWidget {
  const UpcomingShiftsScreen({super.key, this.client, this.days = 30});
  final ApiClient? client;
  final int days;
  @override
  State<UpcomingShiftsScreen> createState() => _UpcomingShiftsScreenState();
}

class _UpcomingShiftsScreenState extends State<UpcomingShiftsScreen> {
  late Future<List<Map<String, dynamic>>> loading = _load();
  bool responding = false;

  ApiClient get _client => widget.client ?? ApiClient.instance;

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> _load() async {
    final today = DateTime.now();
    final rows = await _client.getList(
      '/api/employees/me/shifts',
      query: {
        'from': _date(today),
        'to': _date(today.add(Duration(days: widget.days))),
      },
    );
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      loading = next;
    });
    await next.then((_) {}, onError: (_) {});
  }

  /// Chấp nhận / từ chối ca được phân. Từ chối bắt buộc có lý do.
  Future<void> _respond(Map<String, dynamic> shift, bool accept) async {
    if (responding) return;
    var note = '';
    if (!accept) {
      final controller = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Từ chối ca làm?'),
          content: TextField(
            key: const Key('reject-reason'),
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Lý do (bắt buộc)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('reject-confirm'),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(c, controller.text.trim());
                }
              },
              child: const Text('Từ chối ca'),
            ),
          ],
        ),
      );
      // Let the dialog finish its reverse transition before releasing the controller.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.dispose();
      if (reason == null || !mounted) return;
      note = reason;
    }
    setState(() {
      responding = true;
    });
    try {
      await ScheduleRepository(_client)
          .respond((shift['assignmentId'] as num).toInt(), accept, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Đã chấp nhận ca làm.'
                : 'Đã từ chối ca. Quản lý sẽ được báo.',
          ),
        ),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          responding = false;
        });
      }
    }
  }

  Widget _responseSection(Map<String, dynamic> s) {
    final response = '${s['responseStatus'] ?? 'accepted'}';
    final canRespond =
        response == 'pending' &&
        DateTime.parse(s['startsAt'] as String).isAfter(DateTime.now());
    final (label, color) = switch (response) {
      'pending' => ('Chờ bạn xác nhận', Colors.orange.shade800),
      'rejected' => ('Bạn đã từ chối', Colors.red.shade700),
      _ => ('Đã chấp nhận', Colors.green.shade700),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(
            label: Text(label),
            labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
            side: BorderSide(color: color),
            visualDensity: VisualDensity.compact,
          ),
          if (canRespond)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('accept-${s['assignmentId']}'),
                    onPressed: responding ? null : () => _respond(s, true),
                    icon: const Icon(Icons.check),
                    label: const Text('Chấp nhận'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('reject-${s['assignmentId']}'),
                    onPressed: responding ? null : () => _respond(s, false),
                    icon: const Icon(Icons.close),
                    label: const Text('Từ chối'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static const _status = {
    'NOT_STARTED': 'Chưa đến ca',
    'IN_PROGRESS': 'Đang trong ca',
    'SUCCESS': 'Đã chấm công',
    'PENDING_REVIEW': 'Chờ duyệt',
    'MISSING_CHECK_IN': 'Thiếu giờ vào',
    'MISSING_CHECK_OUT': 'Thiếu giờ ra',
    'REJECTED': 'Bị từ chối',
    'VOIDED': 'Đã hủy công',
  };

  String _time(String iso) {
    final d = DateTime.parse(iso).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _day(String iso) {
    final d = DateTime.parse(iso).toLocal();
    const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return '${names[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ca làm sắp tới'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final e = snapshot.error;
          return Center(
            child: TextButton(
              onPressed: _refresh,
              child: Text(
                e is ApiException
                    ? e.message
                    : 'Không tải được lịch ca. Thử lại.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final shifts = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: shifts.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Chưa có ca nào được phân cho bạn trong 30 ngày tới.\n'
                          'Quản lý cần phân công bạn vào ca thì ca mới hiện ở đây.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: shifts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = shifts[i];
                    return Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.schedule),
                            title: Text(
                              '${_day(s['startsAt'] as String)}  ${_time(s['startsAt'] as String)}–${_time(s['endsAt'] as String)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text('${s['branchName'] ?? ''}'),
                            trailing: Text(
                              _status['${s['status']}'] ?? '${s['status']}',
                            ),
                          ),
                          _responseSection(s),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}
