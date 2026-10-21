# Mã ứng dụng mobile

Luồng chạy hiện tại: main.dart → PrmApp → DatabaseStartup → LoginPage → Workspace.

- `services/local_database.dart`: sao chép và mở SQLite trên thiết bị.
- `services/sample_data.dart`: dữ liệu tài khoản/hồ sơ mẫu.
- `services/auth_service.dart`: kiểm tra users.password_hash bằng bcrypt, đọc vai trò và quyền từ database.
- `services/workforce_repository.dart`: truy vấn dữ liệu theo quyền hiện tại; chỉ cho Nhân viên đọc lịch ca/phiếu lương của mình; lưu tài khoản và hồ sơ mới trong transaction.
- `screens/login_screen.dart`: đăng nhập, không cho tự chọn vai trò.
- `screens/workspace_screen.dart`: điều hướng và giao diện riêng theo vai trò, danh sách dữ liệu thật, form tạo tài khoản/thêm nhân viên, đăng xuất.
- `theme/`, `widgets/`: giao diện dùng chung.

Các file home_screen.dart, schedule_screen.dart, payroll_screen.dart, profile_screen.dart, workspace_controller.dart và workspace_actions.dart là giao diện demo cũ, không được Workspace hiện tại gọi tới. Các màn hình đang hoạt động dùng WorkforceRepository để đọc/ghi SQLite.

Xem README.md ở gốc dự án để biết cách chạy, tài khoản mẫu và phạm vi chức năng hiện có.

- `screens/operations_screen.dart`: các màn hình M01–M07, chi tiết ca, xác nhận điểm danh, camera/đóng ca, chi tiết phiếu lương và 6 bước.
- `services/workforce_operations.dart`: part của repository, transaction và kiểm tra quyền cho lịch/ca, thiết bị/chấm công, tính/duyệt lương, đổi ca, sao và đóng ca.
- `services/attendance_sensors.dart`: thu thập thiết bị, GPS, SSID/BSSID từ plugin thật trên điện thoại.
- `services/feature_migrations.dart`: nâng database cũ đến v4 mà không xóa dữ liệu.
- `FEATURES.md`: hướng dẫn thử M01–M07 và cấu hình Google OAuth.
