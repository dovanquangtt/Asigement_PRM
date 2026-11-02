# Schedule API (`/api/schedule`)

All endpoints need a bearer token. Permissions are checked against the database on every call.
Errors: `{ "message": "<Vietnamese text>" }` with 400/403/404/409. Times are ISO-8601 with offset.

| Method & path | Body / params | Permission | Result |
| --- | --- | --- | --- |
| GET `/branches` | | employees.manage | branches |
| GET `/shifts` | | shifts.manage (all) or schedule.self (own) | roster rows + `branch_name` |
| GET `/shifts/all` | | shifts.manage | shifts + `assigned_count` |
| GET `/shifts/overview?branchId=` | | shifts.manage | shifts + `assigned_count`, `assigned_staff_names` |
| POST `/shifts` | `{branchId,start,end,requiredStaff?,note?}` | shifts.manage | 201 `{id}` |
| GET `/shifts/{id}` | | shifts.manage, or schedule.self if assigned | shift + `roster[]` |
| GET `/shifts/{id}/eligible-employees` | | shifts.manage | employees + `is_available`, `is_already_assigned`, `conflict_reason` |
| POST `/shifts/{id}/assignments` | `{employeeId}` | shifts.manage | 204 |
| DELETE `/shifts/{id}/assignments/{employeeId}` | | shifts.manage | 204 |
| POST `/shifts/{id}/cancel` | | shifts.manage | 204 |
| GET `/my-schedule?employeeId=` | `employeeId` only honoured for managers | schedule.self / shifts.manage | schedule rows |
| GET `/leave-types` | | schedule.self | leave types |
| GET `/leave-requests` | | schedule.self | own leave requests |
| POST `/leave-requests` | `{leaveTypeId,start,end,reason}` | schedule.self | 201 |
| GET `/assignments/{id}/swap-options` | | swaps.self | candidate assignments |
| GET `/swaps` | | swaps.review (all) or swaps.self (own/targeted) | swap requests |
| POST `/swaps` | `{fromAssignmentId,toAssignmentId,reason}` | swaps.self | 201 `{id}` |
| POST `/swaps/{id}/respond` | `{accept}` (counterpart only) | swaps.self | 204 |
| POST `/swaps/{id}/review` | `{accept}` (non-involved reviewer) | swaps.review | 204 |

Notes: the Dart code had no leave review/approval workflow, so none is exposed here.

## Accept / reject assigned shifts and per-employee shift table

`assignShift` now creates (or re-activates) the assignment with `response_status = 'pending'`; the employee is notified
("Bạn có ca làm mới", body ends with "Hãy chấp nhận hoặc từ chối."). Older assignments stay `accepted` (migration
`V21__shift_assignment_response.sql`: `response_status` pending|accepted|rejected, `responded_at`, `response_note`).
A pending assignment can still check in; accepting is a confirmation, not a gate.

- `POST /api/schedule/assignments/{id}/respond` body `{accept: boolean, note: string|null}` → 204. `schedule.self`, the
  assignment must belong to the caller (else 403 'Phân ca không thuộc bạn.'), be `assigned` + `pending` on a `scheduled`
  shift (else 400 'Ca đã được phản hồi hoặc không còn hiệu lực.'), start in the future and have no attendance events (else
  400 'Không thể phản hồi ca đã bắt đầu hoặc đã có chấm công.'). Reject needs a note (400 'Nhập lý do từ chối ca.'): it sets
  `response_status = 'rejected'`, `assignment status = 'cancelled'` (slot freed). Audit `shift.accept` / `shift.reject`;
  notifies the assigner and the admins / managers of the branch ('Nhân viên chấp nhận ca' / 'Nhân viên từ chối ca').
- `GET /api/schedule/employees` → `[{id, full_name, employee_code, branch_id, branch_name}]` (`shifts.manage`; admin all,
  manager own branch).
- `GET /api/schedule/employees/{employeeId}/shifts?from&to` (`shifts.manage`; manager only same branch, else 403
  'Chỉ được xử lý chấm công trong chi nhánh của mình.'; defaults = current month; max 93 days → 400 'Khoảng ngày không hợp lệ.') →
  `{employee:{id,full_name,employee_code}, from, to, summary:{total,pending,accepted,rejected}, rows:[{assignment_id, shift_id,
  starts_at, ends_at, branch_id, branch_name, shift_status, assignment_status, response_status, responded_at, response_note,
  assigned_by_name, assigned_at, check_in_at, check_out_at, sheet_status}]}` ordered by shift start. Rejected assignments are
  included (`sheet_status` null); assignments removed by a manager (unassign / shift cancel) are not.
- `my-schedule`, shift detail roster and `GET /api/employees/me/shifts` (`responseStatus`, `responseNote`) expose the response.
