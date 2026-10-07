# Frontend Flutter cho Pixel

Mở lib/main.dart, chọn Pixel ở thanh thiết bị VS Code, nhấn F5. Nếu app đang chạy phiên bản cũ, dùng Hot Restart hoặc dừng rồi chạy lại.

Đăng nhập trải nghiệm: nhập tên và mật khẩu bất kỳ, chọn Nhân viên / Quản lý / Admin. Không sử dụng mật khẩu MySQL để đăng nhập ứng dụng.

Có 4 tab: Trang chủ, Lịch ca, Thu nhập, Cá nhân. Điểm danh mẫu có xác nhận vào/ra ca; có yêu cầu nghỉ, đổi ca, điều chỉnh công, ghi chú đóng ca, thông báo, hồ sơ, hợp đồng, phiếu lương. Chọn Quản lý/Admin để xem thao tác quản lý mẫu.

Chưa kết nối MySQL, chưa xác thực đăng nhập hay phân quyền thật; dữ liệu và yêu cầu chỉ giữ trong phiên. GPS/Wi-Fi/thiết bị là mô phỏng, chưa chụp ảnh. Các màn hình quản lý hiện là bản giao diện ban đầu, chưa phải nghiệp vụ hoàn chỉnh.

Kiểm tra: dart analyze lib test; flutter test. Widget test chạy ở 412x915 và 360x800, kiểm tra đăng nhập, điểm danh, lịch ngày nghỉ, chuyển tab và lỗi layout.
