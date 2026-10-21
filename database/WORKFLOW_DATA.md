# Luồng dữ liệu và thông báo

Các thao tác dưới đây cập nhật SQLite thật. Quyết định và thông báo được ghi trong cùng transaction; nếu thao tác lỗi thì cả hai cùng rollback.

| Thao tác | Dữ liệu thay đổi | Người nhận thông báo |
| --- | --- | --- |
| Gửi yêu cầu đổi ca | Yêu cầu pending | Người được đề nghị đổi ca |
| Người nhận đồng ý | counterpart_status=accepted, chờ duyệt | Người gửi và người có quyền duyệt, trừ hai người tham gia |
| Người nhận từ chối | Yêu cầu rejected | Người gửi |
| Admin/Quản lý duyệt đổi ca | approved, đổi chủ hai phân ca nguyên tử | Hai người tham gia |
| Admin/Quản lý từ chối đổi ca | rejected, giữ nguyên phân ca | Hai người tham gia |
| Duyệt/từ chối báo cáo đóng ca | approved/rejected; duyệt hoàn tất phân ca | Người gửi báo cáo |
| Duyệt/thu hồi thiết bị | approved_by/revoked_at | Nhân viên sở hữu thiết bị |
| Duyệt kỳ lương | Kỳ lương và phiếu lương approved | Các tài khoản có phiếu lương trong kỳ |

Người thực hiện không nhận thông báo của chính mình. Từ chối đóng ca cho phép nhân viên sửa và gửi lại. Đổi ca đã xử lý không thể duyệt lại. Người tham gia không được tự duyệt đổi ca/đóng ca/thiết bị của mình.

Màn hình chính có nút chuông **Thông báo**. Mở lại trang hoặc kéo để tải trạng thái mới; chạm thông báo để đánh dấu đã đọc. Truy vấn luôn lọc theo user_id đang đăng nhập; tài khoản khác không thể đọc hoặc đánh dấu hộ.

SQLite là database riêng trên từng thiết bị. Để thử luồng hiện tại, dùng cùng máy ảo: đăng nhập Nhân viên thao tác → đăng xuất → Admin xử lý → đăng xuất → Nhân viên xem lại trạng thái và thông báo. Hai máy riêng không tự đồng bộ và hiện chưa có push notification. File database trong project là asset ban đầu; thao tác runtime lưu trong bản SQLite riêng của app.

Phạm vi kiểm tra này là các luồng duyệt đã có API/giao diện nêu trong bảng. Bảng nghỉ phép và điều chỉnh công có dữ liệu mẫu nhưng chưa có luồng gửi/duyệt hoàn chỉnh trong giao diện; không xem các dòng seed là bằng chứng chức năng đã hoàn tất.

Kiểm thử ở `test/workflow_notifications_test.dart` dùng SQLite thật, đối chiếu trạng thái nhân viên, thông báo đúng người, quyền đánh dấu đã đọc, lịch không đổi khi bị từ chối, và chặn xử lý lặp. Các test nghiệp vụ hiện có kiểm tra chuyển phân ca và hoàn tất đóng ca.
