# ANH EM QUÁN — Quản lý nhân sự nhà hàng

Ứng dụng Flutter quản lý nhân sự nhà hàng với ba vai trò **Admin, Quản lý, Nhân viên**.
Đăng nhập bằng tài khoản được cấp hoặc Google; SQLite lưu tài khoản, quyền và dữ liệu
nghiệp vụ riêng trên từng thiết bị. README này tổng hợp thông tin chức năng và frontend.

## 1. Cài đặt và chạy

Cần Flutter SDK, Android SDK và Java tương thích với cấu hình Gradle của project.

```powershell
flutter pub get
flutter devices
flutter run
```

Trong VS Code: chọn thiết bị Android/Pixel, mở **Run and Debug → Flutter - Gmail**,
nhấn **F5**. Cấu hình `.vscode/launch.json` đã truyền Web Client ID của dự án.
Sau khi đổi plugin hoặc `--dart-define`, dừng app rồi chạy lại hoàn toàn.
Hot reload dùng cho thay đổi giao diện; không cập nhật tham số bản build.

`android/local.properties`, `.dart_tool`, `build` và cache thuộc từng máy, không
đưa lên Git. Nếu Terminal không tìm thấy Java, dùng JDK đi kèm Android Studio:

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
```

Thay đường dẫn nếu Android Studio được cài nơi khác. Lệnh chỉ áp dụng cho Terminal hiện tại.

### Tài khoản mẫu

| Tên đăng nhập | Mật khẩu | Vai trò |
| --- | --- | --- |
| admin | Admin@12345 | Admin |
| manager | Manager@12345 | Quản lý |
| employee | Employee@12345 | Nhân viên |

Chỉ dùng các tài khoản này để thử nghiệm. Mật khẩu được lưu bằng bcrypt.
Không đăng nhập bằng tên/mật khẩu bất kỳ; không tự chọn vai trò ở màn hình đăng nhập.

## 2. Không gian và phân quyền

| Vai trò | Chức năng |
| --- | --- |
| Admin | Quản lý tài khoản, cấp vai trò, liên kết Gmail/hồ sơ, nhân sự và các thao tác được cấp quyền |
| Quản lý | Nhân sự, hợp đồng, lịch/phân ca, duyệt thiết bị, đổi ca, lương và báo cáo đóng ca |
| Nhân viên | Lịch ca, điểm danh, yêu cầu đổi ca/nghỉ phép, thu nhập và hồ sơ cá nhân |

Quyền được đối chiếu lại với `users`, `user_roles`, `role_permissions` và
`permissions` trước khi truy cập dữ liệu. Nhân viên chỉ truy cập nghiệp vụ của mình.
Tài khoản bị khóa sẽ bị chặn ở các truy vấn tiếp theo. Người tham gia nghiệp vụ
không được tự duyệt các mục mà hệ thống yêu cầu người khác phê duyệt.

## 3. Chức năng M01–M07

| Mã | Luồng và nghiệp vụ | Bảng chính |
| --- | --- | --- |
| M01 | Lịch ca → Chi tiết ca → Kiểm tra thiết bị & Điểm danh. Chọn thiết bị của mình, gửi bằng chứng GPS/Wi-Fi, Admin duyệt/từ chối và xem lịch sử | employee_devices, branches, branch_wifi, attendance_events, attendance_records |
| M02 | Kỳ lương & 6 bước. Admin/Quản lý tạo kỳ, tính lương, điều chỉnh và duyệt; sau khi chuyển tiền thực tế, xác nhận thanh toán theo từng nhân viên. Nhân viên nhận thông báo riêng khi duyệt và khi xác nhận đã trả | contracts, payroll_periods, payslips, payslip_items, payroll_calculation_steps, employee_payroll_checks |
| M03 | Xem lịch, chi tiết ca theo giờ Việt Nam, chi nhánh, trạng thái, ghi chú và nhân viên cùng ca | shifts, shift_assignments, v_shift_roster |
| M04 | Tạo ca/phân nhân viên; kiểm tra chi nhánh, trạng thái nhân sự, trùng giờ, sức chứa và nghỉ phép đã duyệt | shifts, shift_assignments, employees, leave_requests |
| M05 | Yêu cầu đổi ca → người nhận đồng ý → Admin/Quản lý không tham gia ca duyệt; cập nhật hai phân ca trong cùng transaction | shift_swap_requests, shift_assignments |
| M06 | Quản lý nhập sao/lý do; nhân viên xem tổng sao của mình | star_events, v_employee_stars |
| M07 | Ra ca → chụp ảnh và ghi chú đóng ca → quản lý duyệt/từ chối; có thể bổ sung và gửi lại báo cáo bị từ chối | shift_closures, shift_closure_photos |
| Auth | Đăng nhập mật khẩu/Google, lấy vai trò từ SQLite; đăng xuất Google và xóa lịch sử màn hình phiên cũ | users, user_roles, roles, permissions, role_permissions |
| Thông báo | Thông báo theo luồng nghiệp vụ, xem danh sách và đánh dấu đã đọc | notifications, notification_recipients |

### Thứ tự chạy thử

1. Admin/Quản lý cấu hình GPS & Wi-Fi chi nhánh: tọa độ thật, bán kính,
   SSID và BSSID của router nhà hàng.
2. Tạo ca đúng ngày giờ, cùng chi nhánh nhân viên, rồi phân nhân viên vào ca.
   Hồ sơ mới có thể liên kết tài khoản từ mục Nhân sự.
3. Nhân viên đăng ký thiết bị; chuyển sang Quản lý/Admin khác để duyệt thiết bị.
4. Nhân viên chọn thiết bị của chính tài khoản, cấp quyền vị trí nếu có và kiểm tra
   từng bước **Thiết bị → GPS → Wi-Fi** để xem cảnh báo. Chưa đạt vẫn gửi được cho Admin.
5. Xác nhận vào/ra ca. Nếu hợp lệ sẽ tự ghi công; Admin/Quản lý chỉ xử lý ngoại lệ trong mục **Quản lý chấm công & ngoại lệ**. App đọc lại
   cảm biến sau hộp thoại gửi, lưu cả thiết bị được chọn và thiết bị thực tế. Đi muộn không cần duyệt riêng; chỉ ngoại lệ mới chờ xử lý.
6. Chụp ảnh thật, nhập ghi chú đóng ca và gửi quản lý duyệt.
7. Thêm hợp đồng có ngày hiệu lực, lương và phút chuẩn; tạo kỳ lương, tính,
   xem sáu bước, thêm điều chỉnh nếu cần, tính lại rồi duyệt. Admin và Quản lý
   cùng thao tác trên kỳ lương; mỗi kỳ sinh một phiếu cho từng nhân viên.
   Duyệt chỉ chốt số liệu và gửi thông báo “Bảng lương đã được duyệt”, không
   xác nhận tiền đã chuyển. Sau khi thanh toán thực tế, mở **Phiếu nhân viên &
   thanh toán** trong kỳ, xem chi tiết và xác nhận từng phiếu. Nhân viên nhận
   thông báo thanh toán và có thể mở phiếu từ thông báo. Kỳ chỉ chuyển sang
   “Đã thanh toán đủ” khi tất cả phiếu của kỳ đã được xác nhận.

### Quy tắc chấm công và xử lý ngoại lệ

Điểm danh có thiết bị/GPS/Wi-Fi hợp lệ và trong thời hạn sẽ tự ghi nhận.
Không yêu cầu Admin duyệt tất cả lần điểm danh. Điều kiện đầu vào chưa đạt
được lưu kèm bằng chứng và chuyển ngoại lệ cho người có quyền xử lý.

| Trường hợp | Cách xử lý |
| --- | --- |
| Vào sớm trong một giờ cho phép / đúng giờ | Tự lưu giờ thực tế, không cần duyệt |
| Vào muộn nhưng còn trong ca | Tự ghi nhận, tính phút muộn theo thời gian ân hạn mẫu ca; không tự tạo khoản phạt lương |
| Ra sau kết thúc ca | Lưu giờ ra thực tế; chỉ chờ duyệt phần tăng ca nếu chi nhánh bật quy định |
| Ra sau 00:00 | Giữ nguyên phân ca, ngày công theo ngày bắt đầu ca tại Việt Nam; ra không quá 12 giờ sau kết thúc ca |
| Thiếu giờ vào / giờ ra | Hiện trạng thái thiếu công; nhân viên gửi yêu cầu bổ sung, người quản lý duyệt/từ chối |
| Đề nghị sửa giờ | Chưa đổi bảng công; lưu giờ hiện tại, giờ đề nghị, lý do, ảnh minh chứng nếu có |
| Thiết bị, GPS, Wi-Fi hoặc thời gian bất thường | Gắn cờ, lưu bằng chứng thực tế và chuyển người có quyền kiểm tra |

**Trang chủ → Quản lý chấm công & ngoại lệ** có thống kê nhân viên, đã điểm danh,
đi muộn, chờ xử lý; chọn ngày và lọc tất cả/cần xử lý/đi muộn/thiếu giờ. Mỗi chi tiết
hiển thị ca, giờ công hiện tại, điểm danh gốc, GPS/Wi-Fi/thiết bị, đề nghị điều chỉnh,
minh chứng, người duyệt và lịch sử thao tác. Nhân viên mở **Công của tôi & yêu cầu
sửa công** hoặc **Xem công / yêu cầu sửa giờ** ngay trong màn hình điểm danh.

- Quản lý chỉ xem và xử lý công trong chi nhánh của mình; Admin xem toàn hệ thống.
  Không tự duyệt ngoại lệ, yêu cầu sửa công hoặc tăng ca của bản thân.
- Admin cấu hình yêu cầu duyệt tăng ca tại **Cấu hình GPS & Wi-Fi chi nhánh**.
  Mặc định không yêu cầu duyệt để giữ tương thích cấu hình cũ. Khi bật, phút tăng
  ca chờ duyệt hoặc bị từ chối vẫn hiện trong lịch sử nhưng chưa được tính vào lương.
- Chỉ duyệt ngoại lệ, sửa công và tăng ca cần thiết. Từ chối hoặc duyệt bất thường
  phải có nhận xét; nhân viên nhận thông báo kết quả trong cùng SQLite.
- Duyệt điều chỉnh cập nhật bảng công, giữ nguyên `attendance_events` gốc và lưu
  trước/sau trong yêu cầu và audit log. Không ghi đè lịch sử bằng chứng.
- Không duyệt trùng, không sửa giờ công đã bị thay đổi kể từ lúc gửi mà chưa đối chiếu,
  không chấp nhận giờ tương lai. Chốt công chỉ khi ca xong, đủ giờ, hết yêu cầu chờ xử lý.
  Công đã chốt hoặc kỳ lương đã duyệt/thanh toán không được chỉnh sửa hồi tố.
- Trạng thái vào ca (`ON_TIME`/`LATE`), trạng thái công (`IN_PROGRESS`,
  `MISSING_CHECK_IN`, `MISSING_CHECK_OUT`, `COMPLETED`) và yêu cầu điều chỉnh
  (`PENDING_ADJUSTMENT`, duyệt/từ chối) được tách riêng, không coi đi muộn là chờ duyệt.
- Bản hiện tại demo đổi tài khoản trên **cùng một máy/database**, chưa đồng bộ Internet.

### Công thức lương

Quản lý nhập hệ số tăng ca và khoản cộng/trừ; không tự gán mức thuế, bảo hiểm
hoặc phụ cấp cố định. Hợp đồng phải active và bao phủ cả kỳ. Khi thay hợp đồng
giữa kỳ, cần tách kỳ phù hợp trước khi tính.

- Công thực tế = check-out − check-in − thời gian nghỉ theo mẫu ca.
- Tăng ca thực tế = số phút sau giờ kết thúc ca, không vượt tổng phút làm; chỉ tính trả tăng ca khi không cần duyệt hoặc đã được duyệt.
- Công thường = công thực tế − tăng ca thực tế; không chuyển tăng ca chưa duyệt thành công thường để trả lương.
- Đơn giá phút = lương tháng / phút chuẩn tháng; hợp đồng hourly dùng đơn giá giờ / 60.
- Lương thường = làm tròn(công thường × đơn giá phút).
- Lương tăng ca = làm tròn(phút tăng ca × đơn giá phút × hệ số đã nhập).
- Thực lĩnh = lương thường + tăng ca + phụ cấp/thưởng − khấu trừ/thuế/bảo hiểm đã nhập.

Sáu bước: **kiểm tra kỳ/hồ sơ → hợp đồng/đơn giá → công hợp lệ → thường/tăng ca
→ cộng/trừ → kiểm tra/lưu phiếu**. Không duyệt nếu thiếu bước hoặc dữ liệu nguồn
đã thay đổi. Phiếu đã chốt không được tính lại hay sửa khoản điều chỉnh.

## 4. Cấu hình đăng nhập Google

Web Client ID của dự án được truyền qua `--dart-define` trong `.vscode/launch.json`.
Không đưa Client Secret vào app. Android dùng Web Client ID làm `serverClientId`.

1. Trong cùng Google Cloud project, cấu hình OAuth consent screen và tạo Web OAuth Client.
2. Tạo Android OAuth Client với package `com.example.quanlinhansunhahang`
   và SHA-1 của đúng khóa ký bản app.
3. Khi còn Testing, thêm email thử nghiệm tại **Audience → Test users**.
4. Admin khai báo Gmail cho một tài khoản duy nhất đang hoạt động và có vai trò
   trong database của thiết bị dùng thử. Gmail lạ không tự tạo tài khoản.

Lấy SHA-1 từ thư mục gốc project:

```powershell
cd android
.\gradlew.bat signingReport
```

Lấy dòng `SHA1` thuộc `:app:signingReport` → `Variant: debug`.
Đồng đội tự build với khóa debug khác cần đăng ký thêm Android Client/SHA-1 trong
cùng Google Cloud project; Web Client ID dùng chung. Người cài cùng một APK
không cần tự cấu hình khóa ký. Bản release cần đăng ký fingerprint khóa ký release.

Chạy từ thư mục gốc nếu không dùng cấu hình VS Code:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Thay bằng Web Client ID thật. Google Sign-In cần Internet và Google Play services
phù hợp trên Android. Nếu báo thiếu `GOOGLE_WEB_CLIENT_ID`, dừng app và chạy lại
đúng cấu hình. Tham khảo: https://pub.dev/packages/google_sign_in_android#integration

## 5. Cấu trúc frontend

Luồng chính:

```text
lib/main.dart → PrmApp → DatabaseStartup → LoginPage → Workspace
```

| Thành phần | Vai trò |
| --- | --- |
| lib/app.dart | MaterialApp và theme gốc |
| lib/screens/login_screen.dart | Đăng nhập mật khẩu/Gmail, giao diện ANH EM QUÁN và câu nói theo ngày |
| lib/screens/workspace_screen.dart | Điều hướng và không gian theo vai trò |
| lib/screens/schedule_screen.dart | Lịch ca |
| lib/screens/payroll_screen.dart | Giao diện phiếu lương nhân viên và các thành phần lương |
| lib/screens/operations_screen.dart | Các màn hình nghiệp vụ, chi tiết ca, điểm danh, lương, đóng ca |
| lib/screens/notifications_screen.dart | Thông báo nghiệp vụ |
| lib/services/auth_service.dart, google_auth.dart | Xác thực, đối chiếu tài khoản/vai trò và Google Sign-In |
| lib/services/workforce_repository.dart, workforce_operations.dart | Truy vấn, phân quyền và transaction nghiệp vụ SQLite |
| lib/services/attendance_sensors.dart | Đọc thiết bị, GPS, Wi-Fi từ plugin |
| lib/services/attendance_management.dart | Tổng hợp công, phạm vi chi nhánh, điều chỉnh, tăng ca và chốt công |
| lib/screens/attendance_management_screen.dart | Tổng quan chấm công, chi tiết và yêu cầu sửa giờ |
| lib/services/local_database.dart | Sao chép và mở database cục bộ |
| lib/widgets/, lib/theme/ | Widget dùng chung, màu sắc và theme |
| assets/branding/anh_em_quan.jpg | Ảnh thương hiệu đóng gói, dùng được offline |

Một số file demo cũ như `home_screen.dart`, `profile_screen.dart`,
`workspace_controller.dart`, `workspace_actions.dart` vẫn còn trong source;
không nên coi chúng là bằng chứng cho luồng đang chạy. Kiểm tra nơi được
`Workspace` hiện tại gọi trước khi sửa giao diện.

## 6. Database và dữ liệu mẫu

- `database/prm_database.db`: SQLite khởi tạo, 34 bảng và 5 view.
- `database/prm_schema.sql`, `prm_seed.sql`: schema và danh mục.
- `database/prm_features_v3.sql`, `prm_features_v4.sql`: cấu trúc nghiệp vụ bổ sung.
- `database/prm_demo_seed.sql`: snapshot dữ liệu mẫu.
- `lib/services/sample_data.dart`, `feature_sample_data.dart`: cài/bổ sung mẫu.
- `lib/services/feature_migrations.dart`: nâng cấp database.

Không cần MySQL hoặc server database. Lần đầu chạy, asset được sao chép vào
thư mục riêng của app. Sau đó app đọc/ghi bản cục bộ, không cập nhật ngược file
`.db` trong project. Migration giữ dữ liệu hiện có, hiện nâng tới `user_version=6`.

App đã có database cũ: Admin → Trang chủ → **Nạp dữ liệu mẫu M01–M07**.
Bộ mẫu có marker chống nạp lặp, không cần xóa database hoặc nhập SQL thủ công.
Ảnh DEMO chỉ là dữ liệu mẫu. Các ca mẫu có ngày cụ thể có thể đã qua thời gian
cho phép điểm danh/đổi ca; tạo ca mới đúng ngày khi cần thử.

## 7. Kiểm thử và giới hạn

```powershell
flutter analyze
flutter test
flutter test integration_test/authentication_test.dart -d DEVICE_ID_ANDROID --no-uninstall
```

Thay `DEVICE_ID_ANDROID` bằng ID từ `flutter devices`. Sau integration test,
chạy lại bản app thông thường. Unit/widget test dùng SQLite thật trong thư mục
tạm và cảm biến giả lập để kiểm tra quyền, dữ liệu cá nhân, điểm danh, duyệt thiết
bị, đổi ca, lương, thông báo, migration và bố cục điện thoại.

- **Chưa có đồng bộ giữa thiết bị.** Tài khoản, Gmail, duyệt thiết bị và dữ liệu
  nghiệp vụ phải nằm trong cùng database cục bộ khi thử luồng nhiều vai trò.
- Xác nhận thanh toán là ghi nhận thủ công sau khi chuyển tiền ngoài ứng dụng;
  ứng dụng chưa kết nối ngân hàng và không tự xác minh giao dịch. Admin/Quản lý
  phải dùng chung database cục bộ để trạng thái và thông báo xuất hiện với nhân viên.
- GPS/Wi-Fi/camera cần kiểm thử thực tế trên điện thoại tại chi nhánh.
  Máy ảo không thay thế kiểm thử cảm biến thật; vị trí giả có thể bị từ chối.
- Thiếu quyền, tắt dịch vụ vị trí, không đọc được BSSID hoặc cấu hình chi nhánh
  sai sẽ tạo cảnh báo trong yêu cầu để Admin kiểm tra; chưa ghi công trước khi duyệt.
- Chức năng Google hiện được cấu hình cho Android; nền tảng khác cần tích hợp riêng.
