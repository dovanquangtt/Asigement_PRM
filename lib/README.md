# Cấu trúc frontend

main.dart chỉ gọi runApp. app.dart thiết lập MaterialApp và màn hình đầu tiên.

## Sửa ở đâu?

| Cần sửa | File |
| --- | --- |
| Màu | theme/app_colors.dart |
| Kiểu chữ, input, nút | theme/app_theme.dart |
| Đăng nhập | screens/login_screen.dart |
| Thanh điều hướng, ghép 4 tab | screens/workspace_screen.dart |
| Trang chủ, thẻ ca, thao tác nhanh | screens/home_screen.dart |
| Lịch và yêu cầu | screens/schedule_screen.dart |
| Thu nhập, phiếu lương | screens/payroll_screen.dart |
| Hồ sơ và đăng xuất | screens/profile_screen.dart |
| Dữ liệu và trạng thái dùng chung | state/workspace_controller.dart |
| Hộp thoại, thông báo, điều hướng chi tiết | services/workspace_actions.dart |
| Thẻ, tiêu đề, thống kê, logo dùng chung | widgets/common_widgets.dart |

## Luồng hoạt động

LoginPage mở Workspace với vai trò đã chọn. Workspace tạo WorkspaceController và hủy nó khi rời màn hình. AnimatedBuilder lắng nghe controller, truyền cùng controller và actions vào 4 tab. Khi người dùng thao tác, actions mở hộp thoại; controller.update cập nhật dữ liệu và notifyListeners để giao diện vẽ lại. Các giá trị chỉ tồn tại trong phiên, chưa được lưu vào MySQL.

Ví dụ: sửa màu nút tại theme; sửa thẻ điểm danh tại home_screen; sửa cách xác nhận điểm danh tại workspace_actions; sửa trạng thái entered/exited tại workspace_controller.

Nhóm có thể chia sửa từng màn hình; thống nhất trước khi sửa controller hoặc widgets dùng chung. Không cần thêm thư viện quản lý state cho bản hiện tại. Sau này lớp truy cập API có thể đặt trong services, tách khỏi hộp thoại UI khi thêm backend.
