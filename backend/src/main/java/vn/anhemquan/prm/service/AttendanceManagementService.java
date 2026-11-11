package vn.anhemquan.prm.service;

import vn.anhemquan.prm.repository.Db;
import static vn.anhemquan.prm.service.AttendanceSupport.instant;
import static vn.anhemquan.prm.service.AttendanceSupport.ts;

import com.fasterxml.jackson.core.type.TypeReference;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;

/** Daily attendance board, case detail, adjustment requests, overtime approval and day closing. */
@Service
public class AttendanceManagementService {

    private final AttendanceSupport sup;
    private final JdbcTemplate jdbc;
    private final AttendanceClock clock;

    public AttendanceManagementService(AttendanceSupport sup, JdbcTemplate jdbc, AttendanceClock clock) {
        this.sup = sup;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    public long notificationAssignment(String entity, long id) {
        sup.access.require("profile.self");
        String sql = switch (entity) {
            case "attendance_events" -> "SELECT assignment_id FROM attendance_events WHERE id = ?";
            case "attendance_records" -> "SELECT assignment_id FROM attendance_records WHERE id = ?";
            case "attendance_adjustment_requests" ->
                    "SELECT r.assignment_id FROM attendance_adjustment_requests q "
                            + "JOIN attendance_records r ON r.id = q.attendance_id WHERE q.id = ?";
            default -> throw ApiException.badRequest("Loại thông báo không hợp lệ.");
        };
        List<Long> rows = jdbc.queryForList(sql, Long.class, id);
        if (rows.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy dữ liệu chấm công.");
        }
        caseDetail(rows.get(0));
        return rows.get(0);
    }

    public Map<String, Object> overview(LocalDate day, boolean self) {
        LocalDate date = day == null ? LocalDate.now(AppTime.ZONE) : day;
        Long scope = null;
        Long employeeId = null;
        if (self) {
            sup.access.require("attendance.self");
            employeeId = ((Number) sup.me().get("id")).longValue();
        } else {
            scope = sup.scope();
        }
        List<Object> args = new ArrayList<>();
        args.add(java.sql.Date.valueOf(date));
        StringBuilder where = new StringBuilder(
                "a.status <> 'cancelled' AND s.status <> 'cancelled' "
                        + "AND DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00')) = ?");
        if (scope != null) {
            where.append(" AND s.branch_id = ?");
            args.add(scope);
        }
        if (employeeId != null) {
            where.append(" AND a.employee_id = ?");
            args.add(employeeId);
        }
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT a.id AS assignment_id, e.id AS employee_id, e.user_id, e.full_name, e.employee_code, "
                        + "s.id AS shift_id, s.branch_id, b.name AS branch_name, s.starts_at, s.ends_at, "
                        + "s.status AS shift_status, r.id AS attendance_id, r.check_in_at, r.check_out_at, "
                        + "r.late_minutes, r.worked_minutes, r.overtime_minutes, r.overtime_requested_minutes, "
                        + "r.overtime_status, r.arrival_status, r.locked_at, q.id AS adjustment_id, "
                        + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.result = 'pending_review') AS pending_exceptions "
                        + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "JOIN employees e ON e.id = a.employee_id JOIN branches b ON b.id = s.branch_id "
                        + "LEFT JOIN attendance_records r ON r.assignment_id = a.id "
                        + "LEFT JOIN attendance_adjustment_requests q ON q.attendance_id = r.id AND q.status = 'pending' "
                        + "WHERE " + where + " ORDER BY s.starts_at, e.full_name", args.toArray());
        Instant now = clock.now();
        List<Map<String, Object>> entries = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> entry = new LinkedHashMap<>(r);
            boolean over = now.isAfter(instant(r.get("ends_at")));
            entry.put("work_state", r.get("check_in_at") == null ? (over ? "MISSING_CHECK_IN" : "NOT_STARTED")
                    : r.get("check_out_at") == null ? (over ? "MISSING_CHECK_OUT" : "IN_PROGRESS") : "COMPLETED");
            entry.put("request_state", r.get("adjustment_id") != null ? "PENDING_ADJUSTMENT" : null);
            entries.add(entry);
        }
        List<Object> countArgs = new ArrayList<>();
        StringBuilder countSql = new StringBuilder("SELECT COUNT(*) FROM employees WHERE status = 'active'");
        if (scope != null) {
            countSql.append(" AND branch_id = ?");
            countArgs.add(scope);
        }
        if (employeeId != null) {
            countSql.append(" AND id = ?");
            countArgs.add(employeeId);
        }
        Long employeeCount = jdbc.queryForObject(countSql.toString(), Long.class, countArgs.toArray());
        Set<Object> checkedIn = new LinkedHashSet<>();
        Set<Object> late = new LinkedHashSet<>();
        long pending = 0;
        for (Map<String, Object> r : entries) {
            if (r.get("check_in_at") != null) {
                checkedIn.add(r.get("employee_id"));
            }
            if (r.get("late_minutes") != null && ((Number) r.get("late_minutes")).intValue() > 0) {
                late.add(r.get("employee_id"));
            }
            pending += ((Number) r.get("pending_exceptions")).longValue() + (r.get("adjustment_id") == null ? 0 : 1)
                    + ("PENDING".equals(r.get("overtime_status")) ? 1 : 0);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("date", date.toString());
        result.put("employees", employeeCount);
        result.put("checked_in", checkedIn.size());
        result.put("late", late.size());
        result.put("pending", pending);
        result.put("rows", entries);
        return result;
    }

    public Map<String, Object> caseDetail(long assignmentId) {
        Map<String, Object> s = sup.one(
                "SELECT a.id AS assignment_id, a.employee_id, e.user_id, e.full_name, e.employee_code, s.*, "
                        + "b.name AS branch_name FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "JOIN employees e ON e.id = a.employee_id JOIN branches b ON b.id = s.branch_id "
                        + "WHERE a.id = ?", assignmentId);
        if (s == null) {
            throw ApiException.notFound("Không tìm thấy phân ca.");
        }
        boolean own = s.get("user_id") != null && ((Number) s.get("user_id")).longValue() == sup.access.userId();
        if (own) {
            sup.access.require("attendance.self");
        } else {
            sup.requireBranch(((Number) s.get("branch_id")).longValue());
        }
        Map<String, Object> record = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
        List<Map<String, Object>> events = jdbc.queryForList(
                "SELECT * FROM attendance_events WHERE assignment_id = ? ORDER BY id", assignmentId);
        List<Map<String, Object>> adjustments = record == null ? List.of() : jdbc.queryForList(
                "SELECT q.*, u.username AS reviewer_name FROM attendance_adjustment_requests q "
                        + "LEFT JOIN users u ON u.id = q.reviewed_by WHERE q.attendance_id = ? ORDER BY q.id DESC",
                record.get("id"));
        List<Object> eventIds = events.stream().map(r -> r.get("id")).toList();
        List<Object> requestIds = adjustments.stream().map(r -> r.get("id")).toList();
        List<Object> args = new ArrayList<>(eventIds);
        args.addAll(requestIds);
        args.add(record == null ? -1L : record.get("id"));
        List<Map<String, Object>> audit = jdbc.queryForList(
                "SELECT l.*, u.username AS actor_name FROM audit_logs l LEFT JOIN users u ON u.id = l.actor_user_id "
                        + "WHERE (l.entity_type = 'attendance_events' AND l.entity_id IN (" + marks(eventIds.size())
                        + ")) OR (l.entity_type = 'attendance_adjustment_requests' AND l.entity_id IN ("
                        + marks(requestIds.size()) + ")) OR (l.entity_type = 'attendance_records' AND l.entity_id = ?) "
                        + "ORDER BY l.id DESC", args.toArray());
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("shift", s);
        result.put("record", record);
        result.put("events", events);
        result.put("adjustments", adjustments);
        result.put("audit", audit);
        result.put("can_review", sup.access.can("attendance.review") && !own);
        return result;
    }

    private static String marks(int n) {
        return n == 0 ? "NULL" : String.join(",", Collections.nCopies(n, "?"));
    }

    @Transactional
    public long requestAdjustment(long assignmentId, Instant checkIn, Instant checkOut, String reason,
            String evidencePath) {
        if (reason == null || reason.isBlank() || (checkIn == null && checkOut == null)) {
            throw ApiException.badRequest("Nhập giờ đề nghị và lý do điều chỉnh.");
        }
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        Map<String, Object> shift = sup.ownAssignment(assignmentId, ((Number) me.get("id")).longValue());
        sup.ensureEditable(assignmentId);
        if ("cancelled".equals(shift.get("shift_status"))) {
            throw ApiException.badRequest("Ca đã hủy.");
        }
        sup.ensureNotVoided(assignmentId);
        Map<String, Object> record = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
        if (record == null) {
            jdbc.update("INSERT INTO attendance_records (assignment_id, status, attendance_state) "
                    + "VALUES (?, 'pending', 'MISSING_CHECK_IN')", assignmentId);
            record = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
        }
        Instant proposedIn = checkIn != null ? checkIn : instant(record.get("check_in_at"));
        Instant proposedOut = checkOut != null ? checkOut : instant(record.get("check_out_at"));
        if (proposedIn != null) {
            proposedIn = proposedIn.truncatedTo(ChronoUnit.SECONDS);
        }
        if (proposedOut != null) {
            proposedOut = proposedOut.truncatedTo(ChronoUnit.SECONDS);
        }
        Instant latest = clock.now().plusSeconds(60);
        if ((proposedIn != null && proposedIn.isAfter(latest)) || (proposedOut != null && proposedOut.isAfter(latest))) {
            throw ApiException.badRequest("Không đề nghị giờ công chưa xảy ra.");
        }
        if (proposedIn == null || (proposedOut != null && proposedOut.isBefore(proposedIn))) {
            throw ApiException.badRequest("Cần giờ vào hợp lệ; giờ ra không trước giờ vào.");
        }
        if (!jdbc.queryForList("SELECT 1 FROM attendance_adjustment_requests WHERE attendance_id = ? "
                + "AND status = 'pending'", record.get("id")).isEmpty()) {
            throw ApiException.badRequest("Đã có yêu cầu điều chỉnh đang chờ duyệt.");
        }
        Long id = Db.insert(jdbc,
                "INSERT INTO attendance_adjustment_requests (attendance_id, requested_by, requested_check_in, "
                        + "requested_check_out, reason, before_json, evidence_path) VALUES (?, ?, ?, ?, ?, ?, ?) "
                        + "", record.get("id"), sup.access.userId(), ts(proposedIn),
                ts(proposedOut), reason.trim(), sup.toJson(record), evidencePath);
        sup.notify(sup.reviewers(((Number) shift.get("branch_id")).longValue()), "Yêu cầu bổ sung / sửa công",
                me.get("full_name") + " gửi yêu cầu #" + id + ".", "attendance_adjustment_requests", id);
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("before", record);
        detail.put("proposed_in", proposedIn.toString());
        detail.put("proposed_out", proposedOut == null ? null : proposedOut.toString());
        sup.audit("attendance.adjustment.request", "attendance_adjustment_requests", id, detail);
        return id;
    }

    @Transactional
    public void reviewAdjustment(long requestId, boolean approve, String note) {
        if (note == null || note.isBlank()) {
            throw ApiException.badRequest("Nhập nhận xét xử lý.");
        }
        Map<String, Object> q = sup.one(
                "SELECT * FROM attendance_adjustment_requests WHERE id = ? AND status = 'pending'", requestId);
        if (q == null) {
            throw ApiException.badRequest("Yêu cầu đã xử lý hoặc không tồn tại.");
        }
        Map<String, Object> r = sup.one("SELECT * FROM attendance_records WHERE id = ?", q.get("attendance_id"));
        long assignmentId = ((Number) r.get("assignment_id")).longValue();
        Map<String, Object> s = sup.one(
                "SELECT a.employee_id, s.branch_id FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "WHERE a.id = ?", assignmentId);
        sup.requireBranch(((Number) s.get("branch_id")).longValue());
        if (((Number) q.get("requested_by")).longValue() == sup.access.userId()) {
            throw ApiException.forbidden("Không được tự duyệt yêu cầu của mình.");
        }
        if (approve) {
            sup.ensureEditable(assignmentId);
            if (jdbc.queryForList("SELECT 1 FROM employees WHERE id = ? AND user_id = ?", s.get("employee_id"),
                    q.get("requested_by")).isEmpty()) {
                throw ApiException.badRequest("Phân ca đã đổi người.");
            }
            if (q.get("before_json") == null) {
                throw ApiException.badRequest(
                        "Yêu cầu cũ thiếu dữ liệu đối chiếu. Hãy từ chối và gửi yêu cầu mới.");
            }
            Map<String, Object> original;
            try {
                original = sup.json.readValue((String) q.get("before_json"),
                        new TypeReference<Map<String, Object>>() { });
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
            if (!Objects.equals(instant(r.get("check_in_at")), instant(original.get("check_in_at")))
                    || !Objects.equals(instant(r.get("check_out_at")), instant(original.get("check_out_at")))) {
                throw ApiException.badRequest("Giờ công đã thay đổi sau khi gửi; cần kiểm tra lại yêu cầu.");
            }
            jdbc.update("UPDATE attendance_records SET check_in_at = ?, check_out_at = ?, status = 'adjusted', "
                            + "approved_by = ?, approved_at = ? WHERE id = ?", q.get("requested_check_in"),
                    q.get("requested_check_out"), sup.access.userId(), ts(clock.now()), r.get("id"));
            sup.refreshMetrics(assignmentId);
        }
        jdbc.update("UPDATE attendance_adjustment_requests SET status = ?, reviewed_by = ?, reviewed_at = ?, "
                        + "review_note = ? WHERE id = ?", approve ? "approved" : "rejected", sup.access.userId(),
                ts(clock.now()), note.trim(), requestId);
        Map<String, Object> after = sup.one("SELECT * FROM attendance_records WHERE id = ?", r.get("id"));
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("before", r);
        detail.put("after", after);
        detail.put("note", note.trim());
        sup.audit(approve ? "attendance.adjustment.approve" : "attendance.adjustment.reject",
                "attendance_adjustment_requests", requestId, detail);
        sup.notify(List.of(((Number) q.get("requested_by")).longValue()), "Kết quả điều chỉnh công",
                "Yêu cầu #" + requestId + " " + (approve ? "đã duyệt" : "bị từ chối") + ". " + note.trim(),
                "attendance_adjustment_requests", requestId);
    }

    @Transactional
    public void reviewOvertime(long assignmentId, boolean approve, String note) {
        if (note == null || note.isBlank()) {
            throw ApiException.badRequest("Nhập lý do xác nhận tăng ca.");
        }
        Map<String, Object> s = sup.one(
                "SELECT s.branch_id, e.user_id FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "JOIN employees e ON e.id = a.employee_id WHERE a.id = ?", assignmentId);
        if (s == null) {
            throw ApiException.notFound("Không tìm thấy phân ca.");
        }
        sup.requireBranch(((Number) s.get("branch_id")).longValue());
        if (s.get("user_id") != null && ((Number) s.get("user_id")).longValue() == sup.access.userId()) {
            throw ApiException.forbidden("Không tự duyệt tăng ca.");
        }
        sup.ensureEditable(assignmentId);
        Map<String, Object> r = sup.one(
                "SELECT * FROM attendance_records WHERE assignment_id = ? AND overtime_status = 'PENDING'",
                assignmentId);
        if (r == null) {
            throw ApiException.badRequest("Không có tăng ca đang chờ duyệt.");
        }
        jdbc.update("UPDATE attendance_records SET overtime_status = ?, overtime_minutes = ?, "
                        + "overtime_reviewed_by = ?, overtime_reviewed_at = ?, overtime_review_note = ? WHERE id = ?",
                approve ? "APPROVED" : "REJECTED", approve ? r.get("overtime_requested_minutes") : 0,
                sup.access.userId(), ts(clock.now()), note.trim(), r.get("id"));
        long recordId = ((Number) r.get("id")).longValue();
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("approved", approve);
        detail.put("note", note.trim());
        detail.put("minutes", r.get("overtime_requested_minutes"));
        sup.audit("attendance.overtime.review", "attendance_records", recordId, detail);
        if (s.get("user_id") != null) {
            sup.notify(List.of(((Number) s.get("user_id")).longValue()), "Kết quả xác nhận tăng ca",
                    approve ? "Tăng ca đã được duyệt." : "Tăng ca bị từ chối. " + note.trim(),
                    "attendance_records", recordId);
        }
    }

    @Transactional
    @SuppressWarnings("unchecked")
    public void closeDay(LocalDate day, String note) {
        Map<String, Object> overview = overview(day, false);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) overview.get("rows");
        if (rows.isEmpty()) {
            throw ApiException.badRequest("Không có ca để chốt.");
        }
        for (Map<String, Object> row : rows) {
            Map<String, Object> detail = sup.one(
                    "SELECT a.id, s.branch_id, s.ends_at, r.id AS record_id, r.check_in_at, r.check_out_at, "
                            + "r.overtime_status FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                            + "LEFT JOIN attendance_records r ON r.assignment_id = a.id WHERE a.id = ?",
                    row.get("assignment_id"));
            sup.requireBranch(((Number) detail.get("branch_id")).longValue());
            if (detail.get("check_in_at") == null || detail.get("check_out_at") == null
                    || "PENDING".equals(detail.get("overtime_status"))
                    || instant(detail.get("ends_at")).isAfter(clock.now())) {
                throw ApiException.badRequest("Còn ca chưa hoàn tất hoặc tăng ca chưa xử lý.");
            }
            if (!jdbc.queryForList("SELECT 1 FROM attendance_events WHERE assignment_id = ? "
                    + "AND result = 'pending_review' UNION ALL SELECT 1 FROM attendance_adjustment_requests "
                    + "WHERE attendance_id = ? AND status = 'pending'", row.get("assignment_id"),
                    detail.get("record_id")).isEmpty()) {
                throw ApiException.badRequest("Còn yêu cầu ngoại lệ chưa xử lý.");
            }
            jdbc.update("UPDATE attendance_records SET locked_by = ?, locked_at = ? WHERE id = ?",
                    sup.access.userId(), ts(clock.now()), detail.get("record_id"));
            Map<String, Object> audit = new LinkedHashMap<>();
            audit.put("date", overview.get("date"));
            audit.put("note", note == null ? "" : note.trim());
            sup.audit("attendance.close", "attendance_records", ((Number) detail.get("record_id")).longValue(),
                    audit);
        }
    }
}
