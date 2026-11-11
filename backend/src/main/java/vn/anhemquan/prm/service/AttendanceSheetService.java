package vn.anhemquan.prm.service;

import static vn.anhemquan.prm.service.AttendanceSupport.instant;
import static vn.anhemquan.prm.service.AttendanceSupport.ts;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;
import vn.anhemquan.prm.repository.Db;

/**
 * Per-employee attendance sheet (date range) for employees (own sheet, read-only) and reviewers, plus the
 * reviewers' direct edit / void of a timesheet row (reason required, audited, employee notified).
 */
@Service
public class AttendanceSheetService {

    static final int MAX_DAYS = 93;
    static final String VOIDED_MESSAGE = "Công đã bị hủy. Hãy liên hệ quản lý.";

    private static final String SHEET_SQL = "SELECT a.id AS assignment_id, e.id AS employee_id, e.user_id, "
            + "e.full_name, e.employee_code, s.id AS shift_id, s.branch_id, b.name AS branch_name, "
            + "s.starts_at, s.ends_at, r.id AS attendance_id, r.check_in_at, r.check_out_at, "
            + "COALESCE(r.worked_minutes, 0) AS worked_minutes, COALESCE(r.late_minutes, 0) AS late_minutes, "
            + "COALESCE(r.overtime_minutes, 0) AS overtime_minutes, r.overtime_status, r.arrival_status, "
            + "r.status AS record_status, r.attendance_state, r.locked_at, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id AND ev.result = 'accepted') "
            + "AS accepted_events, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
            + "AND ev.result = 'pending_review') AS pending_events, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id AND ev.result = 'rejected') "
            + "AS rejected_events, "
            + "(SELECT ev.rejection_reason FROM attendance_events ev WHERE ev.assignment_id = a.id "
            + "AND ev.result = 'rejected' ORDER BY ev.id DESC LIMIT 1) AS last_rejection_reason "
            + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
            + "JOIN employees e ON e.id = a.employee_id JOIN branches b ON b.id = s.branch_id "
            + "LEFT JOIN attendance_records r ON r.assignment_id = a.id ";

    private final AttendanceSupport sup;
    private final JdbcTemplate jdbc;
    private final AttendanceClock clock;

    public AttendanceSheetService(AttendanceSupport sup, JdbcTemplate jdbc, AttendanceClock clock) {
        this.sup = sup;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    // ---- sheet ---------------------------------------------------------------------------------

    public Map<String, Object> sheet(Long employeeId, LocalDate fromDate, LocalDate toDate) {
        LocalDate today = LocalDate.now(AppTime.ZONE);
        LocalDate from = fromDate != null ? fromDate : today.withDayOfMonth(1);
        LocalDate to = toDate != null ? toDate : today;
        if (to.isBefore(from) || ChronoUnit.DAYS.between(from, to) + 1 > MAX_DAYS) {
            throw ApiException.badRequest("Khoảng ngày không hợp lệ.");
        }
        boolean reviewer = sup.access.can("attendance.review");
        Map<String, Object> employee = null;
        Long scope = null;
        Long filterEmployee = employeeId;
        if (reviewer) {
            scope = sup.scope();
            if (employeeId != null) {
                employee = sup.one("SELECT id, full_name, employee_code, branch_id FROM employees WHERE id = ?",
                        employeeId);
                if (employee == null) {
                    throw ApiException.notFound("Không tìm thấy nhân viên.");
                }
                if (scope != null && scope != ((Number) employee.get("branch_id")).longValue()) {
                    throw ApiException.forbidden("Chỉ được xử lý chấm công trong chi nhánh của mình.");
                }
            }
        } else {
            sup.access.require("attendance.self");
            Map<String, Object> me = sup.me();
            long myId = ((Number) me.get("id")).longValue();
            if (employeeId != null && employeeId != myId) {
                throw ApiException.forbidden("Tài khoản không có quyền thực hiện thao tác này.");
            }
            filterEmployee = myId;
            employee = sup.one("SELECT id, full_name, employee_code, branch_id FROM employees WHERE id = ?", myId);
        }
        StringBuilder where = new StringBuilder(
                "WHERE a.status <> 'cancelled' AND s.status <> 'cancelled' "
                        + "AND DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00')) BETWEEN ? AND ?");
        List<Object> args = new ArrayList<>();
        args.add(java.sql.Date.valueOf(from));
        args.add(java.sql.Date.valueOf(to));
        if (scope != null) {
            where.append(" AND s.branch_id = ?");
            args.add(scope);
        }
        if (filterEmployee != null) {
            where.append(" AND a.employee_id = ?");
            args.add(filterEmployee);
        }
        List<Map<String, Object>> rows = withStatus(jdbc.queryForList(
                SHEET_SQL + where + " ORDER BY s.starts_at, e.full_name", args.toArray()));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("from", from.toString());
        result.put("to", to.toString());
        result.put("employee", employee);
        result.put("rows", rows);
        result.put("summary", summarize(rows));
        return result;
    }

    public List<Map<String, Object>> sheetEmployees() {
        if (sup.access.can("attendance.review")) {
            Long scope = sup.scope();
            String base = "SELECT id, full_name, employee_code, branch_id FROM employees WHERE status = 'active' ";
            return scope == null ? jdbc.queryForList(base + "ORDER BY full_name")
                    : jdbc.queryForList(base + "AND branch_id = ? ORDER BY full_name", scope);
        }
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        return jdbc.queryForList("SELECT id, full_name, employee_code, branch_id FROM employees WHERE id = ?",
                me.get("id"));
    }

    private List<Map<String, Object>> withStatus(List<Map<String, Object>> rows) {
        Instant now = clock.now();
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> row = new LinkedHashMap<>(r);
            row.put("sheet_status", sheetStatus(r, now));
            result.add(row);
        }
        return result;
    }

    public static String sheetStatus(Map<String, Object> r, Instant now) {
        boolean in = r.get("check_in_at") != null;
        boolean out = r.get("check_out_at") != null;
        boolean ended = instant(r.get("ends_at")).isBefore(now);
        if ("VOIDED".equals(r.get("attendance_state"))) {
            return "VOIDED";
        }
        if (in && out) {
            return "SUCCESS";
        }
        if (((Number) r.get("pending_events")).longValue() > 0) {
            return "PENDING_REVIEW";
        }
        if (in) {
            return ended ? "MISSING_CHECK_OUT" : "IN_PROGRESS";
        }
        if (((Number) r.get("rejected_events")).longValue() > 0) {
            return "REJECTED";
        }
        return ended ? "MISSING_CHECK_IN" : "NOT_STARTED";
    }

    private Map<String, Object> summarize(List<Map<String, Object>> rows) {
        long success = 0;
        long pending = 0;
        long rejected = 0;
        long missing = 0;
        long voided = 0;
        long worked = 0;
        long late = 0;
        for (Map<String, Object> r : rows) {
            switch ((String) r.get("sheet_status")) {
                case "SUCCESS" -> success++;
                case "PENDING_REVIEW" -> pending++;
                case "REJECTED" -> rejected++;
                case "MISSING_CHECK_IN", "MISSING_CHECK_OUT" -> missing++;
                case "VOIDED" -> voided++;
                default -> { }
            }
            worked += ((Number) r.get("worked_minutes")).longValue();
            if (((Number) r.get("late_minutes")).longValue() > 0) {
                late++;
            }
        }
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", rows.size());
        summary.put("success", success);
        summary.put("pending_review", pending);
        summary.put("rejected", rejected);
        summary.put("missing", missing);
        summary.put("voided", voided);
        summary.put("worked_minutes", worked);
        summary.put("late_count", late);
        return summary;
    }

    private Map<String, Object> sheetRow(long assignmentId) {
        List<Map<String, Object>> rows = withStatus(jdbc.queryForList(SHEET_SQL + "WHERE a.id = ?", assignmentId));
        return rows.isEmpty() ? null : rows.get(0);
    }

    // ---- direct edit / void --------------------------------------------------------------------

    @Transactional
    public Map<String, Object> adminEdit(long assignmentId, Instant checkIn, Instant checkOut, String reason) {
        Map<String, Object> target = reviewTarget(assignmentId);
        if (reason == null || reason.isBlank()) {
            throw ApiException.badRequest("Nhập lý do chỉnh công.");
        }
        if (checkIn == null && checkOut == null) {
            throw ApiException.badRequest("Nhập giờ vào hoặc giờ ra cần chỉnh.");
        }
        sup.ensureEditable(assignmentId);
        Map<String, Object> record = ensureRecord(assignmentId);
        Instant newIn = checkIn != null ? checkIn.truncatedTo(ChronoUnit.SECONDS) : instant(record.get("check_in_at"));
        Instant newOut = checkOut != null ? checkOut.truncatedTo(ChronoUnit.SECONDS)
                : instant(record.get("check_out_at"));
        if (newOut != null && (newIn == null || newOut.isBefore(newIn))) {
            // Checked before writing: the table's CHECK constraint would otherwise surface as a 500.
            throw ApiException.badRequest("Giờ ra phải từ giờ vào trở đi.");
        }
        Instant now = clock.now();
        jdbc.update("UPDATE attendance_records SET check_in_at = ?, check_out_at = ?, status = 'adjusted', "
                + "approved_by = ?, approved_at = ? WHERE id = ?", ts(newIn), ts(newOut), sup.access.userId(),
                ts(now), record.get("id"));
        sup.refreshMetrics(assignmentId); // 400 + rollback when the out time precedes the in time
        closeOpenItems(assignmentId, record, "Đã chỉnh công trực tiếp: " + reason.trim(), false, now);
        finish("attendance.admin_edit", "Giờ công đã được chỉnh", "Quản lý đã chỉnh giờ công của bạn. Lý do: ",
                target, record, reason.trim());
        return sheetRow(assignmentId);
    }

    @Transactional
    public Map<String, Object> voidAttendance(long assignmentId, String reason) {
        Map<String, Object> target = reviewTarget(assignmentId);
        if (reason == null || reason.isBlank()) {
            throw ApiException.badRequest("Nhập lý do hủy công.");
        }
        sup.ensureEditable(assignmentId);
        Map<String, Object> record = ensureRecord(assignmentId);
        Instant now = clock.now();
        jdbc.update("UPDATE attendance_records SET check_in_at = NULL, check_out_at = NULL, worked_minutes = 0, "
                + "overtime_minutes = 0, late_minutes = 0, overtime_requested_minutes = 0, "
                + "overtime_status = 'NOT_REQUIRED', arrival_status = NULL, status = 'absent', "
                + "attendance_state = 'VOIDED', approved_by = ?, approved_at = ? WHERE id = ?",
                sup.access.userId(), ts(now), record.get("id"));
        closeOpenItems(assignmentId, record, "Đã hủy công: " + reason.trim(), true, now);
        finish("attendance.void", "Công bị hủy", "Quản lý đã hủy công của bạn. Lý do: ", target, record,
                reason.trim());
        return sheetRow(assignmentId);
    }

    /** Permission, existence, branch, ownership and cancellation checks shared by edit and void. */
    private Map<String, Object> reviewTarget(long assignmentId) {
        sup.access.require("attendance.review");
        Map<String, Object> target = sup.one(
                "SELECT a.id, a.status AS assignment_status, a.employee_id, e.user_id, e.full_name, s.branch_id, "
                        + "s.status AS shift_status FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "JOIN employees e ON e.id = a.employee_id WHERE a.id = ?", assignmentId);
        if (target == null) {
            throw ApiException.notFound("Không tìm thấy phân ca.");
        }
        sup.requireBranch(((Number) target.get("branch_id")).longValue());
        if (target.get("user_id") != null && ((Number) target.get("user_id")).longValue() == sup.access.userId()) {
            throw ApiException.forbidden("Không được tự sửa công của mình.");
        }
        if ("cancelled".equals(target.get("assignment_status")) || "cancelled".equals(target.get("shift_status"))) {
            throw ApiException.badRequest("Ca đã hủy.");
        }
        return target;
    }

    private Map<String, Object> ensureRecord(long assignmentId) {
        Map<String, Object> record = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
        if (record == null) {
            Db.insert(jdbc, "INSERT INTO attendance_records (assignment_id, status, attendance_state) "
                    + "VALUES (?, 'pending', 'MISSING_CHECK_IN')", assignmentId);
            record = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
        }
        return record;
    }

    /** Rejects the open events (pending, plus accepted when voiding) and cancels pending adjustment requests. */
    private void closeOpenItems(long assignmentId, Map<String, Object> record, String reason, boolean includeAccepted,
            Instant now) {
        jdbc.update("UPDATE attendance_events SET result = 'rejected', rejection_reason = ?, reviewed_by = ?, "
                + "reviewed_at = ?, confirmed_at = NULL WHERE assignment_id = ? AND result IN ("
                + (includeAccepted ? "'accepted', 'pending_review'" : "'pending_review'") + ")",
                reason, sup.access.userId(), ts(now), assignmentId);
        jdbc.update("UPDATE attendance_adjustment_requests SET status = 'cancelled' "
                + "WHERE attendance_id = ? AND status = 'pending'", record.get("id"));
    }

    private void finish(String action, String title, String bodyPrefix, Map<String, Object> target,
            Map<String, Object> before, String reason) {
        long recordId = ((Number) before.get("id")).longValue();
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("before", before);
        detail.put("after", sup.one("SELECT * FROM attendance_records WHERE id = ?", recordId));
        detail.put("reason", reason);
        sup.audit(action, "attendance_records", recordId, detail);
        Object user = target.get("user_id");
        if (user != null) {
            sup.notify(List.of(((Number) user).longValue()), title, bodyPrefix + reason, "attendance_records",
                    recordId);
        }
    }
}
