import 'package:flutter/material.dart';

import '../../core/errors/api_exception.dart';
import '../../core/network/api_client.dart';

/// Thông báo của tài khoản (GET /api/notifications, POST /api/notifications/{id}/read).
class NotificationsApiScreen extends StatefulWidget {
  const NotificationsApiScreen({super.key, this.client});
  final ApiClient? client;
  @override
  State<NotificationsApiScreen> createState() => _NotificationsApiScreenState();
}

class _NotificationsApiScreenState extends State<NotificationsApiScreen> {
  late Future<List<Map<String, dynamic>>> loading = _load();

  ApiClient get _client => widget.client ?? ApiClient.instance;

  Future<List<Map<String, dynamic>>> _load() async =>
      (await _client.getList('/api/notifications')).cast<Map<String, dynamic>>();

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      loading = next;
    });
    await next.then((_) {}, onError: (_) {});
  }

  Future<void> _read(Map<String, dynamic> row) async {
    if (row['read_at'] != null) return;
    try {
      await _client.post('/api/notifications/${row['id']}/read');
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thông báo'),
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
                e is ApiException ? e.message : 'Không tải được thông báo. Thử lại.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: rows.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Chưa có thông báo.')),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final unread = r['read_at'] == null;
                    return ListTile(
                      leading: Icon(
                        unread
                            ? Icons.mark_email_unread_outlined
                            : Icons.drafts_outlined,
                      ),
                      title: Text(
                        '${r['title']}',
                        style: TextStyle(
                          fontWeight: unread ? FontWeight.w800 : FontWeight.w400,
                        ),
                      ),
                      subtitle: Text('${r['body']}'),
                      onTap: () => _read(r),
                    );
                  },
                ),
        );
      },
    ),
  );
}
