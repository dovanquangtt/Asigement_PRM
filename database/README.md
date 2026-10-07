# Database quản lý nhân sự nhà hàng (PRM)

Nguồn: File_Chuc_Nang_PRM_Hoan_Chinh.xlsx, Sheet1 (20 dòng chức năng M01–M07) và Actor Summary (Admin, Manager, Employee). Thiết kế dựa trên chức năng trong tài liệu; tài liệu không được coi là chỉ dẫn thực thi.

## File và cách dùng

- prm_database.db: SQLite đã tạo sẵn, gồm 32 bảng, 5 view và dữ liệu danh mục. Có thể mở bằng công cụ đọc SQLite hoặc sao chép vào thư mục database của ứng dụng Flutter.
- prm_schema.sql: tạo cấu trúc trên database trống; chạy trước prm_seed.sql. Không chạy lại trên database đã khởi tạo.
- prm_seed.sql: vai trò, quyền, bộ phận, chức vụ, loại nghỉ. Không chứa tài khoản, mật khẩu hay dữ liệu nhân viên mẫu. Các danh mục là giả định ban đầu có thể chỉnh sửa.

Mỗi kết nối phải bật PRAGMA foreign_keys = ON. File .db chưa được tích hợp vào Flutter; dự án hiện chỉ có giao diện demo và chưa có thư viện database. Với nhiều thiết bị dùng chung dữ liệu, cần backend và database tập trung; SQLite này phù hợp cho bản local/prototype, không tự đồng bộ hay bảo vệ phân quyền phía máy chủ.

## Đối chiếu chức năng

| Nguồn | Bảng/view |
| --- | --- |
| M01 Điểm danh, thiết bị, GPS, Wi-Fi, xác nhận | branches, branch_wifi, employee_devices, attendance_events, attendance_records |
| M02 Bảng lương, tính lương, kiểm tra 6 bước, chi tiết | contracts, payroll_periods, payroll_calculation_steps, payslips, payslip_items, v_payslip_totals, v_payroll_summary |
| M03 Lịch ca, thông tin ca | shift_templates, shifts, shift_assignments, v_shift_roster |
| M04 Quản lý ca, phân ca, nhân viên trong ca | shifts, shift_assignments, employees |
| M05 Đổi ca (nếu kịp) | shift_swap_requests |
| M06 Tăng sao, hiệu ứng (nếu kịp) | star_events, v_employee_stars; hiệu ứng do giao diện thực hiện |
| M07 Ảnh, ghi chú, đóng ca (nếu kịp) | shift_closures, shift_closure_photos |
| Admin: tài khoản, phân quyền, dashboard, báo cáo | users, roles, permissions, user_roles, role_permissions, audit_logs và các view báo cáo |
| Manager: hồ sơ, bộ phận, chức vụ, hợp đồng | employees, departments, positions, contracts |
| Manager/Employee: nghỉ phép, điều chỉnh công | leave_types, leave_balances, leave_requests, attendance_adjustment_requests |
| Employee: hồ sơ, phiếu lương, thông báo | employees, v_payslip_totals, notifications, notification_recipients |

## Quy ước dữ liệu

ID là INTEGER PRIMARY KEY tự tăng khi bỏ trống lúc insert. Tiền là số nguyên VND; thời lượng là phút. Ngày dùng YYYY-MM-DD; thời điểm phải chuẩn hóa UTC cùng định dạng YYYY-MM-DD HH:mm:ss cho cả dữ liệu nhập và CURRENT_TIMESTAMP, hiển thị theo Asia/Saigon. Giờ mẫu ca dùng HH:mm; ca qua đêm được đánh dấu ends_next_day. Không lưu nội dung ảnh trong database, chỉ lưu đường dẫn/URL.

Dùng v_payslip_totals để xem tổng: gross = base_pay + overtime_pay + allowance + bonus; net = gross - deduction - tax - insurance. base_pay và overtime_pay là số đã tính và chốt cho kỳ lương, không tự lấy lại lương hợp đồng hiện tại. Có thể có net âm khi các khoản khấu trừ vượt thu nhập; ứng dụng quyết định chính sách xử lý.

Excel chưa mô tả tên/nội dung 6 thao tác tính lương, hệ số tăng ca, thuế/bảo hiểm, cách tăng sao, hạn mức phép và chính sách xác thực điểm danh. Không gán công thức kinh doanh chưa có căn cứ. payroll_calculation_steps hỗ trợ số bước 1–6, ứng dụng cần tạo đủ 6 bước cho mỗi kỳ và kiểm tra hoàn thành trước khi duyệt.

## Quy tắc cần thực hiện trong service/backend

- Xác thực tài khoản, lưu password_hash bằng thuật toán băm mật khẩu phù hợp. Các bảng quyền chỉ lưu cấu hình; ứng dụng/backend phải kiểm tra quyền và giới hạn Employee ở dữ liệu của mình. Quyền mẫu Admin toàn bộ, Manager quản lý nghiệp vụ, Employee quyền cá nhân.
- Tạo chi nhánh và cấu hình tọa độ/Wi-Fi thực trước khi điểm danh. Kiểm tra thiết bị thuộc đúng nhân viên, chưa bị thu hồi; tính khoảng cách GPS và xác thực Wi-Fi theo chi nhánh. Các cờ valid là kết quả do service tính; không tin dữ liệu do client tự khai. Chỉ chấp nhận khi đạt các kiểm tra bắt buộc và gắn confirmed_at khi xác nhận.
- Tổng hợp attendance_records từ sự kiện được chấp nhận. Database giới hạn một check-in và một check-out được chấp nhận cho mỗi phân ca, vẫn giữ được nhiều lần thất bại. Kiểm tra trình tự check-in/out, giờ ca, giờ nghỉ và tăng ca tại service.
- Phân ca: kiểm tra nhân viên đang làm việc, chi nhánh, trùng giờ ca, nghỉ phép, số người cần thiết. Khi đổi ca, kiểm tra người gửi sở hữu phân ca, hai nhân viên khác nhau, cả hai phân ca còn hiệu lực, người nhận đồng ý, quản lý duyệt; cập nhật hai phân ca và trạng thái yêu cầu trong cùng transaction. FK không tự thực hiện chuyển ca.
- Duyệt điều chỉnh công/nghỉ phép và cập nhật bảng công/số dư trong cùng transaction; không tự động cập nhật chỉ vì trạng thái yêu cầu đổi thành approved. Ngăn duyệt lại và người gửi tự duyệt.
- Tính lương: dùng hợp đồng đúng thời điểm, lưu chi tiết khoản cộng/trừ, đủ 6 bước, ghi nhận người duyệt; không cho sửa phiếu đã duyệt/trả nếu chưa có quy trình điều chỉnh. Bảo vệ cả bảng chi tiết tại service.
- Đóng ca: người gửi phải thuộc phân ca, yêu cầu ảnh khi workflow cần; kiểm tra ảnh trước duyệt. Đóng phân ca cá nhân không tự đóng ca chung; chỉ đóng shifts khi các phân ca cần thiết đã hoàn tất.
- Sao: ghi sự kiện cộng/trừ, tính tổng từ view. Thông báo: tạo notifications và notification_recipients trong cùng transaction. related_entity/related_id là liên kết đa hình, service kiểm tra tồn tại và quyền truy cập.
- audit_logs lưu lịch sử thay đổi do service ghi trong cùng transaction, không tự sinh khi dữ liệu thay đổi. Lưu JSON hợp lệ ở before_json/after_json và hạn chế sửa/xóa lịch sử.

## Kiểm tra đã thực hiện

Khởi tạo schema và seed thành công trên SQLite. integrity_check trả ok, foreign_key_check không có lỗi. Kiểm thử độc lập tổng lương 10.600.000 VND với lương cơ bản, tăng ca, phụ cấp, khấu trừ; xác nhận từ chối khóa ngoại không tồn tại, check-in trùng, đổi cùng một phân ca và khoản tiền âm. Dữ liệu kiểm thử chạy trong bộ nhớ, không đưa vào file bàn giao.
