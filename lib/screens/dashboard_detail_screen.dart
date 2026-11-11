import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../theme/app_colors.dart';

/// Chi tiết của một thẻ thống kê: liệt kê từng bản ghi tạo nên con số, có ô tìm kiếm.
class DashboardDetailScreen extends StatefulWidget {
  const DashboardDetailScreen({
    super.key,
    required this.repository,
    required this.kind,
    required this.title,
    required this.from,
    required this.to,
  });
  final WorkforceRepository repository;
  final String kind;
  final String title;
  final DateTime from;
  final DateTime to;

  @override
  State<DashboardDetailScreen> createState() => _DashboardDetailScreenState();
}

class _DashboardDetailScreenState extends State<DashboardDetailScreen> {
  late final Future<List<RowData>> loading = widget.repository.dashboardDetail(
    widget.kind,
    from: widget.from,
    to: widget.to,
  );
  String query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<List<RowData>>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final e = snapshot.error;
          return Center(
            child: Text(
              e is AuthException ? e.message : 'Không tải được danh sách.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final q = query.trim().toLowerCase();
        final rows = q.isEmpty
            ? all
            : all
                  .where(
                    (r) => '${r['title']} ${r['subtitle']} ${r['badge']}'
                        .toLowerCase()
                        .contains(q),
                  )
                  .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('detail-search'),
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Tìm theo tên, trạng thái…',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  q.isEmpty
                      ? 'Tổng cộng ${all.length} mục'
                      : '${rows.length}/${all.length} mục',
                  key: const Key('detail-count'),
                  style: const TextStyle(color: muted),
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Không có dữ liệu.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final ok = r['ok'] == true;
                        final color = ok
                            ? const Color(0xFF1B7F4B)
                            : const Color(0xFFB45309);
                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFD5E7E4)),
                          ),
                          child: ListTile(
                            title: Text(
                              '${r['title']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text('${r['subtitle']}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${r['badge']}',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
