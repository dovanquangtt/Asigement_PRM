# API chấm công (attendance)

Mọi endpoint cần header `Authorization: Bearer <accessToken>`. Quyền luôn được đọc lại từ database.
Lỗi nghiệp vụ trả `{"message": "..."}` (400 dữ liệu/luật nghiệp vụ, 403 thiếu quyền hoặc sai chi nhánh,
404 không tìm thấy). Tên cột trả về giữ nguyên snake_case như bản SQLite; cờ 0/1 nay là boolean và thời gian
là ISO-8601 UTC. Ngày nghiệp vụ tính theo múi giờ `Asia/Ho_Chi_Minh`.

`Evidence` (không có cờ "được chấp nhận" — server tự đối chiếu):

```json
{ "deviceIdentifier": "...", "platform": "android", "collectedAt": "2026-10-27T03:00:00Z",
  "latitude": 10.77, "longitude": 106.70, "accuracy": 10, "ssid": "AnhEm", "bssid": "aa:bb:cc:dd:ee:ff", "mocked": false }
```

Thời điểm "bây giờ" luôn là giờ máy chủ (không nhận từ client).

## Nhân viên (`attendance.self`)

| Method & path | Body | Kết quả |
| --- | --- | --- |
| GET `/api/attendance/assignments/{id}/context` | | ca + cấu hình chi nhánh |
| POST `/api/attendance/assignments/{id}/inspect` | `{evidence}` | kết quả kiểm tra (không ghi) |
| POST `/api/attendance/assignments/{id}/record` | `{type: check_in\|check_out, evidence}` | `{id, accepted, message}`; lần bị từ chối vẫn được lưu |
| POST `/api/attendance/assignments/{id}/submit` | `{type, evidence, selectedDeviceId?, collectionIssues?[]}` | `{id}`; có cảnh báo → `pending_review` và báo reviewer |
| GET `/api/attendance/history` | | lịch sử sự kiện (reviewer: theo phạm vi chi nhánh) |
| POST `/api/devices` | `{deviceIdentifier, platform}` | đăng ký thiết bị |
| GET `/api/devices/mine` | | thiết bị chưa bị thu hồi của mình |
| POST `/api/attendance/assignments/{id}/adjustments` | `{checkIn?, checkOut?, reason, evidencePath?}` | `{id}` yêu cầu bổ sung/sửa công |
| GET `/api/attendance/management?self=true&date=YYYY-MM-DD` | | bảng công cá nhân trong ngày |

## Quản lý / Admin (`attendance.review`, Quản lý bị giới hạn theo chi nhánh của mình)

| Method & path | Body | Kết quả |
| --- | --- | --- |
| GET `/api/attendance/submissions` | | điểm danh ngoại lệ (chờ duyệt lên đầu) |
| POST `/api/attendance/submissions/{eventId}/review` | `{approve, note}` | duyệt/từ chối; cần lý do khi từ chối hoặc có cảnh báo |
| GET `/api/devices` | | thiết bị trong phạm vi |
| POST `/api/devices/{id}/approve`, `/revoke` | | duyệt/thu hồi (không tự duyệt thiết bị của mình) |
| GET `/api/attendance/management?date=YYYY-MM-DD` | | tổng quan ngày: `employees, checked_in, late, pending, rows[]` |
| GET `/api/attendance/assignments/{id}/detail` | | `shift, record, events, adjustments, audit, can_review` (nhân viên xem được ca của chính mình) |
| POST `/api/attendance/adjustments/{id}/review` | `{approve, note}` | duyệt/từ chối điều chỉnh (không tự duyệt, chống dữ liệu cũ) |
| POST `/api/attendance/assignments/{id}/overtime/review` | `{approve, note}` | xác nhận tăng ca đang `PENDING` |
| POST `/api/attendance/days/close` | `{date, note?}` | chốt công ngày (khóa `attendance_records`) |
| GET `/api/attendance/notifications/{entity}/{id}/assignment` | | tìm ca từ thông báo (`attendance_events`, `attendance_records`, `attendance_adjustment_requests`) |
| PUT `/api/branches/{id}/attendance-config` | `{latitude, longitude, radiusM, ssid, bssid, requireOvertimeApproval?}` | cần `employees.manage`; chỉ Admin được đặt `requireOvertimeApproval` |

## Khác biệt so với bản Flutter

- `evidencePath` của yêu cầu điều chỉnh chỉ là chuỗi tham chiếu (URL/khóa lưu trữ); server không kiểm tra file cục bộ.
- Migration mới `V20__attendance_extensions.sql` bổ sung các cột của SQLite v5/v6 (submitted_by, checks_snapshot,
  overtime_*, locked_*, require_overtime_approval, before_json…) mà `V2` chưa có.
- Thời gian lưu `TIMESTAMPTZ` (cắt đến giây); `before_json` lưu thời gian dạng ISO-8601.

## Bảng điểm danh theo nhân viên, sửa và hủy công trực tiếp

Dữ liệu trả về giữ tên cột snake_case. Ngày tính theo giờ Việt Nam (UTC+7).

### `GET /api/attendance/sheet?employeeId=&from=yyyy-MM-dd&to=yyyy-MM-dd`
Bảng công theo khoảng ngày. `from`/`to` mặc định là đầu tháng đến hôm nay; khoảng phải `from <= to` và tối đa 93 ngày, nếu không trả 400 `Khoảng ngày không hợp lệ.`
- **Người duyệt** (`attendance.review`): Admin xem mọi chi nhánh, Quản lý chỉ chi nhánh của mình. `employeeId` tùy chọn (bỏ trống = mọi nhân viên trong phạm vi). Nhân viên ngoài chi nhánh: 403 `Chỉ được xử lý chấm công trong chi nhánh của mình.`; không tồn tại: 404.
- **Nhân viên** (`attendance.self`): luôn là bảng của chính mình, chỉ xem. `employeeId` khác mình: 403.

Phản hồi: `{from, to, employee, rows, summary}`.
- `rows[]`: một dòng cho mỗi phân ca chưa hủy, sắp theo giờ bắt đầu rồi tên: `assignment_id, employee_id, user_id, full_name, employee_code, shift_id, branch_id, branch_name, starts_at, ends_at, attendance_id, check_in_at, check_out_at, worked_minutes, late_minutes, overtime_minutes, overtime_status, arrival_status, record_status, attendance_state, locked_at, accepted_events, pending_events, rejected_events, last_rejection_reason, sheet_status`.
- `sheet_status` (khớp đầu tiên): `VOIDED` (đã hủy công), `SUCCESS` (có giờ vào và ra), `PENDING_REVIEW` (có điểm danh chờ duyệt), `IN_PROGRESS` / `MISSING_CHECK_OUT` (đã vào ca, ca chưa/đã kết thúc), `REJECTED` (chưa có giờ vào, có lần điểm danh bị từ chối), `MISSING_CHECK_IN` (ca đã kết thúc, chưa có giờ vào), `NOT_STARTED`.
- `summary`: `total, success, pending_review, rejected, missing, voided, worked_minutes, late_count`.

### `GET /api/attendance/sheet/employees`
Người duyệt: nhân viên đang làm trong phạm vi (`id, full_name, employee_code, branch_id`), sắp theo tên. Nhân viên: chỉ chính mình.

### `POST /api/attendance/assignments/{id}/admin-edit`
Body `{checkIn?, checkOut?, reason}` (ISO instant; thiếu một giờ = giữ giờ hiện có). Cần `attendance.review` và đúng chi nhánh; không tự sửa công của mình (403); ca/phân ca chưa hủy; bảng công/kỳ lương chưa chốt. Lý do bắt buộc (`Nhập lý do chỉnh công.`) và phải có ít nhất một giờ. Đặt `status = adjusted`, tính lại phút làm/đi muộn/tăng ca (giờ ra phải từ giờ vào), từ chối các lần điểm danh đang chờ duyệt (`Đã chỉnh công trực tiếp: <lý do>`), hủy yêu cầu điều chỉnh đang chờ, ghi audit `attendance.admin_edit` (trước/sau/lý do) và thông báo cho nhân viên "Giờ công đã được chỉnh". Sửa một công đã bị hủy sẽ khôi phục nó. Trả về dòng bảng công đã cập nhật.

### `POST /api/attendance/assignments/{id}/void`
Body `{reason}` (`Nhập lý do hủy công.`). Cùng điều kiện như trên. Xóa giờ vào/ra và mọi số phút, `status = absent`, `attendance_state = VOIDED`; các lần điểm danh đã duyệt hoặc đang chờ bị đánh dấu `rejected` (`Đã hủy công: <lý do>`); yêu cầu điều chỉnh đang chờ bị hủy; audit `attendance.void`; thông báo "Công bị hủy". Công bị hủy không được tính lương (không còn giờ ra).

Khi công đang `VOIDED`, `POST .../record`, `POST .../submit` và `POST .../adjustments` của nhân viên trả 400 `Công đã bị hủy. Hãy liên hệ quản lý.` cho đến khi người duyệt sửa lại công.
