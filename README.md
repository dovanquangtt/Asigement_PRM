# Mộc — App quản lý nhân sự nhà hàng

Ứng dụng mobile Flutter với 3 vai trò. Đăng nhập kiểm tra tài khoản đang hoạt động và mật khẩu bcrypt trong SQLite; vai trò lấy từ database, người dùng không tự chọn vai trò khi đăng nhập.

## Không gian theo vai trò

| Vai trò | Màn hình và thao tác hiện có |
| --- | --- |
| Admin | Tổng quan, danh sách tài khoản, tạo tài khoản và gán một trong 3 vai trò, danh sách/thêm nhân viên, hồ sơ cá nhân |
| Quản lý | Tổng quan, danh sách/thêm nhân viên, xem phân ca và phiếu lương đã lưu, hồ sơ cá nhân |
| Nhân viên | Tổng quan cá nhân, xem phân ca và phiếu lương của chính mình, hồ sơ cá nhân |

Quyền được đối chiếu lại với users, user_roles, role_permissions và permissions trước khi truy cập dữ liệu. Nhân viên không được truy vấn danh sách tài khoản/nhân sự hoặc phiếu lương, lịch ca của người khác. Khóa tài khoản trong database sẽ chặn các truy vấn tiếp theo.

## Database nằm trong project

- `database/prm_database.db`: file SQLite thật, gồm 34 bảng (32 bảng gốc + 2 bảng nghiệp vụ bổ sung), 5 view, dữ liệu danh mục và 3 tài khoản/hồ sơ mẫu.
- `database/prm_schema.sql`: cấu trúc bảng và view.
- `database/prm_seed.sql`: dữ liệu danh mục.
- `lib/services/sample_data.dart`: cài tài khoản và hồ sơ mẫu một lần, không ghi đè tài khoản đã tồn tại.

Không cần MySQL, máy chủ database hoặc ứng dụng bên ngoài. Khi chạy trên điện thoại, file database được sao chép từ asset sang thư mục dữ liệu riêng của app; mọi thay đổi được lưu ở đó qua các lần mở app. File `.db` trong project là bản khởi tạo, không phải file đang được điện thoại cập nhật.

## Chạy trên Android

```powershell
flutter pub get
flutter run
```

Dừng bản app cũ rồi chạy lại sau khi thay đổi mã kết nối hoặc plugin.

| Tài khoản mẫu | Mật khẩu | Vai trò |
| --- | --- | --- |
| admin | Admin@12345 | Admin |
| manager | Manager@12345 | Quản lý |
| employee | Employee@12345 | Nhân viên |

Mật khẩu được lưu bằng bcrypt trong `users.password_hash`. Các tài khoản trên dành cho thử nghiệm.

## Kiểm thử

```powershell
flutter analyze
flutter test
flutter test integration_test/authentication_test.dart -d DEVICE_ID_ANDROID --no-uninstall
```

Các kiểm thử dùng SQLite thật, kiểm tra đăng nhập sai/đúng, vai trò, giới hạn dữ liệu cá nhân và lưu dữ liệu. Kiểm thử integration chạy trực tiếp trên Android.

## Phạm vi hiện tại

Đã triển khai giao diện và nghiệp vụ M01–M07: thiết bị/GPS/Wi-Fi/điểm danh, lịch/phân ca, tính và duyệt lương 6 bước, đổi ca, sao, ảnh và đóng ca. Có liên kết hồ sơ mới với tài khoản. Đăng nhập Gmail cần Google OAuth Client ID/SHA-1 của chủ dự án; chưa có cấu hình Google thật trong repository. SQLite lưu riêng trên từng thiết bị, chưa đồng bộ giữa điện thoại. Xem [FEATURES.md](FEATURES.md) để biết cách cấu hình, thứ tự thử chức năng, công thức lương và giới hạn kiểm thử.

## Cấu hình trên từng máy

Project không đặt JAVA_HOME, ANDROID_HOME, PATH hay cấu hình hệ điều hành. Dùng Flutter/Android SDK đã có trên máy của bạn. `android/local.properties`, `.dart_tool`, `build` và cache là dữ liệu riêng từng máy, không đưa lên Git. Không áp dụng cấu hình cache Kotlin dành riêng cho ổ C/D của máy phát triển.

Chạy `flutter devices` để lấy thiết bị Android của máy bạn; thay `DEVICE_ID_ANDROID` trong lệnh test bằng ID vừa liệt kê. `flutter run` cho phép chọn thiết bị, không cố định tên máy ảo. Google Client ID là tham số bản build `--dart-define`, không cần tạo biến môi trường toàn hệ thống.

## Bộ dữ liệu thử đầy đủ

File `database/prm_database.db` đã chứa dữ liệu cho đủ 34 bảng và 5 view, giữ nguyên 3 role. Xem [hướng dẫn dữ liệu mẫu](database/DEMO_DATA.md) hoặc [snapshot INSERT SQL](database/prm_demo_seed.sql).

Với app đã có database cũ: chạy lại bản code mới, đăng nhập Admin → Trang chủ → Nạp dữ liệu mẫu M01–M07. Không cần xóa database hoặc nhập SQL thủ công. Các lần nạp sau giữ nguyên dữ liệu đã chỉnh.
