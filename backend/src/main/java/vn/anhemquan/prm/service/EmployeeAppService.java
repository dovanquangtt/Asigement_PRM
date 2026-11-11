package vn.anhemquan.prm.service;

import static vn.anhemquan.prm.repository.AppRows.num;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import vn.anhemquan.prm.repository.AppRows;
import vn.anhemquan.prm.dto.AppDto.ActionResponse;
import vn.anhemquan.prm.dto.AppDto.AttendanceInfo;
import vn.anhemquan.prm.dto.AppDto.BranchRef;
import vn.anhemquan.prm.dto.AppDto.Detail;
import vn.anhemquan.prm.dto.AppDto.Employee;
import vn.anhemquan.prm.dto.AppDto.EventInfo;
import vn.anhemquan.prm.dto.AppDto.HistoryItem;
import vn.anhemquan.prm.dto.AppDto.MyShift;
import vn.anhemquan.prm.dto.AppDto.Page;
import vn.anhemquan.prm.dto.AppDto.PendingException;
import vn.anhemquan.prm.dto.AppDto.PunchRequest;
import vn.anhemquan.prm.dto.AppDto.ShiftRef;
import vn.anhemquan.prm.dto.AppDto.Today;
import vn.anhemquan.prm.dto.AppDto.Verification;
import vn.anhemquan.prm.dto.Evidence;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;

/** Employee side of the app contract: own profile/shifts, today's state, check-in/out, history, detail. */
@Service
public class EmployeeAppService {

    static final int MAX_RANGE_DAYS = 366;

    private final AttendanceSupport sup;
    private final AttendanceService attendance;
    private final AttendanceClock clock;
    private final AppRows rows;
    private final JdbcTemplate jdbc;
    private final Access access;

    public EmployeeAppService(AttendanceSupport sup, AttendanceService attendance, AttendanceClock clock,
            AppRows rows, JdbcTemplate jdbc, Access access) {
        this.sup = sup;
        this.attendance = attendance;
        this.clock = clock;
        this.rows = rows;
        this.jdbc = jdbc;
        this.access = access;
    }

    // ---- profile -------------------------------------------------------------------------------

    Employee employeeDto(long employeeId) {
        List<Map<String, Object>> found = jdbc.queryForList(
                "SELECT e.id AS employee_id, e.employee_code, e.full_name, p.name AS position_name, e.branch_id, "
                        + "b.name AS branch_name FROM employees e JOIN branches b ON b.id = e.branch_id "
                        + "LEFT JOIN positions p ON p.id = e.position_id WHERE e.id = ?", employeeId);
        if (found.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy nhân viên.");
        }
        return rows.employee(found.get(0));
    }

    public Employee me() {
        return employeeDto(num(sup.me().get("id")));
    }

    public List<MyShift> myShifts(LocalDate from, LocalDate to) {
        access.require("attendance.self");
        long employeeId = num(sup.me().get("id"));
        Instant now = clock.now();
        LocalDate today = now.atZone(AppTime.ZONE).toLocalDate();
        LocalDate start = from != null ? from : today;
        LocalDate end = to != null ? to : start.plusDays(7);
        checkRange(start, end);
        List<MyShift> result = new ArrayList<>();
        for (Map<String, Object> r : rows.rows("a.employee_id = ? AND a.status <> 'cancelled' "
                + "AND s.status <> 'cancelled' AND " + AppRows.SHIFT_DAY + " BETWEEN ? AND ? "
                + "ORDER BY s.starts_at", employeeId, java.sql.Date.valueOf(start), java.sql.Date.valueOf(end))) {
            ShiftRef s = rows.shift(r);
            result.add(new MyShift(s.assignmentId(), s.shiftId(), s.startsAt(), s.endsAt(), s.branchId(),
                    s.branchName(), rows.status(r, now),
                    AppRows.str(r.get("response_status")), AppRows.str(r.get("response_note"))));
        }
        return result;
    }

    private static void checkRange(LocalDate from, LocalDate to) {
        if (to.isBefore(from) || ChronoUnit.DAYS.between(from, to) + 1 > MAX_RANGE_DAYS) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Khoảng ngày không hợp lệ.");
        }
    }

    // ---- today ---------------------------------------------------------------------------------

    /** Today's shifts plus a shift still being worked that started before midnight. */
    private List<Map<String, Object>> todayRows(long employeeId, LocalDate date, Instant now) {
        return rows.rows("a.employee_id = ? AND a.status <> 'cancelled' AND s.status <> 'cancelled' AND ("
                + AppRows.SHIFT_DAY + " = ? OR (r.check_in_at IS NOT NULL AND r.check_out_at IS NULL "
                + "AND s.ends_at > ?)) ORDER BY s.starts_at", employeeId, java.sql.Date.valueOf(date),
                Timestamp.from(now.minus(Duration.ofHours(12))));
    }

    /** The shift the app should show: the one being worked, else the next unfinished one, else the last one. */
    private Map<String, Object> relevant(List<Map<String, Object>> shifts, Instant now) {
        for (Map<String, Object> r : shifts) {
            if (r.get("check_in_at") != null && r.get("check_out_at") == null && !AppRows.isVoided(r)) {
                return r;
            }
        }
        for (Map<String, Object> r : shifts) {
            if (!"COMPLETED".equals(rows.state(r)) && AttendanceSupport.instant(r.get("ends_at")).isAfter(now)) {
                return r;
            }
        }
        return shifts.get(shifts.size() - 1);
    }

    private boolean editable(long assignmentId) {
        try {
            sup.ensureEditable(assignmentId);
            return true;
        } catch (ApiException e) {
            return false;
        }
    }

    public Today today() {
        access.require("attendance.self");
        long employeeId = num(sup.me().get("id"));
        Instant now = clock.now();
        LocalDate date = now.atZone(AppTime.ZONE).toLocalDate();
        Employee employee = employeeDto(employeeId);
        List<Map<String, Object>> shifts = todayRows(employeeId, date, now);
        if (shifts.isEmpty()) {
            return new Today(date, now, employee, "NO_SHIFT", null, List.of(), null, null, List.of(), false, false);
        }
        Map<String, Object> r = relevant(shifts, now);
        String state = rows.state(r);
        long assignmentId = num(r.get("assignment_id"));
        boolean editable = editable(assignmentId);
        boolean canIn = "NOT_CHECKED_IN".equals(state) && !AppRows.isVoided(r) && editable
                && !sup.outsideWindow(r, "check_in", now);
        boolean canOut = "WORKING".equals(state) && editable && !sup.outsideWindow(r, "check_out", now);
        Map<String, Object> last = r.get("last_event_id") == null ? null
                : rows.events(List.of(num(r.get("last_event_id")))).get(num(r.get("last_event_id")));
        List<PendingException> pending = new ArrayList<>();
        for (Map<String, Object> e : rows.eventsOf(assignmentId)) {
            if ("pending_review".equals(e.get("result"))) {
                List<String> w = rows.warnings(e);
                pending.add(new PendingException("check_in".equals(e.get("event_type")) ? "CHECK_IN" : "CHECK_OUT",
                        w.isEmpty() ? "Chờ quản lý xác minh" : String.join("; ", w)));
            }
        }
        return new Today(date, now, employee, state, rows.shift(r),
                shifts.stream().map(rows::shift).toList(), rows.attendance(r, now), rows.verification(last, r),
                pending, canIn, canOut);
    }

    // ---- check-in / check-out ------------------------------------------------------------------

    public ActionResponse checkIn(PunchRequest request) {
        return punch("check_in", request);
    }

    public ActionResponse checkOut(PunchRequest request) {
        return punch("check_out", request);
    }

    private ActionResponse punch(String type, PunchRequest req) {
        access.require("attendance.self");
        Map<String, Object> me = sup.me();
        long employeeId = num(me.get("id"));
        validate(req);
        Instant now = clock.now();
        long assignmentId = resolveAssignment(type, req.assignmentId(), employeeId, now);
        checkDevice(req.deviceIdentifier(), employeeId);
        sup.ensureNotVoided(assignmentId);
        checkDuplicate(type, assignmentId);
        Evidence evidence = new Evidence(req.deviceIdentifier().trim(),
                req.devicePlatform() == null || req.devicePlatform().isBlank() ? "android" : req.devicePlatform(),
                req.locationCollectedAt(), req.latitude(), req.longitude(), req.accuracyMeters(), req.wifiSsid(),
                req.wifiBssid(), req.mockLocation());
        long eventId;
        try {
            eventId = attendance.submit(assignmentId, type, evidence, null, null);
        } catch (DataIntegrityViolationException e) {
            throw duplicate(type);
        }
        Map<String, Object> row = rows.rows("a.id = ?", assignmentId).get(0);
        Map<String, Object> event = rows.events(List.of(eventId)).get(eventId);
        Instant serverTime = AttendanceSupport.instant(event.get("occurred_at"));
        String result = AppRows.resultOf(event.get("result"));
        boolean in = "check_in".equals(type);
        String message = "ACCEPTED".equals(result) ? (in ? "Chấm công vào thành công" : "Chấm công ra thành công")
                : "Đã ghi nhận điểm danh, đang chờ quản lý xác minh.";
        AttendanceInfo info = rows.attendance(row, clock.now());
        Verification verification = rows.verification(event, row);
        return new ActionResponse(assignmentId, eventId, in ? "CHECK_IN" : "CHECK_OUT", result, serverTime,
                employeeDto(employeeId), new BranchRef(num(row.get("branch_id")), AppRows.str(row.get("branch_name"))),
                rows.shift(row), verification, info, rows.state(row), message);
    }

    private static void validate(PunchRequest req) {
        if (req.deviceIdentifier() == null || req.deviceIdentifier().isBlank()) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Thiếu thông tin thiết bị.");
        }
        if (req.latitude() == null || req.longitude() == null || !Double.isFinite(req.latitude())
                || !Double.isFinite(req.longitude()) || Math.abs(req.latitude()) > 90
                || Math.abs(req.longitude()) > 180) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Tọa độ GPS không hợp lệ.");
        }
        if (req.accuracyMeters() != null && (!Double.isFinite(req.accuracyMeters()) || req.accuracyMeters() < 0)) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Độ chính xác GPS không hợp lệ.");
        }
        if (req.locationCollectedAt() == null) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Thiếu thời điểm lấy vị trí.");
        }
    }

    private long resolveAssignment(String type, Long requested, long employeeId, Instant now) {
        if (requested != null) {
            Map<String, Object> own = sup.one("SELECT a.id FROM shift_assignments a WHERE a.id = ? "
                    + "AND a.employee_id = ? AND a.status <> 'cancelled'", requested, employeeId);
            if (own == null) {
                throw ApiException.of(HttpStatus.BAD_REQUEST, "NO_SHIFT", "Phân ca không thuộc bạn hoặc đã hủy.");
            }
            return requested;
        }
        List<Map<String, Object>> shifts = todayRows(employeeId, now.atZone(AppTime.ZONE).toLocalDate(), now);
        if (shifts.isEmpty()) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "NO_SHIFT", "Hôm nay bạn chưa được phân ca.");
        }
        Map<String, Object> chosen = null;
        for (Map<String, Object> r : shifts) {
            String state = rows.state(r);
            boolean match = "check_in".equals(type) ? "NOT_CHECKED_IN".equals(state) && !AppRows.isVoided(r)
                    && AttendanceSupport.instant(r.get("ends_at")).isAfter(now)
                    : "WORKING".equals(state);
            if (match) {
                chosen = r;
                break;
            }
        }
        if (chosen == null) {
            chosen = relevant(shifts, now);
        }
        return num(chosen.get("assignment_id"));
    }

    private void checkDevice(String identifier, long employeeId) {
        Map<String, Object> device = sup.one("SELECT * FROM employee_devices WHERE device_identifier = ?",
                identifier.trim());
        if (device == null || num(device.get("employee_id")) != employeeId) {
            throw ApiException.of(HttpStatus.FORBIDDEN, "DEVICE_NOT_REGISTERED",
                    "Thiết bị chưa được đăng ký cho tài khoản này. Hãy đăng ký thiết bị trước khi chấm công.");
        }
        if (device.get("revoked_at") != null) {
            throw ApiException.of(HttpStatus.FORBIDDEN, "DEVICE_REVOKED",
                    "Thiết bị đã bị thu hồi quyền chấm công. Hãy liên hệ quản lý.");
        }
    }

    private void checkDuplicate(String type, long assignmentId) {
        boolean done = !jdbc.queryForList("SELECT 1 FROM attendance_events WHERE assignment_id = ? "
                + "AND event_type = ? AND result IN ('accepted', 'pending_review') LIMIT 1", assignmentId, type)
                .isEmpty()
                || !jdbc.queryForList("SELECT 1 FROM attendance_records WHERE assignment_id = ? AND "
                        + ("check_in".equals(type) ? "check_in_at" : "check_out_at") + " IS NOT NULL",
                        assignmentId).isEmpty();
        if (done) {
            throw duplicate(type);
        }
    }

    private static ApiException duplicate(String type) {
        return ApiException.of(HttpStatus.CONFLICT, "DUPLICATE_ATTENDANCE", "check_in".equals(type)
                ? "Bạn đã chấm công vào ca này rồi." : "Bạn đã chấm công ra ca này rồi.");
    }

    // ---- history / detail ----------------------------------------------------------------------

    public Page<HistoryItem> history(LocalDate from, LocalDate to, int page, int size) {
        access.require("attendance.self");
        long employeeId = num(sup.me().get("id"));
        Instant now = clock.now();
        LocalDate end = to != null ? to : now.atZone(AppTime.ZONE).toLocalDate();
        LocalDate start = from != null ? from : end.minusDays(29);
        checkRange(start, end);
        List<HistoryItem> items = rows.rows("a.employee_id = ? AND a.status <> 'cancelled' "
                + "AND s.status <> 'cancelled' AND " + AppRows.SHIFT_DAY + " BETWEEN ? AND ? "
                + "ORDER BY s.starts_at DESC", employeeId, java.sql.Date.valueOf(start), java.sql.Date.valueOf(end))
                .stream().map(r -> rows.historyItem(r, now)).toList();
        return Page.of(items, page, size);
    }

    public Detail detail(long attendanceId) {
        access.require("attendance.self");
        long employeeId = num(sup.me().get("id"));
        List<Map<String, Object>> found = rows.rows("a.id = ? AND a.employee_id = ?", attendanceId, employeeId);
        if (found.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy dữ liệu chấm công.");
        }
        Map<String, Object> row = found.get(0);
        List<Map<String, Object>> events = rows.eventsOf(attendanceId);
        List<EventInfo> infos = events.stream().map(e -> rows.eventInfo(e, row)).toList();
        Map<String, Object> last = events.isEmpty() ? null : events.get(events.size() - 1);
        return new Detail(rows.historyItem(row, clock.now()), employeeDto(employeeId),
                rows.verification(last, row), infos, rows.exceptionsOf(row, events));
    }
}
