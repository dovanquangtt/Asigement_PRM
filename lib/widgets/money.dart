/// Định dạng tiền VNĐ kiểu Việt Nam: 7657000 → "7.657.000đ"; số âm giữ dấu trừ.
String formatVnd(num? value) {
  final amount = (value ?? 0).round();
  final digits = amount.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return (amount < 0 ? '-' : '') + digits + 'đ';
}

/// "8g05" từ số phút làm việc.
String formatMinutes(num? minutes) {
  final m = (minutes ?? 0).round();
  return '${m ~/ 60} giờ ${(m % 60).toString().padLeft(2, '0')} phút';
}

/// "dd/MM/yyyy" từ chuỗi ngày yyyy-MM-dd.
String formatDay(Object? iso) {
  final d = DateTime.tryParse('$iso');
  if (d == null) return '$iso';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
