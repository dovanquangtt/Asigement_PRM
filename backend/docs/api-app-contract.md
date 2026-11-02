# API contract for the Flutter attendance / manager / admin screens

Single source of truth shared by the Spring Boot controllers (`vn.anhemquan.prm.app`) and the Flutter
client (`lib/features/**`). All bodies are JSON, **camelCase**, timestamps are ISO-8601 UTC instants
(`2026-10-29T01:00:00Z`), dates are `yyyy-MM-dd` (business day = UTC+7). Every endpoint needs
`Authorization: Bearer <accessToken>` (from `/api/auth/login` or `/api/auth/google`) except those two.

Errors (all endpoints): HTTP 4xx/5xx with `{"code": "SOME_CODE", "message": "<Vietnamese, user-safe>"}`.
Codes: `VALIDATION_ERROR`(400) `BUSINESS_RULE`(400) `UNAUTHORIZED`(401) `FORBIDDEN`(403) `NOT_FOUND`(404)
`CONFLICT`(409) `DEVICE_NOT_REGISTERED`(403) `DEVICE_REVOKED`(403) `NO_SHIFT`(400) `DUPLICATE_ATTENDANCE`(409)
`ATTENDANCE_VOIDED`(400) `ATTENDANCE_LOCKED`(400). Unknown failures: `INTERNAL_ERROR`(500) without details.

Pagination: `?page=0&size=20` (size ≤ 100) → `{"items":[...],"page":0,"size":20,"totalItems":57,"totalPages":3}`.

## Shared shapes

```
Employee      {id, employeeCode, fullName, position|null, branchId, branchName, avatarUrl|null}
ShiftRef      {assignmentId, shiftId, startsAt, endsAt, branchId, branchName}
Verification  {gps: "VERIFIED"|"FAILED"|"UNKNOWN", device: same, wifi: same,
               distanceMeters: number|null, radiusMeters: number|null, warnings: [string]}
AttendanceInfo{checkInAt|null, checkOutAt|null, status: SheetStatus, arrivalStatus: "ON_TIME"|"LATE"|null,
               lateMinutes, workedMinutes, breakMinutes, overtimeMinutes}
SheetStatus   SUCCESS | PENDING_REVIEW | REJECTED | IN_PROGRESS | MISSING_CHECK_IN | MISSING_CHECK_OUT | NOT_STARTED | VOIDED
AttendanceState NO_SHIFT | NOT_CHECKED_IN | WORKING | COMPLETED | ATTENDANCE_EXCEPTION
```
`attendanceId` everywhere means the **shift assignment id** (one attendance row per assignment; a record may
not exist yet).

## Employee

`GET /api/employees/me` → `Employee`  
`GET /api/employees/me/shifts?from&to` → `[ShiftRef + {status}]`

`GET /api/attendance/me/today` →
```
{ date, serverTime, employee: Employee,
  state: AttendanceState,
  shift: ShiftRef|null,            // the relevant shift: working one, else next unfinished, else last of the day
  shifts: [ShiftRef],              // all of today's shifts
  attendance: AttendanceInfo|null,
  verification: Verification|null, // of the latest event
  pendingExceptions: [{eventType: "CHECK_IN"|"CHECK_OUT", message}],
  canCheckIn: bool, canCheckOut: bool }
```
State rules: no shift → NO_SHIFT; record VOIDED or no check-in → NOT_CHECKED_IN (canCheckIn true only if shift not
ended+12h / not locked / not voided); check-in present, no check-out → WORKING; both → COMPLETED; any
pending_review event (and the matching time still empty) → ATTENDANCE_EXCEPTION.

`POST /api/attendance/check-in` and `POST /api/attendance/check-out` body:
```
{ assignmentId: int|null,          // null → server picks the relevant shift of today
  deviceIdentifier: string, devicePlatform: "android", deviceModel: string|null,
  latitude: number, longitude: number, accuracyMeters: number|null,
  locationCollectedAt: instant, mockLocation: bool,
  wifiSsid: string|null, wifiBssid: string|null }
```
→ `201`
```
{ attendanceId, eventId, type: "CHECK_IN"|"CHECK_OUT",
  result: "ACCEPTED"|"PENDING_REVIEW",     // PENDING_REVIEW = saved as exception for manager review
  serverTime,                               // official time, taken from the server clock
  employee: Employee, branch: {id,name}, shift: ShiftRef,
  verification: Verification, attendance: AttendanceInfo,
  status: AttendanceState, message }
```
Uses the existing evidence rules (device registered+approved, GPS radius/accuracy/freshness, Wi-Fi when the
branch requires it). Rule failures that the old flow stored as exceptions stay exceptions (`PENDING_REVIEW`
with `verification.warnings`); hard failures are HTTP errors: no shift, device not registered/revoked,
duplicate (`DUPLICATE_ATTENDANCE`), voided, locked, invalid coordinates.

`GET /api/attendance/me/history?from&to&page&size` → page of
`{attendanceId, date, shift: ShiftRef, checkInAt, checkOutAt, status: SheetStatus, late: bool, lateMinutes, workedMinutes}`  
`GET /api/attendance/me/{attendanceId}` (own only, else 404) →
`{item: <history item>, employee, verification|null, events: [{eventId, type, occurredAt, result: "ACCEPTED"|"PENDING_REVIEW"|"REJECTED", latitude|null, longitude|null, accuracyMeters|null, distanceMeters|null, verification, rejectionReason|null}], exceptions: [string]}`

Devices (employee): existing `POST /api/devices`, `GET /api/devices/mine`.

## Manager (`attendance.review`, branch-scoped; admin sees all)

`GET /api/manager/attendance/summary?date&branchId` →
`{date, branchId|null, totalEmployees, checkedIn, working, completed, late, notCheckedIn, exceptions}`
(`notCheckedIn` = shifts of the day already started (starts_at ≤ now) with no check-in; never counted before the shift starts.)

`GET /api/manager/attendance?date&branchId&shiftId&status&q&page&size` → page of
`{attendanceId, employee: Employee, shift: ShiftRef, checkInAt, checkOutAt, status: SheetStatus, late: bool,
  lateMinutes, workedMinutes, verification: {gps, device}}`  (`q` matches name/code; `status` = SheetStatus)  
`GET /api/manager/attendance/{attendanceId}` → manager detail = employee-detail shape + `employee`, `shift`, `attendance`, `auditLog: [{action, actorName, at, detail}]`  
`GET /api/manager/attendance/exceptions?date&branchId&page&size` → page of the list item above restricted to rows with
pending exceptions / pending adjustment / pending overtime, plus `reason: string`.

Outside the manager's branch → 403 `FORBIDDEN`. Existing edit/void/review endpoints under `/api/attendance/**` stay.

## Admin (`users.manage`/admin role)

Same three attendance endpoints under `/api/admin/attendance` (`summary`, list, `{id}`), branchId optional, summary adds
`totalBranches, totalShifts`.  
`GET /api/admin/devices?status&q&page&size` → page of
`{id, employeeId, employeeName, employeeCode, deviceIdentifierMasked, platform, registeredAt, status: "PENDING"|"APPROVED"|"REVOKED", approvedByName|null, revokedAt|null}`  
`POST /api/admin/devices/{id}/revoke` `{reason}` → 204 (audit + notify employee). `POST /api/admin/devices/{id}/approve` → 204.  
`GET /api/admin/reports/attendance?from&to&groupBy=employee|branch|date&branchId` →
`{groupBy, from, to, rows: [{key, label, totalShifts, success, late, missing, exceptions, voided, workedMinutes}]}`
Excel/PDF export is **not** implemented.

## Implementation notes (backend, package `vn.anhemquan.prm.app`)

Implemented as written above; the files are `EmployeeAppController/Service`, `ReviewAppController/Service`,
`AppRows` (one query per assignment + DTO mapping), `AppDto`. Tests: `AppApiIntegrationTest` (compiled, **not
executed** from the authoring session — run `mvn test` against MySQL).

Assumptions / behaviour worth knowing:
- Check-in/out reuse `AttendanceService.submit`: server clock (`AttendanceClock`), device/GPS/Wi-Fi/freshness rules
  and notifications are unchanged. **Wi-Fi is still required whenever the branch has `require_wifi`** (default true):
  the app must send `wifiSsid`/`wifiBssid`, otherwise the punch becomes `PENDING_REVIEW` with a warning.
- Hard failures (HTTP errors): no shift (`NO_SHIFT`), device not registered / belongs to someone else
  (`DEVICE_NOT_REGISTERED`), revoked device (`DEVICE_REVOKED`), duplicate event or time already recorded
  (`DUPLICATE_ATTENDANCE`, 409), voided/locked records, bad coordinates (`VALIDATION_ERROR`). A registered but not
  yet approved device, GPS outside the radius/low accuracy, wrong Wi-Fi, stale evidence or an out-of-window time
  are **not** errors: the event is stored `pending_review` and the response says `result: PENDING_REVIEW`.
- `assignmentId` null: check-in picks today's first not-yet-checked-in shift that has not ended; check-out picks the
  shift being worked; otherwise the "relevant" shift (see below). Today = server clock in UTC+7; a shift still
  being worked that started before midnight is included.
- Relevant shift = the one being worked, else the first unfinished shift that has not ended, else the last shift.
- `ATTENDANCE_EXCEPTION` = a `pending_review` check-in with no check-in time yet, or a pending check-out with no
  check-out time. `canCheckIn/Out` also require the usual time window and that the record is not locked/voided.
- `verification.gps|device|wifi` come from the latest event: `VERIFIED` when the stored flag is true; `UNKNOWN` when
  the event has no coordinates / no BSSID (or there is no event); otherwise `FAILED`. `distanceMeters` comes from the
  event's `checks_snapshot` (written by `submit`), falling back to a haversine of the stored coordinates vs the
  branch for events written by the older `/record` endpoint.
- Lists are filtered in memory after one SQL query for the day/range and then paged (`size` ≤ 100); the `status`
  filter uses the SheetStatus computed with the server clock. Ranges are limited to 366 days (reports, history,
  shifts); invalid values → 400 `VALIDATION_ERROR`.
- Manager summary `notCheckedIn` counts shifts that started (starts_at ≤ now), have no check-in, are not voided and
  have no pending check-in; pending submissions are counted in `exceptions` (together with pending adjustment
  requests and pending overtime approvals). Admin `totalShifts` counts all non-cancelled shifts of the day (also
  those without assignments), `totalEmployees` counts active employees.
- Manager endpoints use permission `attendance.review` with branch scope (Admin sees all); admin endpoints require
  `users.manage`. A manager asking for another branch gets 403 `FORBIDDEN`.
- `auditLog.detail` is the raw `after_json` of `audit_logs`. Device revoke reason is optional (stored in the audit
  entry); revoke/approve reuse `AttendanceService.reviewDevice` (audit + employee notification).
- Error bodies are `{code, message}` everywhere (`GlobalExceptionHandler`); unexpected exceptions → 500
  `INTERNAL_ERROR` with a generic message. `ApiException.of(status, code, message)` creates coded errors.
- Not implemented: Excel/PDF export, refresh tokens, avatar upload (`avatarUrl` is always null).

### Update: shift response in `GET /api/employees/me/shifts`
Each item additionally has `responseStatus: "pending"|"accepted"|"rejected"` and `responseNote: string|null`
(rejected assignments are not returned; respond with `POST /api/schedule/assignments/{assignmentId}/respond`).
