# Dữ liệu DEMO cho Admin, Quản lý và Nhân viên

Dữ liệu đã nằm thật trong `database/prm_database.db`, không chỉ ở giao diện. Toàn bộ 34 bảng và 5 view đều có bản ghi. `prm_demo_seed.sql` là bản snapshot SQL dễ đọc, có INSERT cho đầy đủ 34 bảng. Không thêm role ngoài 3 role sẵn có; không thay mật khẩu hay thiết lập biến môi trường.

## Tài khoản

| Tài khoản | Mật khẩu | Vai trò |
| --- | --- | --- |
| admin | Admin@12345 | Admin |
| manager | Manager@12345 | Quản lý |
| employee | Employee@12345 | Nhân viên |

Mỗi tài khoản có hồ sơ, hợp đồng active, đơn giá lương, số dư phép, thiết bị minh họa, sao và phiếu lương riêng. Email `.example` chỉ là dữ liệu mẫu; không tạo Google subject/OAuth giả.

## Những dữ liệu có thể thử ngay

| Phần | Dữ liệu |
| --- | --- |
| Chi nhánh / danh mục | 1 chi nhánh, Wi-Fi mẫu, 3 bộ phận, 4 chức vụ, 4 mẫu ca gồm ca qua đêm |
| Phân quyền | 3 role, 20 quyền, 48 liên kết role–quyền, 3 tài khoản |
| Thiết bị | 5 bản ghi: đã duyệt, chờ duyệt và đã thu hồi |
| Lịch / ca làm | 13 ca, 18 phân ca; lịch sử, đang diễn ra, tương lai và ca trống để phân thêm |
| Chấm công | 10 bản ghi công, 22 sự kiện gồm accepted, rejected và pending_review |
| Hợp đồng / lương | 3 hợp đồng, 2 kỳ, 6 phiếu lương, 30 khoản cộng/trừ đủ 5 loại |
| 6 bước tính lương | 12 bước toàn kỳ và 36 kiểm tra cá nhân, hash nguồn cùng cách tính với nghiệp vụ |
| Đổi ca | 3 yêu cầu: chờ người nhận, người nhận đã đồng ý/chờ Admin duyệt, đã từ chối |
| Sao | 4 sự kiện cộng/trừ; Nhân viên chỉ đọc tổng của mình |
| Đóng ca | 9 báo cáo: 6 đã duyệt, 2 chờ duyệt, 1 bị từ chối; 9 ảnh minh họa đi kèm |
| Nghỉ phép / điều chỉnh công | 3 số dư phép, 3 đơn nghỉ, 2 yêu cầu điều chỉnh công |
| Thông báo / nhật ký | 3 thông báo, 9 người nhận; nhật ký đánh dấu bộ dữ liệu đã nạp |

### Admin

Đăng nhập `admin`: xem đủ 3 tài khoản/nhân sự. Mở các chức năng tại Trang chủ để xem dữ liệu. Trong Đổi ca, có một yêu cầu người nhận đã đồng ý để thử duyệt ngay; Admin không phải người tham gia đổi ca.

### Quản lý

Đăng nhập `manager`: mở lịch ca để phân thêm người vào ca `[DEMO UNASSIGNED]`, xem đội ngũ trong ca, duyệt thiết bị hoặc báo cáo của Nhân viên. Kỳ `DEMO_OPEN` có phiếu nháp và đủ 6 bước để thử tính lại, thêm khoản điều chỉnh rồi tính lại/duyệt. Kỳ `DEMO_PAID` đã trả để kiểm tra app chặn sửa lương đã chốt.

### Nhân viên

Đăng nhập `employee`: xem lịch và 2 phiếu lương của riêng mình. Mở:

- Ca `[DEMO LIVE]`: ca tại thời điểm tạo bộ mẫu, chưa điểm danh để thử vào/ra ca thật.
- Ca `[DEMO READY_CLOSE]`: đã có check-out, chưa có báo cáo; dùng camera chụp ảnh và gửi đóng ca.
- Ca `[DEMO RETRY_CLOSE]`: báo cáo bị từ chối, có thể bổ sung ảnh/ghi chú và gửi lại.
- Các ca `[DEMO FUTURE_*]`: để xem thông tin và thử đổi ca.

Ngày giờ được tạo theo thời điểm nạp lần đầu, lưu UTC và hiển thị giờ Việt Nam. Sau nhiều ngày, ca LIVE sẽ thành ca lịch sử; hãy tạo ca mới tại ngày đang thử. Nạp lại không tự dời lịch hoặc ghi đè dữ liệu đã sửa.

## Nếu app đã có database cũ

App tự bổ sung mẫu một lần cho database vẫn dùng đúng ba tài khoản demo gốc, kể cả khi bạn đã tạo ca/phân ca bằng tay. Các bản ghi đã nhập được giữ lại. Database có tài khoản khác dùng nút nạp mẫu của Admin. Thao tác trên giao diện tiếp tục lưu vào SQLite riêng của thiết bị; không ghi ngược vào file asset trong mã nguồn.


App không ghi đè database đang dùng bằng file asset mới. Để nhận bộ mẫu mà giữ dữ liệu hiện tại: đăng nhập **Admin → Trang chủ → Nạp dữ liệu mẫu M01–M07**, đọc xác nhận rồi nạp. Thao tác chỉ thêm bộ mẫu một lần; lần sau giữ nguyên dữ liệu đã chỉnh. Cần còn ba hồ sơ mẫu gốc cùng chi nhánh; nếu không, thao tác báo lỗi và rollback, không tự sửa tài khoản thật.

## Ảnh, GPS, Wi-Fi và Gmail

Ảnh `demo_assets/closure_sample.png` là hình minh họa có chữ DEMO, không phải ảnh chụp thật. Database dùng URI `asset:database/demo_assets/closure_sample.png`, nên không chứa đường dẫn ổ C/D hoặc tên người dùng máy phát triển. Ảnh chụp bằng camera vẫn lưu riêng trên thiết bị.

Tọa độ/Wi-Fi/mã thiết bị mẫu là dữ liệu minh họa, không thay cho thiết bị thật. Để điểm danh accepted, vẫn phải cấu hình vị trí và Wi-Fi chi nhánh thật, đăng ký/duyệt thiết bị thật. Không tắt các kiểm tra để dữ liệu mẫu tự qua xác thực. Gmail vẫn cần OAuth Client ID/SHA-1 và email tài khoản thật do Admin cấp.

## Tạo lại snapshot / kiểm thử

Tại thư mục project, dùng Flutter/Dart đã có sẵn:

```powershell
dart run tool/seed_database.dart
flutter test --no-pub
flutter analyze --no-pub
```

Lệnh seed nạp khi chưa có marker `sample.features.v1`, tạo ảnh minh họa và xuất SQL. Chạy lại không nhân đôi bản ghi. `prm_demo_seed.sql` là snapshot **đầy đủ**, chỉ khôi phục vào schema v4 **trống**, không chạy sau `prm_seed.sql` và không chạy lên database đang có dữ liệu. Ứng dụng không cần chạy file SQL này vì đã có file `.db`.
