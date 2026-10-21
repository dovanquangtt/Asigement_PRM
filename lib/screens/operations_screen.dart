import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../services/attendance_sensors.dart';
import '../services/attendance_evidence.dart';
import '../widgets/common_widgets.dart';

/// Ảnh mẫu dùng asset URI để không phụ thuộc đường dẫn máy tạo database.
/// Ảnh camera thật vẫn được đọc từ thư mục riêng của app trên thiết bị.
Widget closurePhotoPreview(RowData photo) {
  final path = photo['file_url'].toString();
  final Widget preview;
  if (path.startsWith('asset:')) {
    preview = Image.asset(
      path.substring(6),
      height: 160,
      errorBuilder: (_, e, s) => const Text('Không đọc được ảnh minh họa.'),
    );
  } else if (File(path).existsSync()) {
    preview = Image.file(
      File(path),
      height: 160,
      errorBuilder: (_, e, s) => const Text('Không đọc được ảnh.'),
    );
  } else {
    preview = const Text('Ảnh không còn trên thiết bị.');
  }
  return Column(
    children: [
      preview,
      if (photo['caption'] != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${photo['caption']}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ],
  );
}

class InputSpec {
  const InputSpec(
    this.key,
    this.label, {
    this.value = '',
    this.options,
    this.optional = false,
    this.number = false,
  });
  final String key, label, value;
  final Map<String, String>? options;
  final bool optional, number;
}

Future<void> featureForm(
  BuildContext context,
  String title,
  List<InputSpec> fields,
  Future<void> Function(Map<String, String>) save,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _FeatureForm(title: title, fields: fields, save: save),
  );
}

/// Form dùng chung: validate trước khi lưu, chặn gửi lặp và giữ lỗi tại form.
class _FeatureForm extends StatefulWidget {
  const _FeatureForm({
    required this.title,
    required this.fields,
    required this.save,
  });
  final String title;
  final List<InputSpec> fields;
  final Future<void> Function(Map<String, String>) save;
  @override
  State<_FeatureForm> createState() => _FeatureFormState();
}

class _FeatureFormState extends State<_FeatureForm> {
  final form = GlobalKey<FormState>();
  late final values = {
    for (final f in widget.fields)
      f.key: TextEditingController(
        text: f.value.isNotEmpty ? f.value : f.options?.keys.firstOrNull ?? '',
      ),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in values.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(values.map((k, v) => MapEntry(k, v.text)));
      if (mounted) Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FormatException {
      if (mounted) {
        setState(() => error = 'Kiểm tra lại định dạng ngày giờ và số.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không lưu được. Kiểm tra dữ liệu trùng hoặc thiếu liên kết.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: f.options != null
                      ? DropdownButtonFormField<String>(
                          initialValue: values[f.key]!.text.isEmpty
                              ? null
                              : values[f.key]!.text,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: f.label),
                          items: [
                            for (final option in f.options!.entries)
                              DropdownMenuItem(
                                value: option.key,
                                child: Text(
                                  option.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => values[f.key]!.text = v ?? '',
                          validator: (v) => v == null || v.isEmpty
                              ? 'Chưa có lựa chọn hợp lệ'
                              : null,
                        )
                      : TextFormField(
                          controller: values[f.key],
                          enabled: !busy,
                          keyboardType: f.number
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : TextInputType.text,
                          decoration: InputDecoration(labelText: f.label),
                          validator: (v) =>
                              !f.optional && (v == null || v.trim().isEmpty)
                              ? 'Không được bỏ trống'
                              : null,
                        ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    ),
  );
}

String localTime(Object? value) {
  if (value == null) return 'Chưa có';
  final d = utcTime(value).add(const Duration(hours: 7));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

DateTime inputTime(String value) =>
    DateTime.parse('${value.trim().replaceFirst(' ', 'T')}+07:00').toUtc();
String tomorrow(int hour) {
  final d = DateTime.now().toUtc().add(const Duration(days: 1, hours: 7));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${hour.toString().padLeft(2, '0')}:00';
}

class OperationsPage extends StatefulWidget {
  const OperationsPage({
    super.key,
    required this.repository,
    required this.kind,
  });
  final WorkforceRepository repository;
  final String kind;
  @override
  State<OperationsPage> createState() => _OperationsPageState();
}

class _OperationsPageState extends State<OperationsPage> {
  WorkforceRepository get r => widget.repository;
  bool get manager => r.session.role != 'Nhân viên';
  late Future<List<RowData>> loading;
  static const titles = {
    'schedule': 'Quản lý ca & lịch ca',
    'attendance': 'Lịch sử điểm danh',
    'devices': 'Duyệt thiết bị',
    'payroll': 'Kỳ lương & 6 bước',
    'swaps': 'Yêu cầu đổi ca',
    'stars': 'Sao nhân viên',
    'closures': 'Báo cáo đóng ca',
    'branches': 'Cấu hình điểm danh',
  };
  @override
  void initState() {
    super.initState();
    loading = load();
  }

  Future<List<RowData>> load() => switch (widget.kind) {
    'schedule' => manager ? r.allShifts() : r.shifts(),
    'attendance' => r.attendanceHistory(),
    'devices' => r.devices(),
    'payroll' => r.periods(),
    'swaps' => r.swaps(),
    'stars' => r.stars(),
    'closures' => r.closures(),
    'branches' => r.branches(),
    _ => r.shifts(),
  };
  Future<void> refresh() async {
    final future = load();
    setState(() {
      loading = future;
    });
    try {
      await future;
    } catch (_) {}
  }

  Future<void> action(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) await refresh();
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thực hiện được thao tác.')),
        );
      }
    }
  }

  Widget button(String label, Future<void> Function() work) =>
      TextButton(onPressed: () => action(work), child: Text(label));
  Future<void> createShift() async {
    final branches = await r.branches();
    if (!mounted) return;
    await featureForm(
      context,
      'Tạo ca làm',
      [
        InputSpec(
          'branch',
          'Chi nhánh',
          options: {for (final b in branches) '${b['id']}': '${b['name']}'},
        ),
        InputSpec(
          'start',
          'Bắt đầu (YYYY-MM-DD HH:mm, giờ VN)',
          value: tomorrow(8),
        ),
        InputSpec(
          'end',
          'Kết thúc (YYYY-MM-DD HH:mm, giờ VN)',
          value: tomorrow(16),
        ),
        const InputSpec('count', 'Số nhân viên cần', value: '1', number: true),
        const InputSpec('note', 'Ghi chú', optional: true),
      ],
      (v) async {
        await r.createShift(
          branchId: int.parse(v['branch']!),
          start: inputTime(v['start']!),
          end: inputTime(v['end']!),
          requiredStaff: int.parse(v['count']!),
          note: v['note']!,
        );
      },
    );
    await refresh();
  }

  Future<void> createPeriod() async {
    if (!mounted) return;
    await featureForm(
      context,
      'Tạo kỳ lương',
      const [
        InputSpec('code', 'Mã kỳ lương'),
        InputSpec('start', 'Từ ngày YYYY-MM-DD'),
        InputSpec('end', 'Đến ngày YYYY-MM-DD'),
        InputSpec('multiplier', 'Hệ số trả lương tăng ca (>=1)', number: true),
      ],
      (v) async {
        await r.createPeriod(
          v['code']!,
          DateTime.parse('${v['start']}T00:00:00Z'),
          DateTime.parse('${v['end']}T00:00:00Z'),
          double.parse(v['multiplier']!),
        );
      },
    );
    await refresh();
  }

  Future<void> branchConfig(RowData b) async {
    AttendanceEvidence? evidence;
    try {
      evidence = await AttendanceSensors().collect();
    } catch (_) {
      /* Allow entering the known branch coordinates manually. */
    }
    if (!mounted) return;
    await featureForm(
      context,
      'GPS & Wi-Fi chi nhánh',
      [
        InputSpec(
          'lat',
          'Vĩ độ',
          value: '${evidence?.latitude ?? b['latitude'] ?? ''}',
          number: true,
        ),
        InputSpec(
          'lng',
          'Kinh độ',
          value: '${evidence?.longitude ?? b['longitude'] ?? ''}',
          number: true,
        ),
        InputSpec(
          'radius',
          'Bán kính mét',
          value: '${b['geofence_radius_m']}',
          number: true,
        ),
        InputSpec('ssid', 'Tên Wi-Fi (SSID)', value: evidence?.ssid ?? ''),
        InputSpec(
          'bssid',
          'BSSID (aa:bb:cc:dd:ee:ff)',
          value: evidence?.bssid ?? '',
        ),
      ],
      (v) => r.configureBranch(
        b['id'] as int,
        latitude: double.parse(v['lat']!),
        longitude: double.parse(v['lng']!),
        radius: int.parse(v['radius']!),
        ssid: v['ssid']!,
        bssid: v['bssid']!,
      ),
    );
    await refresh();
  }

  Future<void> award(RowData employee) async {
    await featureForm(
      context,
      'Tặng / trừ sao',
      const [
        InputSpec('delta', 'Số sao (+ hoặc -)', value: '1', number: true),
        InputSpec('reason', 'Lý do'),
      ],
      (v) => r.awardStars(
        employee['employee_id'] as int,
        int.parse(v['delta']!),
        v['reason']!,
      ),
    );
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          content: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: const Icon(Icons.star, size: 100, color: Colors.amber),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      await refresh();
    }
  }

  Widget tile(RowData row) {
    switch (widget.kind) {
      case 'schedule':
        return ListTile(
          title: Text(
            manager
                ? '${row['branch_name']} • ${row['assigned_count']}/${row['required_staff']} người'
                : '${row['branch_name']}',
          ),
          subtitle: Text(
            '${localTime(row['starts_at'])} — ${localTime(row['ends_at'])}\n${row['status']}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ShiftPage(
                repository: r,
                shiftId: (manager ? row['id'] : row['shift_id']) as int,
                assignmentId: manager ? null : row['assignment_id'] as int,
              ),
            ),
          ),
        );
      case 'attendance':
        return ListTile(
          title: Text(
            '${row['full_name']} • ${row['event_type'] == 'check_in' ? 'Vào ca' : 'Ra ca'}',
          ),
          subtitle: Text(
            '${localTime(row['occurred_at'])}\n${row['result']} ${row['rejection_reason'] ?? ''}',
          ),
        );
      case 'devices':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text('${row['full_name']} • ${row['platform']}'),
              subtitle: Text(
                row['revoked_at'] != null
                    ? 'Đã thu hồi'
                    : row['approved_by'] == null
                    ? 'Chờ duyệt'
                    : 'Đã duyệt',
              ),
            ),
            Wrap(
              children: [
                button('Duyệt', () => r.approveDevice(row['id'] as int)),
                button(
                  'Thu hồi',
                  () => r.approveDevice(row['id'] as int, revoke: true),
                ),
              ],
            ),
          ],
        );
      case 'payroll':
        return Column(
          children: [
            ListTile(
              title: Text('${row['code']} • ${row['status']}'),
              subtitle: Text(
                '${row['starts_on']} — ${row['ends_on']}\nHệ số tăng ca: ${row['overtime_multiplier'] ?? 'Chưa cấu hình'}',
              ),
            ),
            Wrap(
              children: [
                button(
                  manager
                      ? 'Tính lương toàn kỳ'
                      : 'Tính & kiểm tra lương của tôi',
                  () async {
                    final result = await r.calculatePay(row['id'] as int);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${result['message']}')),
                      );
                    }
                  },
                ),
                if (manager)
                  button(
                    'Duyệt kỳ lương',
                    () => r.approvePayroll(row['id'] as int),
                  ),
              ],
            ),
          ],
        );
      case 'swaps':
        return Column(
          children: [
            ListTile(
              title: Text('${row['from_name']} ↔ ${row['to_name']}'),
              subtitle: Text(
                '${localTime(row['from_start'])} ↔ ${localTime(row['to_start'])}\n${row['reason']}\nNgười nhận: ${row['counterpart_status']} • ${row['status']}',
              ),
            ),
            if (row['status'] == 'pending')
              Wrap(
                children: [
                  if (row['target_user_id'] == r.session.userId &&
                      row['counterpart_status'] == 'pending') ...[
                    button(
                      'Đồng ý',
                      () => r.respondSwap(row['id'] as int, true),
                    ),
                    button(
                      'Từ chối',
                      () => r.respondSwap(row['id'] as int, false),
                    ),
                  ],
                  if (manager) ...[
                    button(
                      'Duyệt đổi',
                      () => r.respondSwap(row['id'] as int, true, review: true),
                    ),
                    button(
                      'Không duyệt',
                      () =>
                          r.respondSwap(row['id'] as int, false, review: true),
                    ),
                  ],
                ],
              ),
          ],
        );
      case 'stars':
        return ListTile(
          leading: TweenAnimationBuilder<double>(
            key: ValueKey('${row['employee_id']}_${row['total_stars']}'),
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 600),
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: const Icon(Icons.star, color: Colors.amber),
          ),
          title: Text('${row['full_name']}'),
          subtitle: Text('${row['total_stars']} sao'),
          trailing: manager
              ? IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => action(() => award(row)),
                )
              : null,
        );
      case 'closures':
        return Column(
          children: [
            ListTile(
              title: Text('${row['full_name']} • ${row['status']}'),
              subtitle: Text(
                '${row['note']}\n${localTime(row['submitted_at'])}',
              ),
            ),
            for (final photo in row['photos'] as List<RowData>)
              closurePhotoPreview(photo),
            if (manager && row['status'] == 'submitted')
              Wrap(
                children: [
                  button(
                    'Duyệt',
                    () => r.reviewClosure(row['id'] as int, true),
                  ),
                  button(
                    'Từ chối',
                    () => r.reviewClosure(row['id'] as int, false),
                  ),
                ],
              ),
          ],
        );
      default:
        return ListTile(
          title: Text('${row['name']}'),
          subtitle: Text(
            'GPS: ${row['latitude'] ?? 'Chưa có'}, ${row['longitude'] ?? 'Chưa có'} • ${row['geofence_radius_m']} m',
          ),
          trailing: const Icon(Icons.settings),
          onTap: () => action(() => branchConfig(row)),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(titles[widget.kind] ?? 'Chức năng')),
    body: FutureBuilder<List<RowData>>(
      future: loading,
      builder: (context, s) {
        if (!s.hasData && !s.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
            child: Text(
              s.error is AuthException
                  ? (s.error as AuthException).message
                  : 'Không tải được dữ liệu.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (manager && widget.kind == 'schedule')
                FilledButton.icon(
                  onPressed: () => action(createShift),
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo ca làm'),
                ),
              if (manager && widget.kind == 'payroll')
                FilledButton.icon(
                  onPressed: () => action(createPeriod),
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo kỳ lương'),
                ),
              if (s.data!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Chưa có dữ liệu.'),
                ),
              for (final row in s.data!)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: panel(child: tile(row)),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class ShiftPage extends StatefulWidget {
  const ShiftPage({
    super.key,
    required this.repository,
    required this.shiftId,
    this.assignmentId,
  });
  final WorkforceRepository repository;
  final int shiftId;
  final int? assignmentId;
  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  late Future<RowData> loading;
  WorkforceRepository get r => widget.repository;
  @override
  void initState() {
    super.initState();
    loading = r.shiftDetail(widget.shiftId);
  }

  Future<void> perform(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) {
        setState(() {
          loading = r.shiftDetail(widget.shiftId);
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không thực hiện được.')));
      }
    }
  }

  Future<void> assign() async {
    final people = await r.employees();
    if (!mounted) return;
    await featureForm(context, 'Phân ca', [
      InputSpec(
        'employee',
        'Nhân viên',
        options: {
          for (final e in people)
            '${e['id']}': '${e['employee_code']} • ${e['full_name']}',
        },
      ),
    ], (v) => r.assignShift(widget.shiftId, int.parse(v['employee']!)));
  }

  Future<void> swap(int own) async {
    final options = await r.swapOptions(own);
    if (!mounted) return;
    await featureForm(context, 'Gửi yêu cầu đổi ca', [
      InputSpec(
        'target',
        'Ca muốn đổi',
        options: {
          for (final a in options)
            '${a['id']}': '${a['full_name']} • ${localTime(a['starts_at'])}',
        },
      ),
      const InputSpec('reason', 'Lý do'),
    ], (v) => r.requestSwap(own, int.parse(v['target']!), v['reason']!));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết ca làm')),
    body: FutureBuilder<RowData>(
      future: loading,
      builder: (context, s) {
        if (!s.hasData && !s.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
            child: Text(
              s.error is AuthException
                  ? (s.error as AuthException).message
                  : 'Không tải được ca.',
            ),
          );
        }
        final row = s.data!;
        final roster = row['roster'] as List<RowData>;
        final own =
            widget.assignmentId ??
            roster
                    .where((a) => a['user_id'] == r.session.userId)
                    .firstOrNull?['id']
                as int?;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            heading('${row['branch_name']}', 'CA #${row['id']}'),
            Text(
              '${localTime(row['starts_at'])} — ${localTime(row['ends_at'])} (giờ VN)',
            ),
            Text(
              'Trạng thái: ${row['status']}\nSố người cần: ${row['required_staff']}\n${row['note'] ?? ''}',
            ),
            if (r.session.role != 'Nhân viên')
              FilledButton(
                onPressed: () => perform(assign),
                child: const Text('Phân nhân viên vào ca'),
              ),
            section('Nhân viên trong ca'),
            for (final a in roster)
              ListTile(
                title: Text('${a['full_name']}'),
                subtitle: Text('${a['employee_code']} • ${a['status']}'),
              ),
            if (own != null) ...[
              section('Thao tác ca của bạn'),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AttendancePage(repository: r, assignmentId: own),
                  ),
                ),
                icon: const Icon(Icons.fingerprint),
                label: const Text('Kiểm tra & điểm danh'),
              ),
              OutlinedButton(
                onPressed: () => perform(() => swap(own)),
                child: const Text('Yêu cầu đổi ca'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ClosurePage(repository: r, assignmentId: own),
                  ),
                ),
                child: const Text('Chụp ảnh & đóng ca'),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.repository,
    required this.assignmentId,
  });
  final WorkforceRepository repository;
  final int assignmentId;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  AttendanceEvidence? evidence;
  bool busy = false;
  String message = 'Kiểm tra thiết bị, GPS và Wi-Fi trước khi xác nhận.';
  String type = 'check_in';
  Future<void> work(Future<void> Function() run) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await run();
    } on AuthException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Không đọc được thiết bị/GPS/Wi-Fi. Kiểm tra quyền và kết nối.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> inspect() async {
    final e = await AttendanceSensors().collect();
    final c = await widget.repository.attendanceContext(widget.assignmentId);
    if (mounted) {
      setState(() {
        evidence = e;
        message =
            'Thiết bị: ${e.platform}\nGPS: ${e.latitude}, ${e.longitude} (±${e.accuracy?.round()} m)\nWi-Fi: ${e.ssid ?? 'Không đọc được'}\nBSSID: ${e.bssid ?? 'Không đọc được'}\nChi nhánh: ${c['latitude'] ?? 'Chưa cấu hình'}, ${c['longitude'] ?? 'Chưa cấu hình'} • ${c['geofence_radius_m']} m\n${e.mocked ? 'Cảnh báo: vị trí giả' : ''}';
      });
    }
  }

  Future<void> confirm() async {
    // Chỉ gửi sau khi người dùng xác nhận; repository tự quyết định accepted/rejected.
    if (evidence == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xác nhận điểm danh?'),
        content: Text(
          type == 'check_in'
              ? 'Ghi nhận vào ca bằng kết quả kiểm tra vừa thu thập.'
              : 'Ghi nhận ra ca bằng kết quả kiểm tra vừa thu thập.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await widget.repository.recordAttendance(
      widget.assignmentId,
      type,
      evidence!,
    );
    if (mounted) {
      setState(
        () => message =
            '${result['accepted'] == true ? '✓' : '✗'} ${result['message']}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Điểm danh')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Thiết bị cần được Quản lý/Admin duyệt. GPS và Wi-Fi phải khớp cấu hình chi nhánh.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: type,
          items: const [
            DropdownMenuItem(value: 'check_in', child: Text('Vào ca')),
            DropdownMenuItem(value: 'check_out', child: Text('Ra ca')),
          ],
          onChanged: busy ? null : (v) => setState(() => type = v!),
        ),
        const SizedBox(height: 16),
        panel(child: Text(message)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => work(() async {
                  final e = await AttendanceSensors().collect(location: false);
                  await widget.repository.registerDevice(e);
                  if (mounted) {
                    setState(
                      () => message = 'Đã đăng ký thiết bị. Nhờ Quản lý/Admin duyệt trước khi điểm danh.',
                    );
                  }
                }),
          child: const Text('Đăng ký thiết bị này'),
        ),
        FilledButton(
          onPressed: busy ? null : () => work(inspect),
          child: const Text('Kiểm tra GPS & Wi-Fi'),
        ),
        FilledButton(
          onPressed: busy || evidence == null ? null : () => work(confirm),
          child: const Text('Xác nhận điểm danh'),
        ),
        if (busy) const LinearProgressIndicator(),
      ],
    ),
  );
}

class ClosurePage extends StatefulWidget {
  const ClosurePage({
    super.key,
    required this.repository,
    required this.assignmentId,
  });
  final WorkforceRepository repository;
  final int assignmentId;
  @override
  State<ClosurePage> createState() => _ClosurePageState();
}

class _ClosurePageState extends State<ClosurePage> {
  final note = TextEditingController();
  String? photo;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    recover();
  }

  Future<void> keep(XFile f) async {
    final directory = await getApplicationSupportDirectory();
    final folder = Directory(p.join(directory.path, 'closure_photos'));
    await folder.create(recursive: true);
    final destination = p.join(
      folder.path,
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await f.saveTo(destination);
    if (mounted) setState(() => photo = destination);
  }

  Future<void> recover() async {
    try {
      final result = await ImagePicker().retrieveLostData();
      if (result.files?.isNotEmpty == true) await keep(result.files!.first);
    } catch (_) {}
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> capture() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (f != null) await keep(f);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không mở được camera. Kiểm tra quyền camera trên điện thoại.',
        );
      }
    }
  }

  Future<void> submit() async {
    if (photo == null) {
      setState(() => error = 'Cần chụp ảnh đóng ca.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repository.closeAssignment(
        widget.assignmentId,
        note.text,
        photo!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu ảnh và gửi báo cáo đóng ca.')),
        );
        Navigator.pop(context);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Không gửi được báo cáo.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ảnh & ghi chú đóng ca')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (photo != null) Image.file(File(photo!), height: 240),
        OutlinedButton.icon(
          onPressed: busy ? null : capture,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Chụp ảnh'),
        ),
        TextField(
          controller: note,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Ghi chú bàn giao / đóng ca',
          ),
        ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Đang gửi…' : 'Gửi báo cáo đóng ca'),
        ),
      ],
    ),
  );
}

class PayDetailPage extends StatefulWidget {
  const PayDetailPage({super.key, required this.repository, required this.id});
  final WorkforceRepository repository;
  final int id;
  @override
  State<PayDetailPage> createState() => _PayDetailPageState();
}

class _PayDetailPageState extends State<PayDetailPage> {
  late Future<RowData> loading;
  @override
  void initState() {
    super.initState();
    loading = widget.repository.payslipDetail(widget.id);
  }

  Future<void> add() async {
    await featureForm(
      context,
      'Khoản cộng/trừ',
      const [
        InputSpec('code', 'Mã khoản'),
        InputSpec('name', 'Tên khoản'),
        InputSpec(
          'type',
          'Loại',
          options: {
            'allowance': 'Phụ cấp',
            'bonus': 'Thưởng',
            'deduction': 'Khấu trừ',
            'tax': 'Thuế',
            'insurance': 'Bảo hiểm',
          },
        ),
        InputSpec('amount', 'Số tiền VND', number: true),
      ],
      (v) => widget.repository.addPayItem(
        widget.id,
        v['code']!,
        v['name']!,
        v['type']!,
        int.parse(v['amount']!),
      ),
    );
    if (mounted) {
      setState(() {
        loading = widget.repository.payslipDetail(widget.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết phiếu lương')),
    body: FutureBuilder<RowData>(
      future: loading,
      builder: (c, s) {
        if (!s.hasData && !s.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return const Center(child: Text('Không tải được phiếu lương.'));
        }
        final pay = s.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            heading(
              '${pay['full_name']}',
              'PHIẾU #${pay['id']} • ${pay['status']}',
            ),
            money('Công thường', '${pay['regular_minutes']} phút'),
            money('Công tăng ca', '${pay['overtime_minutes']} phút'),
            money('Lương thường', '${pay['base_pay_vnd']} VND'),
            money('Lương tăng ca', '${pay['overtime_pay_vnd']} VND'),
            for (final item in pay['items'] as List<RowData>)
              money(
                '${item['name']} (${item['item_type']})',
                '${item['amount_vnd']} VND',
              ),
            money('Thực lĩnh', '${pay['net_pay_vnd']} VND', bold: true),
            if (widget.repository.session.role != 'Nhân viên' &&
                pay['status'] == 'draft')
              OutlinedButton(
                onPressed: add,
                child: const Text('Thêm khoản cộng/trừ'),
              ),
            section('Kiểm tra 6 bước tính lương'),
            if ((pay['checks'] as List).length != 6)
              const Text(
                'Chưa đủ 6 bước hoặc đã sửa khoản điều chỉnh. Hãy tính lại lương.',
              ),
            for (final check in pay['checks'] as List<RowData>)
              ListTile(
                leading: CircleAvatar(child: Text('${check['step_number']}')),
                title: Text('${check['name']}'),
                subtitle: Text('${check['detail']}'),
              ),
          ],
        );
      },
    ),
  );
}
