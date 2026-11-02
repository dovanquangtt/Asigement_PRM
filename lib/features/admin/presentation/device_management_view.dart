import 'package:flutter/material.dart';

import '../../../widgets/status_highlight.dart';

import '../../manager/data/attendance_models.dart';
import '../../manager/presentation/attendance_widgets.dart';
import '../data/admin_repository.dart';

const deviceStatusLabels = {
  'PENDING': 'Chờ duyệt',
  'APPROVED': 'Đã duyệt',
  'REVOKED': 'Đã thu hồi',
};

/// Registered devices: filter by status, search, page, approve or revoke (reason required).
class DeviceManagementView extends StatefulWidget {
  const DeviceManagementView({super.key, required this.repository});
  final AdminRepository repository;
  @override
  State<DeviceManagementView> createState() => _DeviceManagementViewState();
}

class _DeviceManagementViewState extends State<DeviceManagementView> {
  String? status;
  final search = TextEditingController();
  final items = <DeviceItem>[];
  int page = 0;
  bool hasNext = false, loading = true, busy = false;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      items.clear();
      error = null;
      loading = true;
    });
    await load(0, ++generation);
  }

  Future<void> load(int next, int gen) async {
    try {
      final result = await widget.repository.devices(
        status: status,
        q: search.text,
        page: next,
      );
      if (mounted && gen == generation) {
        setState(() {
          items.addAll(result.items);
          page = result.page;
          hasNext = result.hasNext;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && gen == generation) {
        setState(() {
          error = errorText(e);
          loading = false;
        });
      }
    }
  }

  Future<void> act(Future<void> Function() action, String done) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      showSnack(context, done);
      await reload();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(DeviceItem d) async {
    final reason = await askReason(
      context,
      'Thu hồi thiết bị của ${d.employeeName}?',
      confirm: 'Thu hồi',
    );
    if (reason == null) return;
    await act(
      () => widget.repository.revokeDevice(d.id, reason: reason),
      'Đã thu hồi thiết bị.',
    );
  }

  Future<void> approve(DeviceItem d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Duyệt thiết bị của ${d.employeeName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('approve-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Duyệt'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await act(
      () => widget.repository.approveDevice(d.id),
      'Đã duyệt thiết bị.',
    );
  }

  Color statusColor(String s) => switch (s) {
    'APPROVED' => Colors.green.shade700,
    'PENDING' => Colors.orange.shade800,
    _ => Colors.red.shade700,
  };

  Widget tile(DeviceItem d) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d.employeeName} (${d.employeeCode})',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Thiết bị ${d.deviceIdentifierMasked} · ${d.platform ?? 'không rõ'}',
          ),
          Text('Đăng ký: ${dateTimeText(d.registeredAt)}'),
          if (d.approvedByName != null) Text('Duyệt bởi: ${d.approvedByName}'),
          if (d.revokedAt != null)
            Text('Thu hồi: ${dateTimeText(d.revokedAt)}'),
          const SizedBox(height: 6),
          if (d.status == 'PENDING')
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: Key('approve-${d.id}'),
                  onPressed: busy ? null : () => approve(d),
                  child: const Text('Duyệt'),
                ),
                TextButton(
                  key: Key('revoke-${d.id}'),
                  onPressed: busy ? null : () => revoke(d),
                  child: const Text('Thu hồi'),
                ),
              ],
            )
          else if (d.status == 'APPROVED')
            Row(
              children: [
                StatusHighlight.approved(key: Key('status-${d.id}')),
                const Spacer(),
                PopupMenuButton<String>(
                  key: Key('more-${d.id}'),
                  tooltip: 'Thao tác khác',
                  enabled: !busy,
                  onSelected: (_) => revoke(d),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'revoke',
                      child: Text('Thu hồi thiết bị'),
                    ),
                  ],
                ),
              ],
            )
          else
            StatusHighlight.revoked(key: Key('status-${d.id}')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final e in {null: 'Tất cả', ...deviceStatusLabels}.entries)
              ChoiceChip(
                key: Key('device-filter-${e.key ?? 'all'}'),
                label: Text(e.value),
                selected: status == e.key,
                onSelected: (_) {
                  status = e.key;
                  reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('device-search'),
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Tìm nhân viên hoặc thiết bị',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: reload,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          onSubmitted: (_) => reload(),
        ),
        const SizedBox(height: 12),
        if (error != null)
          ErrorRetry(message: error!, onRetry: reload)
        else if (items.isEmpty && loading)
          const Center(child: CircularProgressIndicator())
        else if (items.isEmpty)
          const Center(
            key: Key('empty-devices'),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Chưa có thiết bị nào.'),
            ),
          )
        else ...[
          for (final d in items) tile(d),
          if (hasNext)
            OutlinedButton(
              key: const Key('devices-load-more'),
              onPressed: loading
                  ? null
                  : () async {
                      setState(() => loading = true);
                      await load(page + 1, generation);
                    },
              child: const Text('Tải thêm'),
            ),
        ],
      ],
    ),
  );
}
