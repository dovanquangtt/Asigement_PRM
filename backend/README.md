# Backend Java

REST API Spring Boot cho ứng dụng ANH EM QUÁN. Thư mục gốc hiện vẫn là Flutter frontend; backend được phát triển độc lập tại đây.

## Công nghệ

- Java 17 và Spring Boot 3.5
- Maven
- MySQL 8.0+ (cần CHECK constraint và cột sinh tự động)
- Flyway quản lý migration

## Chạy local

Cần MySQL 8 đang chạy ở `localhost:3306` và JDK 17+. Mặc định backend dùng user `root`, mật khẩu `123456` (chỉ dành cho máy phát triển) và dùng database `prm_database` (tự tạo nếu chưa có); Flyway tạo bảng khi khởi động nên database này phải trống hoặc chưa có bảng trùng tên.

```powershell
cd backend
mvn spring-boot:run "-Dspring-boot.run.profiles=dev"
```

Kiểm tra API tại `http://localhost:8080/api/health`. Đổi cấu hình bằng biến môi trường `DB_URL`, `DB_USER`, `DB_PASSWORD`, `SERVER_PORT`. Thời gian lưu dạng UTC (`DATETIME`); ngày làm việc tính theo UTC+7.

Chạy test và build. Test chạy trực tiếp trên database `prm_database` (cùng cấu hình `DB_URL`, `DB_USER`, `DB_PASSWORD`), không xóa bảng nhưng **thêm dữ liệu thử vào đó** (tài khoản `authit-*`, chi nhánh, ca, kỳ lương...). Riêng `PayrollIntegrationTest` tạm chuyển mọi nhân viên đang `active` sang `inactive` trong lúc chạy rồi khôi phục. Đừng chạy test trên database chứa dữ liệu thật:

```powershell
mvn test
mvn package
```

## Đăng nhập và Google

- `POST /api/auth/login` `{username, password}` và `POST /api/auth/google` `{idToken}` đều trả `{accessToken, tokenType, expiresIn, session}`; các API còn lại cần header `Authorization: Bearer <accessToken>`.
- Google chỉ xác minh danh tính: server kiểm tra chữ ký, hạn, issuer, audience (`GOOGLE_CLIENT_IDS`) và `email_verified`, sau đó email phải khớp đúng một tài khoản đang hoạt động do Admin cấp. Lần đầu đăng nhập, `google_subject` được gắn vào tài khoản và các lần sau phải trùng.
- Biến môi trường: `GOOGLE_CLIENT_IDS` (Web Client ID, cách nhau bằng dấu phẩy), `JWT_SECRET` (≥ 32 byte, bắt buộc đổi khi triển khai), `JWT_TTL_MINUTES`.
- Tài khoản mẫu cho dev: chạy với `--spring.profiles.active=dev` (admin/manager/employee như README gốc).
- Flutter: chạy với `--dart-define=API_BASE_URL=http://10.0.2.2:8080` (emulator Android) cùng `GOOGLE_WEB_CLIENT_ID`; khi có `API_BASE_URL`, nút Google gửi ID token lên server.
- Tài liệu API từng module: thư mục `docs/`.

## Chế độ ứng dụng qua API (chấm công, quản lý, admin)

Khi chạy Flutter với `--dart-define=API_BASE_URL=...`, đăng nhập (mật khẩu hoặc Google) đi qua backend và ứng dụng mở giao diện theo vai trò: nhân viên chấm công vào/ra bằng GPS + thiết bị đã đăng ký, quản lý và admin xem bảng điều khiển chấm công, thiết bị, báo cáo. Hợp đồng JSON: `docs/api-app-contract.md`. Địa chỉ API: emulator Android `http://10.0.2.2:8080`; điện thoại thật `http://<IP LAN máy chạy backend>:8080` (mở cổng 8080 trong tường lửa; bản debug cho phép HTTP, bản release phải dùng HTTPS). Các chức năng khác (lịch ca, lương, đóng ca) vẫn là SQLite trong chế độ ngoại tuyến cho đến khi được nối API.

## Phạm vi hiện tại

Toàn bộ nghiệp vụ của lớp dịch vụ Flutter đã được port sang REST API: xác thực/Google, tài khoản và nhân viên, ca làm/nghỉ phép/đổi ca, chấm công, lương, sao, đóng ca (xem `docs/api-*.md`). Test tích hợp chạy trên MySQL cục bộ (`mvn test`). Phần còn lại là chuyển giao diện Flutter từ SQLite sang gọi HTTP; hiện chỉ đăng nhập Google đã nối với server. Không nhập trực tiếp file SQLite hiện tại vào PostgreSQL; cần viết bước migration dữ liệu có kiểm tra và ánh xạ kiểu dữ liệu.