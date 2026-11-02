# API: lương, sao, đóng ca, liên kết tài khoản

Tất cả endpoint cần `Authorization: Bearer <accessToken>`. Quyền luôn được kiểm tra lại từ database.
Lỗi trả `{ "message": "<tiếng Việt>" }` với 400 (dữ liệu/nghiệp vụ), 403 (không có quyền), 404, 409.
Dòng trả về giữ nguyên tên cột snake_case như bản SQLite; body request dùng camelCase.

## Lương — `/api/payroll`

| Method & path | Quyền | Body / kết quả |
| --- | --- | --- |
| `GET /periods` | `payslips.self` | danh sách kỳ + `overtime_multiplier` |
| `POST /periods` | `payroll.manage` | `{code, startsOn, endsOn, overtimeMultiplier}` (>= 1) → 201 `{id}` |
| `POST /contracts` | `employees.manage` | `{employeeId, contractNumber, monthlySalary, standardMinutes, startsOn}` → 201 |
| `GET /payslips` | `payroll.manage` (tất cả) hoặc `payslips.self` (của mình) | danh sách phiếu kèm `net_pay_vnd`, `period_code` |
| `GET /payslips/{id}` | như trên | phiếu + `items`, `checks`, `checks_current` |
| `POST /payslips/{id}/items` | `payroll.manage` | `{code, name, type, amount}`; type: allowance/bonus/deduction/tax/insurance. Xóa các bước kiểm tra, buộc tính lại |
| `POST /periods/{id}/calculate` | `payroll.manage` hoặc `payslips.self` | body tùy chọn `{employeeId}`. Quản lý không gửi `employeeId` = tính toàn kỳ (6 bước, kỳ chuyển `calculating`); nhân viên chỉ tính phiếu của mình (trả thêm `payslip_id`) |
| `POST /periods/{id}/approve` | `payroll.manage` | duyệt khi đủ 6 bước, danh sách nhân viên active khớp và hash nguồn dữ liệu còn khớp; thông báo cho nhân viên |

Công thức: đơn giá/phút = `hourly_rate_vnd/60` (hourly) hoặc `base_salary_vnd/standard_minutes_per_month`;
lương thường = `round(regular × đơn giá)`; tăng ca = `round(overtime × đơn giá × hệ số)`.
`regular = worked − overtime − overtime_requested` khi `overtime_status` là `PENDING`/`REJECTED`.

## Sao — `/api/stars`

- `GET /` — `stars.award`: mọi nhân viên; `stars.self`: chỉ của mình (`v_employee_stars`).
- `POST /` — `stars.award`, `{employeeId, delta, reason}` → 201; không tự tặng sao, `delta` ≠ 0.

## Đóng ca — `/api/closures`

- `GET /` — `closures.review` (tất cả) hoặc `closures.self`; mỗi dòng có `photos`.
- `POST /` — `closures.self`, `{assignmentId, note, photoUrl}` → 201 `{id}`. Cần đã check-out; gửi lại được khi bị từ chối.
- `POST /{id}/review` — `closures.review`, `{approve}`. Không tự duyệt; duyệt xong phân ca `completed`, ca `closed` khi hết phân ca chưa hoàn tất; thông báo người gửi.

## Tài khoản — `/api/accounts`

- `PUT /users/{userId}/email` — `users.manage`, `{email}`; đặt lại `google_subject` về null.
- `GET /unlinked` — `employees.manage`; tài khoản active chưa gắn hồ sơ nhân viên.
- `PUT /employees/{employeeId}/user` — `employees.manage`, `{userId}`.

## Khác biệt so với Flutter

- `photoUrl` là chuỗi URL/đường dẫn; server không đọc file cục bộ nên bỏ bước kiểm tra JPEG/PNG.
- Hash nguồn lương (SHA-256 trên JSON chuẩn hóa) chỉ nhất quán trong ứng dụng Java, không trùng byte với hash của Dart.
- Bản ghi không tìm thấy trả 404 với thông báo mới thay vì `StateError`.
- Stars nằm ở package `vn.anhemquan.prm.stars`.
- Cần cột `attendance_records.overtime_status` / `overtime_requested_minutes` (migration v6 của Flutter, chưa có trong V2):
  xem `docs/proposed-V4__attendance_overtime_columns.sql`.
