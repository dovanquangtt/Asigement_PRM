import 'package:flutter/material.dart';

import '../services/workforce_repository.dart';

/// Hộp thông báo đọc trực tiếp từ SQLite của tài khoản đang đăng nhập.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.repository});
  final WorkforceRepository repository;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<RowData>> loading;
  @override
  void initState() {
    super.initState();
    loading = widget.repository.notifications();
  }

  Future<void> refresh() async {
    final next = widget.repository.notifications();
    setState(() {
      loading = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thông báo'),
      actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<RowData>>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Không tải được thông báo. Vui lòng thử lại.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (rows.isEmpty)
                const ListTile(title: Text('Chưa có thông báo.')),
              for (final row in rows)
                ListTile(
                  leading: Icon(
                    row['read_at'] == null
                        ? Icons.mark_email_unread_outlined
                        : Icons.drafts_outlined,
                  ),
                  title: Text('${row['title']}'),
                  subtitle: Text('${row['body']}\n${row['created_at']}'),
                  isThreeLine: true,
                  onTap: () async {
                    await widget.repository.markNotificationRead(
                      row['id'] as int,
                    );
                    if (mounted) await refresh();
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}
