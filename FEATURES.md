# Chức năng M01–M07 và đăng nhập Google

Tất cả dữ liệu nghiệp vụ dùng SQLite cục bộ. File đóng gói: `database/prm_database.db`. Database trên điện thoại tự nâng cấp đến user_version=4, giữ lại tài khoản/dữ liệu hiện có. Có 34 bảng (32 bảng gốc + payroll_policies + employee_payroll_checks) và 5 view.

| Mã | Giao diện / luồng | Bảng chính |
| --- | --- | --- |
| M01 | Lịch ca → Chi tiết ca → Kiểm tra & điểm danh. Đăng ký thiết bị, duyệt thiết bị, kiểm tra GPS và Wi-Fi, xác nhận vào/ra ca; xem lịch sử chấp nhận/từ chối | employee_devices, branches, branch_wifi, attendance_events, attendance_records |
| M02 | Trang chủ → Kỳ lương & 6 bước. Quản lý tạo kỳ/hệ số, tạo hợp đồng từ Nhân sự, tính lương, thêm khoản cộng/trừ, tính lại và duyệt. Nhân viên chỉ tính/xem phiếu nháp của mình; không được duyệt | contracts, payroll_periods, payroll_policies, payslips, payslip_items, payroll_calculation_steps, employee_payroll_checks, v_payslip_totals |
| M03 | Lịch ca → xem giờ Việt Nam, chi nhánh, trạng thái, ghi chú và nhân viên cùng ca | shifts, shift_assignments, v_shift_roster |
| M04 | Trang chủ → Lịch ca/phân ca → Tạo ca → Phân nhân viên. Kiểm tra cùng chi nhánh, còn làm việc, trùng giờ, đủ số người và nghỉ phép đã duyệt | shifts, shift_assignments, employees, leave_requests |
| M05 | Chi tiết ca → Yêu cầu đổi ca → người nhận Đồng ý → Admin/Quản lý không tham gia ca duyệt. Cập nhật cả hai phân ca trong cùng transaction | shift_swap_requests, shift_assignments |
| M06 | Trang chủ → Sao nhân viên. Quản lý nhập số sao/lý do; Nhân viên chỉ thấy tổng sao của mình. Có hiệu ứng sao | star_events, v_employee_stars |
| M07 | Chi tiết ca → Chụp ảnh & đóng ca. Phải ra ca trước; ảnh được chụp bằng camera và sao chép vào thư mục riêng của app. Quản lý xem ảnh, duyệt hoặc từ chối. Có thể bổ sung/gửi lại báo cáo bị từ chối | shift_closures, shift_closure_photos |
| Auth | Đăng nhập mật khẩu hoặc Google; vai trò đọc từ SQLite; đăng xuất xóa màn hình phiên cũ và đăng xuất Google | users, user_roles, roles, permissions, role_permissions |

## Thứ tự chuẩn bị để thử nghiệp vụ

1. Đăng nhập Admin hoặc Quản lý. Từ Trang chủ mở Cấu hình GPS & Wi-Fi chi nhánh. Nhập tọa độ thật, bán kính và SSID/BSSID của router tại nhà hàng. Có thể đọc từ điện thoại hoặc nhập thủ công.
2. Tạo ca đúng ngày giờ, cùng chi nhánh nhân viên và phân nhân viên vào ca. Hồ sơ mới có thể liên kết tài khoản ở Nhân sự → chọn nhân viên → Liên kết tài khoản.
3. Nhân viên đăng nhập trên thiết bị, mở ca của mình và đăng ký thiết bị. Chuyển sang tài khoản Quản lý/Admin khác để duyệt thiết bị. Không cho tự duyệt thiết bị.
4. Nhân viên cấp quyền vị trí, bật GPS và kết nối đúng Wi-Fi. Kiểm tra GPS/Wi-Fi rồi xác nhận vào ca. Khi kết thúc kiểm tra lại và xác nhận ra ca.
5. Sau ra ca, chụp ảnh thật và nhập ghi chú đóng ca; Quản lý duyệt báo cáo.
6. Từ Nhân sự thêm hợp đồng có ngày hiệu lực, lương tháng và phút chuẩn. Tạo kỳ lương có hệ số tăng ca do người quản lý nhập. Tính toàn kỳ, xem chi tiết/6 bước, thêm khoản điều chỉnh nếu cần, tính lại rồi duyệt.

Điểm danh vào ca được phép từ 1 giờ trước giờ bắt đầu đến giờ kết thúc; ra ca đến 12 giờ sau giờ kết thúc. GPS phải trong bán kính, độ chính xác không vượt min(100m, bán kính), không là vị trí giả; bằng chứng phải mới trong 2 phút. Các điều kiện bắt buộc lấy từ branches. Máy ảo dùng vị trí giả có thể bị từ chối đúng thiết kế; cần kiểm tra phần cứng thực tế bằng điện thoại.

## Công thức lương được triển khai

Không tự gán thuế, bảo hiểm, hệ số tăng ca hay phụ cấp cố định. Quản lý nhập hệ số khi tạo kỳ; khoản cộng/trừ được nhập riêng. Hợp đồng phải đang active và bao phủ cả kỳ. Nếu thay hợp đồng giữa kỳ, hiện cần tách kỳ phù hợp trước khi tính.

- Công thực tế = thời gian check-out − check-in − giờ nghỉ của mẫu ca.
- Tăng ca = max(0, công thực tế − độ dài ca sau khi trừ nghỉ).
- Công thường = công thực tế − tăng ca.
- Đơn giá phút = lương tháng / phút chuẩn tháng; với hợp đồng hourly dùng đơn giá giờ / 60.
- Lương thường = làm tròn(công thường × đơn giá phút).
- Lương tăng ca = làm tròn(phút tăng ca × đơn giá phút × hệ số đã nhập).
- Thực lĩnh = lương thường + tăng ca + phụ cấp/thưởng − khấu trừ/thuế/bảo hiểm đã nhập.

Sáu bước: kiểm tra kỳ/hồ sơ → kiểm tra hợp đồng/đơn giá → tổng hợp công hợp lệ → tính thường/tăng ca → tổng hợp cộng/trừ → kiểm tra/lưu phiếu. Chi tiết 6 bước của từng nhân viên được lưu trong employee_payroll_checks. Không duyệt nếu thiếu bước, danh sách nhân viên thay đổi hoặc hash dữ liệu nguồn công/hợp đồng/phiếu không khớp. Phiếu đã chốt không được tính hoặc sửa khoản điều chỉnh lại.

## Cấu hình Gmail (cần thông tin Google Cloud của chủ dự án)

Mã đã tích hợp GoogleSignIn; chưa có OAuth Client ID thực trong repository. Không tạo tài khoản tùy ý hoặc gán Admin cho Gmail lạ. Admin phải chọn tài khoản trong mục Tài khoản và khai báo Gmail được phép đăng nhập. Sau khi Google xác thực thành công, app đối chiếu email đang active trong SQLite, liên kết Google subject và lấy vai trò đã cấp.

1. Trong Google Cloud tạo OAuth consent screen, Android OAuth client với package `com.example.quanlinhansunhahang` và SHA-1 đúng khóa ký của bản app.
2. Tạo OAuth client loại Web application và lấy Client ID (không dùng client secret trong app).
3. Chạy:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Mỗi máy phát triển có debug signing key riêng; khi chạy máy khác cần thêm Android client/SHA-1 tương ứng. Bản release cần đăng ký đúng fingerprint của khóa release. Tham khảo hướng dẫn chính thức: https://pub.dev/packages/google_sign_in_android#integration

Chưa thể kiểm thử đăng nhập Gmail thực nếu chưa có cấu hình OAuth của dự án. Không ảnh hưởng đăng nhập bằng tài khoản/mật khẩu SQLite. Google Sign-In cần Internet; dữ liệu nghiệp vụ vẫn nằm trên thiết bị.

## Kiểm thử và giới hạn đã biết

`flutter test` dùng SQLite thật trong thư mục tạm để kiểm tra quyền, ownership, ghi công, từ chối lặp/trùng ca, tính lương 6 bước, chốt lương, đổi ca nguyên tử, sao, ảnh/đóng ca và migration từ schema gốc. Các bằng chứng cảm biến trong unit test là dữ liệu đầu vào kiểm thử; không thay thế thử nghiệm GPS/Wi-Fi/camera thực tế.

SQLite lưu riêng trên từng thiết bị. Chưa có đồng bộ giữa điện thoại nhân viên và điện thoại quản lý; các vai trò phải thao tác trên cùng database cục bộ khi thử quy trình. Không bổ sung backend/MySQL theo yêu cầu dùng database trong project.

Lệnh kiểm thử Android giữ bản app sau khi test:

```powershell
flutter test integration_test/authentication_test.dart -d DEVICE_ID_ANDROID --no-uninstall
```

Sau kiểm thử integration, chạy lại bản app thông thường bằng `flutter run -t lib/main.dart`.

## Bộ dữ liệu mẫu

Đã chuẩn bị đủ dữ liệu cho 34 bảng và 5 view trong file database của project. Xem [database/DEMO_DATA.md](database/DEMO_DATA.md) để chọn tình huống thử cho từng vai trò. Ảnh mẫu là asset có nhãn DEMO. Trên app đã có database cũ, dùng Admin → Trang chủ → Nạp dữ liệu mẫu M01–M07 để bổ sung một lần mà giữ dữ liệu đã có.
