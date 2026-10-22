import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../services/workforce_repository.dart';
import '../services/attendance_sensors.dart';
import '../services/attendance_evidence.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import 'attendance_management_screen.dart';

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
  final d = utcTime(value).toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

DateTime inputTime(String value) =>
    DateTime.parse(value.trim().replaceFirst(' ', 'T')).toUtc();
String tomorrow(int hour) {
  final d = DateTime.now().add(const Duration(days: 1));
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
    'attendance_review': 'Duyệt điểm danh',
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
    'attendance_review' => r.attendanceSubmissions(),
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
  Future<void> reviewAttendance(RowData row, bool approve) async {
    await featureForm(
      context,
      approve ? 'Duyệt điểm danh #${row['id']}' : 'Từ chối #${row['id']}',
      const [InputSpec('note', 'Nhận xét / lý do kiểm tra')],
      (values) =>
          r.reviewAttendance(row['id'] as int, approve, note: values['note']!),
    );
    if (mounted) await refresh();
  }

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
        if (r.session.role == 'Admin')
          InputSpec(
            'overtime',
            'Tăng ca cần duyệt?',
            value: '${b['require_overtime_approval'] ?? 0}',
            options: const {
              '0': 'Không, tự ghi nhận',
              '1': 'Có, chờ xác nhận tăng ca',
            },
          ),
      ],
      (v) => r.configureBranch(
        b['id'] as int,
        latitude: double.parse(v['lat']!),
        longitude: double.parse(v['lng']!),
        radius: int.parse(v['radius']!),
        ssid: v['ssid']!,
        bssid: v['bssid']!,
        requireOvertimeApproval: v['overtime'] == null
            ? null
            : v['overtime'] == '1',
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
      case 'attendance_review':
        final snapshot = jsonDecode(
          row['checks_snapshot'] as String,
        ) as Map<String, dynamic>;
        final warnings = (snapshot['warnings'] as List).cast<String>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '#${row['id']} • ${row['full_name']} • ${row['event_type'] == 'check_in' ? 'Vào ca' : 'Ra ca'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${row['branch_name']}\nGửi: ${localTime(row['occurred_at'])}\nCa: ${localTime(row['starts_at'])} – ${localTime(row['ends_at'])}',
            ),
            Text(
              'Trạng thái: ${row['result'] == 'pending_review'
                  ? 'Chờ Admin duyệt'
                  : row['result'] == 'accepted'
                  ? 'Đã duyệt'
                  : 'Đã từ chối'}',
            ),
            const Divider(),
            SelectableText(
              'Thiết bị được chọn: ${row['selected_device_identifier']}\nThiết bị thực tế: ${row['actual_device_identifier']}\nNền tảng: ${row['device_platform']}',
            ),
            Text(
              'GPS: ${row['latitude'] ?? 'Không có'}, ${row['longitude'] ?? 'Không có'} • ±${row['gps_accuracy_m'] ?? '?'} m\nKhoảng cách lúc gửi: ${snapshot['distance_m'] ?? '?'} m / bán kính ${snapshot['radius_m']} m\nVị trí giả: ${row['evidence_mocked'] == 1 ? 'Có' : 'Không phát hiện'}\nWi-Fi: ${row['wifi_ssid'] ?? 'Không đọc được'}\nBSSID: ${row['wifi_bssid'] ?? 'Không đọc được'}',
            ),
            for (final warning in warnings)
              Text(
                '⚠ $warning',
                style: const TextStyle(color: Colors.deepOrange),
              ),
            if (warnings.isEmpty)
              const Text('Các điều kiện tự động đều đạt tại lúc gửi.'),
            if (row['reviewed_at'] != null)
              Text(
                'Nhận xét: ${row['review_note']}\nDuyệt lúc: ${localTime(row['reviewed_at'])}',
              ),
            if (row['result'] == 'pending_review')
              Wrap(
                children: [
                  button('Duyệt ghi công', () => reviewAttendance(row, true)),
                  button('Từ chối', () => reviewAttendance(row, false)),
                ],
              ),
          ],
        );
      case 'attendance':
        return ListTile(
          title: Text(
            '${row['full_name']} • ${row['event_type'] == 'check_in' ? 'Vào ca' : 'Ra ca'}',
          ),
          subtitle: Text(
            '${localTime(row['occurred_at'])}\n${row['result'] == 'pending_review'
                ? 'Chờ Admin duyệt'
                : row['result'] == 'accepted'
                ? 'Đã ghi công'
                : 'Bị từ chối'} ${row['review_note'] ?? row['rejection_reason'] ?? ''}',
          ),
        );
      case 'devices':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(
                '#${row['id']} • ${row['full_name']} • ${row['platform']}',
              ),
              subtitle: Text(
                row['revoked_at'] != null
                    ? 'Đã thu hồi'
                    : row['approved_by'] == null
                    ? 'Chờ duyệt • Mã thiết bị: ${row['device_identifier']}'
                    : 'Đã duyệt • Mã thiết bị: ${row['device_identifier']}',
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
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có ca phù hợp để đổi lúc này.')),
      );
      return;
    }
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

  String _shiftTitle(DateTime start) {
    final hour = start.hour;
    if (hour < 12) return 'Ca sáng';
    if (hour < 17) return 'Ca chiều';
    return 'Ca tối';
  }

  IconData _shiftIcon(DateTime start) {
    final hour = start.hour;
    if (hour < 12) return Icons.wb_sunny_rounded;
    if (hour < 17) return Icons.wb_twilight_rounded;
    return Icons.bedtime_rounded;
  }

  List<Color> _headerGradient(DateTime start) {
    final hour = start.hour;
    if (hour < 12) {
      return const [Color(0xFFD35400), Color(0xFFF39C12)];
    }
    if (hour < 17) {
      return const [Color(0xFFC0392B), Color(0xFFE67E22)];
    }
    return const [Color(0xFF1A252F), Color(0xFF34495E)];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chi tiết ca làm'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            setState(() {
              loading = r.shiftDetail(widget.shiftId);
            });
          },
        ),
      ],
    ),
    body: FutureBuilder<RowData>(
      future: loading,
      builder: (context, s) {
        if (!s.hasData && !s.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (s.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.error is AuthException
                        ? (s.error as AuthException).message
                        : 'Không tải được thông tin ca làm.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        loading = r.shiftDetail(widget.shiftId);
                      });
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
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

        final startVn = utcTime(row['starts_at']).toLocal();
        final endVn = utcTime(row['ends_at']).toLocal();
        final durationMins = endVn.difference(startVn).inMinutes;
        final durationHoursStr = (durationMins / 60).toStringAsFixed(
          durationMins % 60 == 0 ? 0 : 1,
        );

        final title = _shiftTitle(startVn);
        final icon = _shiftIcon(startVn);
        final gradientColors = _headerGradient(startVn);

        final nowUtc = DateTime.now().toUtc();
        final isPast = utcTime(row['ends_at']).isBefore(nowUtc);
        final isInProgress =
            utcTime(row['starts_at']).isBefore(nowUtc) && !isPast;
        final requiredStaff = (row['required_staff'] as int?) ?? 1;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              loading = r.shiftDetail(widget.shiftId);
            });
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              // 1. Thẻ Header Hero hiển thị khung giờ & trạng thái
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.first.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$title • CA #${row['id']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isInProgress
                                  ? '🟢 Đang diễn ra'
                                  : isPast || row['status'] == 'completed'
                                  ? '⚪ Hoàn thành'
                                  : '🔵 Sắp tới',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${startVn.hour.toString().padLeft(2, '0')}:${startVn.minute.toString().padLeft(2, '0')} — ${endVn.hour.toString().padLeft(2, '0')}:${endVn.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Thứ ${startVn.weekday == 7 ? 'Chủ nhật' : startVn.weekday + 1}, ngày ${startVn.day.toString().padLeft(2, '0')}/${startVn.month.toString().padLeft(2, '0')}/${startVn.year} • $durationHoursStr tiếng',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Thông tin Địa điểm & Ghi chú phân công
              section('Địa điểm & Vị trí làm việc'),
              panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5EA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: green,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        '${row['branch_name']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        row['latitude'] != null
                            ? 'Tọa độ: ${row['latitude']}, ${row['longitude']} • Bán kính check-in: ${row['geofence_radius_m']}m'
                            : 'Địa điểm chi nhánh chính',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (row['note'] != null &&
                        row['note'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.assignment_outlined,
                              size: 18,
                              color: muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Phân công / Ghi chú: ${row['note']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Danh sách nhân viên trong ca
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nhân viên trong ca (${roster.length}/$requiredStaff)',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (r.session.role != 'Nhân viên')
                    TextButton.icon(
                      onPressed: () => perform(assign),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 18,
                      ),
                      label: const Text('Phân ca'),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (roster.isEmpty)
                panel(
                  child: const Text(
                    'Chưa có nhân viên nào được phân công vào ca này.',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else
                for (final a in roster) ...[
                  Builder(
                    builder: (_) {
                      final isMe = a['user_id'] == r.session.userId;
                      final name = a['full_name']?.toString() ?? 'Nhân viên';
                      final code = a['employee_code']?.toString() ?? '';
                      final lastEvt = a['last_event']?.toString();
                      final initial = name.isNotEmpty
                          ? name[0].toUpperCase()
                          : 'N';

                      return panel(
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isMe
                                  ? green
                                  : const Color(0xFFE8EDE7),
                              foregroundColor: isMe ? Colors.white : ink,
                              radius: 20,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        pill('Bạn'),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mã: $code • Trạng thái: ${a['status']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  if (lastEvt != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      lastEvt == 'check_in'
                                          ? '✓ Đã điểm danh vào ca'
                                          : '✓ Đã điểm danh ra ca',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],

              // 4. Các nút thao tác dành riêng cho nhân viên
              if (own != null) ...[
                section('Thao tác ca làm của bạn'),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AttendancePage(
                              repository: r,
                              assignmentId: own,
                            ),
                          ),
                        ).then((_) {
                          setState(() {
                            loading = r.shiftDetail(widget.shiftId);
                          });
                        }),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Kiểm tra thiết bị & Điểm danh'),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => perform(() => swap(own)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Yêu cầu đổi ca'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ClosurePage(
                                  repository: r,
                                  assignmentId: own,
                                ),
                              ),
                            ).then((_) {
                              setState(() {
                                loading = r.shiftDetail(widget.shiftId);
                              });
                            }),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Báo cáo đóng ca'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
    this.sensors,
  });
  final WorkforceRepository repository;
  final int assignmentId;
  final AttendanceSensors? sensors;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late final AttendanceSensors sensors = widget.sensors ?? AttendanceSensors();
  final Map<String, bool> results = {};
  final Map<String, String> details = {};
  bool busy = false;
  String type = 'check_in';
  String message =
      'Chọn thiết bị và gửi yêu cầu. Các kiểm tra bên dưới là thông tin tham khảo cho Admin.';
  int selectedDevice = 0;
  bool sent = false;
  List<RowData> devices = [];

  @override
  void initState() {
    super.initState();
    loadDevices();
  }

  Future<void> loadDevices() async {
    try {
      final rows = await widget.repository.myAttendanceDevices();
      if (mounted) setState(() => devices = rows);
    } on AuthException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Không tải được danh sách thiết bị. Có thể chọn thiết bị đang sử dụng.',
        );
      }
    }
  }

  bool get ready =>
      ['device', 'gps', 'wifi'].every((key) => results[key] == true);

  Future<void> work(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Không đọc được cảm biến. Kiểm tra quyền vị trí, bật GPS và kết nối Wi-Fi rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> inspect(String step) async {
    setState(() {
      results.remove(step);
      details.remove(step);
    });
    final c = await widget.repository.attendanceContext(widget.assignmentId);
    final required =
        c[step == 'device' ? 'require_registered_device' : 'require_$step'] ==
        1;
    final e = await sensors.collect(
      location: required && step != 'device',
      gps: step == 'gps',
      wifi: step == 'wifi',
    );
    final check = await widget.repository.inspectAttendance(
      widget.assignmentId,
      e,
    );
    if (!mounted) return;
    setState(() {
      results[step] = check['${step}_ok'] == true;
      details[step] = !required
          ? 'Chi nhánh không bắt buộc điều kiện này.'
          : switch (step) {
              'device' =>
                check['device_valid'] == true
                    ? 'Thiết bị đã được duyệt cho tài khoản của bạn.'
                    : switch (check['device_status']) {
                        'pending' =>
                          'Thiết bị #${check['registration_id']} đang chờ duyệt. Đăng nhập Quản lý/Admin trên cùng máy → Trang chủ → Duyệt thiết bị nhân viên → duyệt #${check['registration_id']}. Sau đó quay lại kiểm tra.',
                        'revoked' =>
                          'Thiết bị #${check['registration_id']} đã bị thu hồi. Liên hệ Quản lý/Admin để kiểm tra và duyệt lại.',
                        'another_employee' => 'Thiết bị này thuộc tài khoản nhân viên khác. Không thể đăng ký dùng chung để điểm danh.',
                        _ => 'Thiết bị chưa đăng ký. Bấm “Đăng ký thiết bị này”, rồi nhờ Quản lý/Admin duyệt trên cùng database.',
                      },
              'gps' =>
                '${check['gps_valid'] == true ? 'Trong phạm vi' : 'GPS chưa hợp lệ'}'
                    '\nKhoảng cách: ${check['distance_m'] == null ? 'chưa xác định' : '${(check['distance_m'] as num).round()} m'}'
                    ' • Bán kính: ${check['radius_m']} m'
                    '\nĐộ chính xác: ${e.accuracy == null ? 'chưa xác định' : '±${e.accuracy!.round()} m'}'
                    '${e.mocked ? '\nPhát hiện vị trí giả.' : ''}',
              _ =>
                '${e.ssid ?? 'Không đọc được tên Wi-Fi'}'
                    '\nBSSID: ${e.bssid ?? 'chưa xác định'}'
                    '\n${check['wifi_valid'] == true ? 'Khớp Wi-Fi chi nhánh.' : 'Wi-Fi không khớp cấu hình chi nhánh.'}',
            };
      message = ready
          ? 'Các bước kiểm tra đã đạt. Bạn có thể xác nhận.'
          : 'Có cảnh báo. Bạn vẫn có thể gửi để Admin kiểm tra và quyết định.';
    });
  }

  Future<void> register() async {
    final e = await sensors.collect(location: false);
    await widget.repository.registerDevice(e);
    await loadDevices();
    if (!mounted) return;
    setState(() {
      results.clear();
      details.clear();
      message = 'Đã đăng ký thiết bị. Bạn có thể chọn thiết bị này và gửi điểm danh cho Admin kiểm tra.';
    });
  }

  Future<void> confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          type == 'check_in' ? 'Gửi yêu cầu vào ca?' : 'Gửi yêu cầu ra ca?',
        ),
        content: const Text(
          'Ứng dụng đọc lại thiết bị, GPS và Wi-Fi. Nếu hợp lệ sẽ tự ghi nhận giờ thực tế; nếu bất thường sẽ chuyển quản lý chi nhánh hoặc Admin xử lý. Đi muộn chỉ được đánh dấu, không tự trừ lương.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final configuration = await widget.repository.attendanceContext(
      widget.assignmentId,
    );
    final sample = await sensors.collectForReview(
      requireGps: configuration['require_gps'] == 1,
      requireWifi: configuration['require_wifi'] == 1,
    );
    final id = await widget.repository.submitAttendance(
      widget.assignmentId,
      type,
      sample.evidence,
      selectedDeviceId: selectedDevice == 0 ? null : selectedDevice,
      collectionIssues: sample.issues,
    );
    if (!mounted) return;
    final detail = await widget.repository.attendanceCaseDetail(
      widget.assignmentId,
    );
    final event = (detail['events'] as List<RowData>).firstWhere(
      (e) => e['id'] == id,
    );
    if (!mounted) return;
    setState(() {
      sent = true;
      message = event['result'] == 'accepted'
          ? 'Đã tự ghi nhận ${type == 'check_in' ? 'vào ca' : 'ra ca'} #$id.${(detail['record'] as RowData?)?['arrival_status'] == 'LATE' ? ' Có đi muộn, không cần duyệt riêng.' : ''} Xem Công của tôi để biết giờ và trạng thái tăng ca.'
          : 'Yêu cầu #$id có dữ liệu bất thường, đã chuyển người có quyền xử lý. Chưa ghi công.';
    });
  }

  Widget step(String key, String title, IconData icon) {
    final passed = results[key];
    final color = passed == null
        ? Colors.blueGrey
        : passed
        ? green
        : Colors.red.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  passed == null
                      ? Icons.radio_button_unchecked
                      : passed
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              details[key] ??
                  (passed == null ? 'Chưa kiểm tra' : 'Đã kiểm tra'),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy ? null : () => work(() => inspect(key)),
              child: Text(passed == null ? title : 'Kiểm tra lại'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Điểm danh')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        heading('Điểm danh ca làm', 'THIẾT BỊ · GPS · WI-FI'),
        const Text(
          'Thiết bị, GPS và Wi-Fi hợp lệ sẽ tự ghi nhận công. Chỉ dữ liệu bất thường cần người quản lý kiểm tra. Đi muộn không cần duyệt riêng.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey(type),
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Loại điểm danh'),
          items: const [
            DropdownMenuItem(value: 'check_in', child: Text('Vào ca')),
            DropdownMenuItem(value: 'check_out', child: Text('Ra ca')),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() {
                  type = value!;
                  sent = false;
                  results.clear();
                  details.clear();
                }),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          initialValue: selectedDevice,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Thiết bị muốn điểm danh',
          ),
          items: [
            const DropdownMenuItem(
              value: 0,
              child: Text('Thiết bị đang sử dụng'),
            ),
            for (final device in devices)
              DropdownMenuItem(
                value: device['id'] as int,
                child: Text(
                  '#${device['id']} • ${device['platform']} • ${device['approved_by'] == null ? 'Chờ duyệt' : 'Đã duyệt'}',
                ),
              ),
          ],
          onChanged: busy || sent
              ? null
              : (value) => setState(() => selectedDevice = value!),
        ),
        const SizedBox(height: 16),
        step('device', 'Kiểm tra thiết bị', Icons.phonelink_lock_outlined),
        OutlinedButton.icon(
          onPressed: busy ? null : () => work(register),
          icon: const Icon(Icons.app_registration),
          label: const Text('Đăng ký thiết bị này'),
        ),
        const SizedBox(height: 12),
        step('gps', 'Kiểm tra GPS', Icons.location_on_outlined),
        step('wifi', 'Kiểm tra Wi-Fi', Icons.wifi),
        Semantics(liveRegion: true, child: panel(child: Text(message))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy || sent ? null : () => work(confirm),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Xác nhận điểm danh'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AttendanceCaseScreen(
                      repository: widget.repository,
                      assignmentId: widget.assignmentId,
                    ),
                  ),
                ),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Xem công / yêu cầu sửa giờ'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => OperationsPage(
                      repository: widget.repository,
                      kind: 'attendance',
                    ),
                  ),
                ),
          child: const Text('Xem lịch sử điểm danh'),
        ),
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
