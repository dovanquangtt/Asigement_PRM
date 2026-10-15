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

- `database/prm_database.db`: file SQLite thật, gồm 32 bảng, 5 view, dữ liệu danh mục và 3 tài khoản/hồ sơ mẫu.
- `database/prm_schema.sql`: cấu trúc bảng và view.
- `database/prm_seed.sql`: dữ liệu danh mục.
- `lib/services/sample_data.dart`: cài tài khoản và hồ sơ mẫu một lần, không ghi đè tài khoản đã tồn tại.

Không cần MySQL, máy chủ database hoặc ứng dụng bên ngoài. Khi chạy trên điện thoại, file database được sao chép từ asset sang thư mục dữ liệu riêng của app; mọi thay đổi được lưu ở đó qua các lần mở app. File `.db` trong project là bản khởi tạo, không phải file đang được điện thoại cập nhật.

## Chạy trên Android

```powershell
flutter pub get
flutter run -d emulator-5554
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
flutter test integration_test/authentication_test.dart -d emulator-5554
```

Các kiểm thử dùng SQLite thật, kiểm tra đăng nhập sai/đúng, vai trò, giới hạn dữ liệu cá nhân và lưu dữ liệu. Kiểm thử integration chạy trực tiếp trên Android.

## Phạm vi hiện tại

Lịch ca và phiếu lương hiển thị các bản ghi có trong database; khi chưa có dữ liệu, app hiển thị trạng thái trống. Chức năng tạo/phân ca, chấm công thực tế, tính/duyệt lương và duyệt nghỉ phép chưa có trong giao diện hiện tại. Hồ sơ thêm mới được gán chi nhánh đầu tiên, chưa có màn hình liên kết hồ sơ với tài khoản. SQLite lưu riêng trên từng thiết bị và chưa đồng bộ giữa nhiều điện thoại.
