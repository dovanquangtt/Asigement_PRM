package vn.anhemquan.prm.service;

import vn.anhemquan.prm.repository.Db;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;

/** Shifts, assignments, leave requests and shift swaps (port of the Flutter WorkforceOperations schedule part). */
@Service
public class ScheduleService {

    private static final String AUDIT_EMPTY = "{}";

    private final JdbcTemplate jdbc;
    private final Access access;
    private final Notifier notifier;
    private final AttendanceClock clock;

    public ScheduleService(JdbcTemplate jdbc, Access access, Notifier notifier, AttendanceClock clock) {
        this.jdbc = jdbc;
        this.access = access;
        this.notifier = notifier;
        this.clock = clock;
    }

    // ---------------------------------------------------------------- helpers

    /** The active employee profile of the signed-in user. */
    private Map<String, Object> me() {
        access.require("profile.self");
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT * FROM employees WHERE user_id = ? AND status = 'active'", access.userId());
        if (rows.isEmpty()) {
            throw ApiException.forbidden("Tài khoản chưa được liên kết hồ sơ nhân viên đang làm việc.");
        }
        return rows.get(0);
    }

    private void audit(String action, String entity, long id) {
        notifier.audit(access.userId(), action, entity, id, null, AUDIT_EMPTY);
    }

    private Map<String, Object> shiftOrThrow(long shiftId) {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT * FROM shifts WHERE id = ?", shiftId);
        if (rows.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy ca.");
        }
        return rows.get(0);
    }

    private static long id(Object value) {
        return ((Number) value).longValue();
    }

    private static Instant instant(Object value) {
        if (value == null) {
            throw new IllegalArgumentException("Unsupported time value: null");
        }
        return AppTime.toInstant(value);
    }

    private void notifyUsers(Collection<Long> users, String title, String body, long requestId) {
        notifier.notify(access.userId(), users, title, body, "shift_swap_requests", requestId);
    }

    /** Employee may take this shift: active, same branch, shift open, no overlap, not on approved leave. */
    private void available(long employeeId, Map<String, Object> shift, Collection<Long> ignoring) {
        List<Map<String, Object>> employees = jdbc.queryForList(
                "SELECT * FROM employees WHERE id = ? AND status = 'active'", employeeId);
        if (employees.isEmpty() || id(employees.get(0).get("branch_id")) != id(shift.get("branch_id"))) {
            throw ApiException.badRequest("Nhân viên phải đang làm việc và thuộc cùng chi nhánh.");
        }
        if (!List.of("scheduled", "in_progress").contains(shift.get("status"))) {
            throw ApiException.badRequest("Ca đã đóng hoặc hủy.");
        }
        List<Long> overlaps = jdbc.queryForList(
                "SELECT a.id FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "WHERE a.employee_id = ? AND a.status <> 'cancelled' AND s.status <> 'cancelled' "
                        + "AND s.starts_at < ? AND s.ends_at > ?",
                Long.class, employeeId, shift.get("ends_at"), shift.get("starts_at"));
        if (overlaps.stream().anyMatch(a -> !ignoring.contains(a))) {
            throw ApiException.badRequest("Nhân viên bị trùng giờ ca.");
        }
        if (!jdbc.queryForList(
                "SELECT id FROM leave_requests WHERE employee_id = ? AND status = 'approved' "
                        + "AND starts_at < ? AND ends_at > ?",
                employeeId, shift.get("ends_at"), shift.get("starts_at")).isEmpty()) {
            throw ApiException.badRequest("Nhân viên đang nghỉ phép.");
        }
    }

    // ---------------------------------------------------------------- shifts (manager)

    public List<Map<String, Object>> branches() {
        access.require("employees.manage");
        return jdbc.queryForList("SELECT * FROM branches ORDER BY name");
    }

    /** Roster rows (one per assignment); employees only see their own. */
    public List<Map<String, Object>> shifts() {
        boolean managing = access.can("shifts.manage");
        if (!managing) {
            access.require("schedule.self");
        }
        String sql = "SELECT v.*, b.name AS branch_name FROM v_shift_roster v "
                + "JOIN branches b ON b.id = v.branch_id JOIN employees e ON e.id = v.employee_id "
                + (managing ? "" : "WHERE e.user_id = ? ") + "ORDER BY v.starts_at DESC";
        return managing ? jdbc.queryForList(sql) : jdbc.queryForList(sql, access.userId());
    }

    public List<Map<String, Object>> allShifts() {
        access.require("shifts.manage");
        return jdbc.queryForList(
                "SELECT s.*, b.name AS branch_name, (SELECT COUNT(*) FROM shift_assignments a "
                        + "WHERE a.shift_id = s.id AND a.status <> 'cancelled') AS assigned_count "
                        + "FROM shifts s JOIN branches b ON b.id = s.branch_id ORDER BY starts_at DESC");
    }

    public List<Map<String, Object>> managerShiftOverview(Long branchId) {
        access.require("shifts.manage");
        String sql = "SELECT s.*, b.name AS branch_name, COUNT(a.id) AS assigned_count, "
                + "COALESCE(GROUP_CONCAT(e.full_name SEPARATOR ', '), '') AS assigned_staff_names "
                + "FROM shifts s JOIN branches b ON b.id = s.branch_id "
                + "LEFT JOIN shift_assignments a ON a.shift_id = s.id AND a.status <> 'cancelled' "
                + "LEFT JOIN employees e ON e.id = a.employee_id "
                + (branchId == null ? "" : "WHERE s.branch_id = ? ")
                + "GROUP BY s.id, b.id ORDER BY s.starts_at DESC, s.id DESC";
        return branchId == null ? jdbc.queryForList(sql) : jdbc.queryForList(sql, branchId);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> eligibleEmployeesForShift(long shiftId) {
        access.require("shifts.manage");
        Map<String, Object> shift = shiftOrThrow(shiftId);
        List<Map<String, Object>> employees = jdbc.queryForList(
                "SELECT * FROM employees WHERE branch_id = ? AND status = 'active' ORDER BY full_name, id",
                shift.get("branch_id"));
        List<Long> assigned = jdbc.queryForList(
                "SELECT employee_id FROM shift_assignments WHERE shift_id = ? AND status <> 'cancelled'",
                Long.class, shiftId);
        Set<Long> assignedIds = new HashSet<>(assigned);
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> employee : employees) {
            boolean already = assignedIds.contains(id(employee.get("id")));
            String reason = null;
            if (already) {
                reason = "Đã phân vào ca này";
            } else {
                try {
                    available(id(employee.get("id")), shift, List.of());
                    if (assigned.size() >= ((Number) shift.get("required_staff")).intValue()) {
                        reason = "Ca đã đủ nhân viên.";
                    }
                } catch (ApiException e) {
                    reason = e.getMessage();
                }
            }
            Map<String, Object> row = new LinkedHashMap<>(employee);
            row.put("is_available", reason == null);
            row.put("is_already_assigned", already);
            row.put("conflict_reason", reason);
            result.add(row);
        }
        return result;
    }

    /** "16/10 08:00-16:00" in Vietnam time for notification texts. */
    private String shiftLabel(Map<String, Object> shift) {
        java.time.format.DateTimeFormatter day = java.time.format.DateTimeFormatter.ofPattern("dd/MM HH:mm");
        java.time.format.DateTimeFormatter hour = java.time.format.DateTimeFormatter.ofPattern("HH:mm");
        return day.format(instant(shift.get("starts_at")).atZone(vn.anhemquan.prm.util.AppTime.ZONE)) + "-"
                + hour.format(instant(shift.get("ends_at")).atZone(vn.anhemquan.prm.util.AppTime.ZONE));
    }

    private void notifyShift(java.util.Collection<Long> employeeIds, String title, String body, long shiftId) {
        notifier.notify(access.userId(), notifier.employeeUsers(employeeIds), title, body, "shifts", shiftId);
    }

    @Transactional
    public void unassignShift(long shiftId, long employeeId) {
        access.require("shifts.manage");
        Map<String, Object> shift = shiftOrThrow(shiftId);
        if (!"scheduled".equals(shift.get("status"))) {
            throw ApiException.badRequest("Chỉ được bỏ phân công ca chưa bắt đầu.");
        }
        List<Long> assignment = jdbc.queryForList(
                "SELECT id FROM shift_assignments WHERE shift_id = ? AND employee_id = ? AND status = 'assigned'",
                Long.class, shiftId, employeeId);
        if (assignment.isEmpty()) {
            throw ApiException.badRequest("Không tìm thấy phân công đang hoạt động.");
        }
        long assignmentId = assignment.get(0);
        if (!jdbc.queryForList("SELECT id FROM attendance_events WHERE assignment_id = ? LIMIT 1", assignmentId)
                .isEmpty()) {
            throw ApiException.badRequest("Không thể bỏ phân công đã có chấm công.");
        }
        jdbc.update("UPDATE shift_assignments SET status = 'cancelled' WHERE id = ?", assignmentId);
        audit("shift.unassign", "shift_assignments", assignmentId);
        notifyShift(List.of(employeeId), "Ca làm đã bị gỡ",
                "Bạn không còn được phân vào ca " + shiftLabel(shift) + ".", shiftId);
    }

    @Transactional
    public void cancelShift(long shiftId) {
        access.require("shifts.manage");
        Map<String, Object> shift = shiftOrThrow(shiftId);
        if ("cancelled".equals(shift.get("status"))) {
            return;
        }
        if (!"scheduled".equals(shift.get("status"))) {
            throw ApiException.badRequest("Chỉ được hủy ca chưa bắt đầu.");
        }
        if (!jdbc.queryForList(
                "SELECT a.id FROM shift_assignments a WHERE a.shift_id = ? AND (a.status = 'completed' "
                        + "OR EXISTS (SELECT 1 FROM attendance_events ev WHERE ev.assignment_id = a.id) "
                        + "OR EXISTS (SELECT 1 FROM attendance_records r WHERE r.assignment_id = a.id)) LIMIT 1",
                shiftId).isEmpty()) {
            throw ApiException.badRequest("Không thể hủy ca đã có chấm công.");
        }
        List<Long> affected = jdbc.queryForList(
                "SELECT employee_id FROM shift_assignments WHERE shift_id = ? AND status = 'assigned'",
                Long.class, shiftId);
        jdbc.update("UPDATE shift_assignments SET status = 'cancelled' WHERE shift_id = ? AND status = 'assigned'",
                shiftId);
        jdbc.update("UPDATE shifts SET status = 'cancelled' WHERE id = ?", shiftId);
        audit("shift.cancel", "shifts", shiftId);
        notifyShift(affected, "Ca làm đã bị hủy", "Ca " + shiftLabel(shift) + " đã bị hủy.", shiftId);
    }

    @Transactional
    public long createShift(long branchId, OffsetDateTime start, OffsetDateTime end, int requiredStaff, String note) {
        if (start == null || end == null || !end.isAfter(start) || requiredStaff < 1) {
            throw ApiException.badRequest(
                    "Giờ kết thúc phải sau giờ bắt đầu; số nhân viên phải lớn hơn 0.");
        }
        access.require("shifts.manage");
        if (jdbc.queryForList("SELECT id FROM branches WHERE id = ?", branchId).isEmpty()) {
            throw ApiException.notFound("Không tìm thấy chi nhánh.");
        }
        Long shiftId = Db.insert(jdbc,
                "INSERT INTO shifts (branch_id, starts_at, ends_at, required_staff, created_by, note) "
                        + "VALUES (?, ?, ?, ?, ?, ?)", branchId, start, end, requiredStaff, access.userId(), note == null ? "" : note);
        audit("shift.create", "shifts", shiftId);
        // Tell the branch's active employees that a new shift exists (not yet an assignment).
        List<Long> branchEmployees = jdbc.queryForList(
                "SELECT id FROM employees WHERE branch_id = ? AND status = 'active' AND user_id IS NOT NULL",
                Long.class, branchId);
        List<Long> managers = notifier.reviewers("shifts.manage", List.of());
        List<Long> recipients = new java.util.ArrayList<>(notifier.employeeUsers(branchEmployees));
        recipients.removeAll(managers);
        notifier.notify(access.userId(), recipients, "Có ca làm mới",
                "Chi nhánh vừa tạo ca " + shiftLabel(shiftOrThrow(shiftId))
                        + ". Quản lý sẽ phân công cho bạn nếu phù hợp.", "shifts", shiftId);
        return shiftId;
    }

    @Transactional
    public void assignShift(long shiftId, long employeeId) {
        access.require("shifts.manage");
        Map<String, Object> shift = shiftOrThrow(shiftId);
        available(employeeId, shift, List.of());
        Long count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM shift_assignments WHERE shift_id = ? AND status <> 'cancelled'",
                Long.class, shiftId);
        if (count != null && count >= ((Number) shift.get("required_staff")).intValue()) {
            throw ApiException.badRequest("Ca đã đủ nhân viên.");
        }
        List<Long> old = jdbc.queryForList(
                "SELECT id FROM shift_assignments WHERE shift_id = ? AND employee_id = ?",
                Long.class, shiftId, employeeId);
        long assignmentId;
        if (old.isEmpty()) {
            assignmentId = Db.insert(jdbc,
                    "INSERT INTO shift_assignments (shift_id, employee_id, assigned_by, status, response_status) "
                            + "VALUES (?, ?, ?, 'assigned', 'pending')", shiftId, employeeId, access.userId());
        } else {
            assignmentId = old.get(0);
            jdbc.update("UPDATE shift_assignments SET assigned_by = ?, status = 'assigned', "
                    + "response_status = 'pending', responded_at = NULL, response_note = NULL WHERE id = ?",
                    access.userId(), assignmentId);
        }
        audit("shift.assign", "shift_assignments", assignmentId);
        notifyShift(List.of(employeeId), "Bạn có ca làm mới",
                "Bạn được phân vào ca " + shiftLabel(shift) + ". Hãy chấp nhận hoặc từ chối.", shiftId);
    }

    @Transactional(readOnly = true)
    public Map<String, Object> shiftDetail(long shiftId) {
        if (!access.can("shifts.manage")) {
            access.require("schedule.self");
            Map<String, Object> me = me();
            if (jdbc.queryForList(
                    "SELECT id FROM shift_assignments WHERE shift_id = ? AND employee_id = ? AND status <> 'cancelled'",
                    shiftId, me.get("id")).isEmpty()) {
                throw ApiException.forbidden("Bạn không thuộc ca này.");
            }
        }
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT s.*, b.name AS branch_name, b.latitude, b.longitude, b.geofence_radius_m "
                        + "FROM shifts s JOIN branches b ON b.id = s.branch_id WHERE s.id = ?",
                shiftId);
        if (rows.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy ca.");
        }
        List<Map<String, Object>> roster = jdbc.queryForList(
                "SELECT a.id, a.status, a.response_status, e.employee_code, e.full_name, e.user_id, "
                        + "(SELECT event_type FROM attendance_events WHERE assignment_id = a.id AND result = 'accepted' "
                        + "ORDER BY occurred_at DESC LIMIT 1) AS last_event, "
                        + "(SELECT status FROM shift_closures WHERE assignment_id = a.id ORDER BY id DESC LIMIT 1) "
                        + "AS closure_status "
                        + "FROM shift_assignments a JOIN employees e ON e.id = a.employee_id "
                        + "WHERE a.shift_id = ? AND a.status <> 'cancelled'",
                shiftId);
        Map<String, Object> detail = new LinkedHashMap<>(rows.get(0));
        detail.put("roster", roster);
        return detail;
    }

    // ---------------------------------------------------------------- employee schedule & leave

    /** Schedule of the signed-in employee, or of {@code employeeId} when the caller manages shifts. */
    public List<Map<String, Object>> employeeSchedule(Long employeeId) {
        boolean managing = access.can("shifts.manage");
        long target;
        if (employeeId != null && managing) {
            target = employeeId;
        } else {
            access.require("schedule.self");
            target = id(me().get("id"));
        }
        return jdbc.queryForList(
                "SELECT a.id AS assignment_id, s.id AS shift_id, s.branch_id, s.starts_at, s.ends_at, "
                        + "s.status AS shift_status, s.required_staff, s.note AS shift_note, b.name AS branch_name, "
                        + "a.status AS assignment_status, "
                        + "a.response_status, a.responded_at, a.response_note, "
                        + "(SELECT GROUP_CONCAT(e2.full_name SEPARATOR ', ') FROM shift_assignments a2 "
                        + "JOIN employees e2 ON e2.id = a2.employee_id WHERE a2.shift_id = s.id "
                        + "AND a2.employee_id <> a.employee_id AND a2.status <> 'cancelled') AS coworkers, "
                        + "(SELECT COUNT(*) FROM shift_assignments a3 WHERE a3.shift_id = s.id "
                        + "AND a3.status <> 'cancelled') AS total_assigned, "
                        + "(SELECT event_type FROM attendance_events WHERE assignment_id = a.id "
                        + "AND result = 'accepted' ORDER BY occurred_at DESC LIMIT 1) AS last_attendance_event, "
                        + "(SELECT status FROM shift_closures WHERE assignment_id = a.id ORDER BY id DESC LIMIT 1) "
                        + "AS closure_status "
                        + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "JOIN branches b ON b.id = s.branch_id "
                        + "WHERE a.employee_id = ? AND a.status <> 'cancelled' ORDER BY s.starts_at DESC",
                target);
    }

    public List<Map<String, Object>> leaveTypes() {
        access.require("schedule.self");
        return jdbc.queryForList("SELECT * FROM leave_types ORDER BY name");
    }

    public List<Map<String, Object>> employeeLeaveRequests() {
        access.require("schedule.self");
        Map<String, Object> me = me();
        return jdbc.queryForList(
                "SELECT l.*, t.name AS leave_type_name FROM leave_requests l "
                        + "JOIN leave_types t ON t.id = l.leave_type_id WHERE l.employee_id = ? "
                        + "ORDER BY l.starts_at DESC",
                me.get("id"));
    }

    @Transactional
    public void createLeaveRequest(long leaveTypeId, OffsetDateTime start, OffsetDateTime end, String reason) {
        if (start == null || end == null || !end.isAfter(start)) {
            throw ApiException.badRequest("Thời gian kết thúc phải sau thời gian bắt đầu.");
        }
        if (reason == null || reason.isBlank()) {
            throw ApiException.badRequest("Vui lòng nhập lý do nghỉ phép.");
        }
        access.require("schedule.self");
        Map<String, Object> me = me();
        long minutes = Duration.between(start, end).toMinutes();
        if (minutes <= 0) {
            throw ApiException.badRequest("Thời gian nghỉ không hợp lệ.");
        }
        if (jdbc.queryForList("SELECT id FROM leave_types WHERE id = ?", leaveTypeId).isEmpty()) {
            throw ApiException.badRequest("Loại nghỉ phép không hợp lệ.");
        }
        long requestId = vn.anhemquan.prm.repository.Db.insert(jdbc,
                "INSERT INTO leave_requests (employee_id, leave_type_id, starts_at, ends_at, requested_minutes, "
                        + "reason, status) VALUES (?, ?, ?, ?, ?, ?, 'pending')",
                me.get("id"), leaveTypeId, start, end, minutes, reason.trim());
        // Admin and the branch's managers decide on the request.
        notifier.notify(access.userId(), branchReviewers(id(me.get("branch_id"))), "Yêu cầu nghỉ phép mới",
                me.get("full_name") + " xin nghỉ " + minutes + " phút. Lý do: " + reason.trim(), "leave_requests",
                requestId);
    }

    /** Admin plus the managers of one branch. */
    private List<Long> branchReviewers(long branchId) {
        return jdbc.queryForList(
                "SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id "
                        + "JOIN roles r ON r.id = ur.role_id "
                        + "LEFT JOIN employees e ON e.user_id = u.id AND e.status = 'active' "
                        + "WHERE u.is_active AND (r.code = 'admin' OR (r.code = 'manager' AND e.branch_id = ?))",
                Long.class, branchId);
    }

    /** Own leave balances of the current year (1 day = 480 minutes); pending requests are already deducted. */
    public List<Map<String, Object>> leaveBalances() {
        access.require("schedule.self");
        Map<String, Object> me = me();
        int year = clock.now().atZone(AppTime.ZONE).getYear();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT t.id AS leave_type_id, t.code, t.name, t.is_paid, "
                        + "COALESCE(b.granted_minutes, 0) AS granted_minutes, COALESCE(b.used_minutes, 0) AS used_minutes, "
                        + "COALESCE((SELECT SUM(l.requested_minutes) FROM leave_requests l WHERE l.employee_id = ? "
                        + "AND l.leave_type_id = t.id AND l.status = 'pending' "
                        + "AND YEAR(CONVERT_TZ(l.starts_at, '+00:00', '+07:00')) = ?), 0) AS pending_minutes "
                        + "FROM leave_types t LEFT JOIN leave_balances b ON b.leave_type_id = t.id "
                        + "AND b.employee_id = ? AND b.year = ? ORDER BY t.name",
                me.get("id"), year, me.get("id"), year);
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> row = new LinkedHashMap<>(r);
            row.put("pending_minutes", id(r.get("pending_minutes")));
            row.put("remaining_minutes",
                    id(r.get("granted_minutes")) - id(r.get("used_minutes")) - id(r.get("pending_minutes")));
            result.add(row);
        }
        return result;
    }

    /** Leave requests the caller may decide on: admin all, manager the own branch; pending first. */
    public List<Map<String, Object>> leaveRequestsForReview() {
        Long scope = shiftScope();
        String sql = "SELECT l.*, t.name AS leave_type_name, t.is_paid, e.full_name, e.employee_code, "
                + "b.name AS branch_name, COALESCE(lb.granted_minutes, 0) - COALESCE(lb.used_minutes, 0) "
                + "AS remaining_minutes FROM leave_requests l JOIN leave_types t ON t.id = l.leave_type_id "
                + "JOIN employees e ON e.id = l.employee_id JOIN branches b ON b.id = e.branch_id "
                + "LEFT JOIN leave_balances lb ON lb.employee_id = l.employee_id AND lb.leave_type_id = l.leave_type_id "
                + "AND lb.year = YEAR(CONVERT_TZ(l.starts_at, '+00:00', '+07:00')) "
                + (scope == null ? "" : "WHERE e.branch_id = ? ")
                + "ORDER BY CASE l.status WHEN 'pending' THEN 0 ELSE 1 END, l.starts_at DESC";
        return scope == null ? jdbc.queryForList(sql) : jdbc.queryForList(sql, scope);
    }

    /**
     * Approves or rejects a pending leave request (reason required to reject). Approving needs enough paid days
     * left and no assigned shift inside the leave; the minutes are deducted from the balance.
     */
    @Transactional
    public void reviewLeaveRequest(long requestId, boolean approve, String note) {
        String reason = note == null ? "" : note.trim();
        if (!approve && reason.isEmpty()) {
            throw ApiException.badRequest("Nhập lý do từ chối nghỉ phép.");
        }
        Long scope = shiftScope();
        List<Map<String, Object>> found = jdbc.queryForList(
                "SELECT l.*, t.is_paid, t.name AS leave_type_name, e.user_id, e.branch_id FROM leave_requests l "
                        + "JOIN leave_types t ON t.id = l.leave_type_id JOIN employees e ON e.id = l.employee_id "
                        + "WHERE l.id = ? FOR UPDATE", requestId);
        if (found.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy yêu cầu nghỉ phép.");
        }
        Map<String, Object> leave = found.get(0);
        requireShiftBranch(scope, id(leave.get("branch_id")));
        Object owner = leave.get("user_id");
        if (owner != null && id(owner) == access.userId()) {
            throw ApiException.forbidden("Không thể tự duyệt nghỉ phép của mình.");
        }
        if (!"pending".equals(leave.get("status"))) {
            throw ApiException.badRequest("Yêu cầu đã được xử lý.");
        }
        long minutes = id(leave.get("requested_minutes"));
        int year = AppTime.toInstant(leave.get("starts_at")).atZone(AppTime.ZONE).getYear();
        if (approve) {
            List<Map<String, Object>> balance = jdbc.queryForList(
                    "SELECT * FROM leave_balances WHERE employee_id = ? AND leave_type_id = ? AND year = ? FOR UPDATE",
                    leave.get("employee_id"), leave.get("leave_type_id"), year);
            Object paid = leave.get("is_paid");
            boolean isPaid = paid instanceof Boolean b ? b : paid != null && id(paid) == 1;
            if (isPaid && (balance.isEmpty()
                    || id(balance.get(0).get("granted_minutes")) - id(balance.get(0).get("used_minutes")) < minutes)) {
                throw ApiException.badRequest("Không đủ số ngày phép còn lại.");
            }
            if (!jdbc.queryForList(
                    "SELECT 1 FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id WHERE a.employee_id = ? "
                            + "AND a.status = 'assigned' AND s.status <> 'cancelled' AND s.starts_at < ? "
                            + "AND s.ends_at > ? LIMIT 1",
                    leave.get("employee_id"), leave.get("ends_at"), leave.get("starts_at")).isEmpty()) {
                throw ApiException.badRequest(
                        "Nhân viên đang có ca trong thời gian nghỉ. Hãy gỡ hoặc đổi ca trước khi duyệt.");
            }
            if (!balance.isEmpty()) {
                jdbc.update("UPDATE leave_balances SET used_minutes = used_minutes + ? "
                        + "WHERE employee_id = ? AND leave_type_id = ? AND year = ?", minutes,
                        leave.get("employee_id"), leave.get("leave_type_id"), year);
            }
        }
        jdbc.update("UPDATE leave_requests SET status = ?, reviewed_by = ?, reviewed_at = ?, review_note = ? "
                + "WHERE id = ?", approve ? "approved" : "rejected", access.userId(),
                AttendanceSupport.ts(clock.now()), reason, requestId);
        audit(approve ? "leave.approve" : "leave.reject", "leave_requests", requestId);
        if (owner != null) {
            notifier.notify(access.userId(), List.of(id(owner)), "Kết quả duyệt nghỉ phép",
                    "Yêu cầu nghỉ phép " + leave.get("leave_type_name") + " của bạn "
                            + (approve ? "đã được duyệt" : "bị từ chối") + (reason.isEmpty() ? "." : ". " + reason),
                    "leave_requests", requestId);
        }
    }

    // ---------------------------------------------------------------- accept / reject an assigned shift

    /** Admin works across branches (null); a manager works inside their own branch. */
    private Long shiftScope() {
        access.require("shifts.manage");
        boolean admin = !jdbc.queryForList(
                "SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id "
                        + "WHERE u.id = ? AND u.is_active AND r.code = 'admin'", access.userId()).isEmpty();
        return admin ? null : id(me().get("branch_id"));
    }

    private void requireShiftBranch(Long scope, long branchId) {
        if (scope != null && scope != branchId) {
            throw ApiException.forbidden("Chỉ được xử lý chấm công trong chi nhánh của mình.");
        }
    }

    /** The assigned employee accepts, or rejects with a reason (which frees the slot). */
    @Transactional
    public void respondToAssignment(long assignmentId, boolean accept, String note) {
        access.require("schedule.self");
        Map<String, Object> me = me();
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT a.*, s.starts_at, s.ends_at, s.branch_id, s.status AS shift_status "
                        + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "WHERE a.id = ? AND a.employee_id = ? FOR UPDATE",
                assignmentId, me.get("id"));
        if (rows.isEmpty()) {
            throw ApiException.forbidden("Phân ca không thuộc bạn.");
        }
        Map<String, Object> a = rows.get(0);
        if (!"assigned".equals(a.get("status")) || !"pending".equals(a.get("response_status"))
                || !"scheduled".equals(a.get("shift_status"))) {
            throw ApiException.badRequest("Ca đã được phản hồi hoặc không còn hiệu lực.");
        }
        if (!instant(a.get("starts_at")).isAfter(clock.now()) || !jdbc.queryForList(
                "SELECT id FROM attendance_events WHERE assignment_id = ? LIMIT 1", assignmentId).isEmpty()) {
            throw ApiException.badRequest("Không thể phản hồi ca đã bắt đầu hoặc đã có chấm công.");
        }
        String reason = note == null ? "" : note.trim();
        if (!accept && reason.isEmpty()) {
            throw ApiException.badRequest("Nhập lý do từ chối ca.");
        }
        if (accept) {
            jdbc.update("UPDATE shift_assignments SET response_status = 'accepted', responded_at = ?, "
                    + "response_note = NULL WHERE id = ?", Timestamp.from(clock.now()), assignmentId);
        } else {
            jdbc.update("UPDATE shift_assignments SET response_status = 'rejected', responded_at = ?, "
                    + "response_note = ?, status = 'cancelled' WHERE id = ?",
                    Timestamp.from(clock.now()), reason, assignmentId);
        }
        long shiftId = id(a.get("shift_id"));
        audit(accept ? "shift.accept" : "shift.reject", "shift_assignments", assignmentId);
        Set<Long> recipients = new HashSet<>(jdbc.queryForList(
                "SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id "
                        + "JOIN roles r ON r.id = ur.role_id "
                        + "LEFT JOIN employees e ON e.user_id = u.id AND e.status = 'active' "
                        + "WHERE u.is_active AND (r.code = 'admin' OR (r.code = 'manager' AND e.branch_id = ?))",
                Long.class, a.get("branch_id")));
        if (a.get("assigned_by") != null) {
            recipients.add(id(a.get("assigned_by")));
        }
        String label = shiftLabel(a);
        String who = String.valueOf(me.get("full_name"));
        notifier.notify(access.userId(), recipients,
                accept ? "Nhân viên chấp nhận ca" : "Nhân viên từ chối ca",
                accept ? who + " đã chấp nhận ca " + label + "."
                        : who + " đã từ chối ca " + label + ". Lý do: " + reason,
                "shifts", shiftId);
    }

    // ---------------------------------------------------------------- per-employee shift table (managers)

    /** Employees whose shift table the caller may open: admin all, manager the own branch. */
    public List<Map<String, Object>> scheduleEmployees() {
        Long scope = shiftScope();
        String sql = "SELECT e.id, e.full_name, e.employee_code, e.branch_id, b.name AS branch_name "
                + "FROM employees e JOIN branches b ON b.id = e.branch_id WHERE e.status = 'active' "
                + (scope == null ? "" : "AND e.branch_id = ? ") + "ORDER BY e.full_name, e.id";
        return scope == null ? jdbc.queryForList(sql) : jdbc.queryForList(sql, scope);
    }

    /** Every shift of one employee in a date range with their response and attendance outcome. */
    public Map<String, Object> employeeShiftTable(long employeeId, java.time.LocalDate from, java.time.LocalDate to) {
        Long scope = shiftScope();
        List<Map<String, Object>> employees = jdbc.queryForList(
                "SELECT id, full_name, employee_code, branch_id FROM employees WHERE id = ?", employeeId);
        if (employees.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy nhân viên.");
        }
        Map<String, Object> employee = employees.get(0);
        requireShiftBranch(scope, id(employee.get("branch_id")));
        java.time.LocalDate today = clock.now().atZone(AppTime.ZONE).toLocalDate();
        java.time.LocalDate start = from != null ? from : today.withDayOfMonth(1);
        java.time.LocalDate end = to != null ? to : start.withDayOfMonth(start.lengthOfMonth());
        if (end.isBefore(start) || java.time.temporal.ChronoUnit.DAYS.between(start, end) + 1 > 93) {
            throw ApiException.badRequest("Khoảng ngày không hợp lệ.");
        }
        List<Map<String, Object>> raw = jdbc.queryForList(
                "SELECT a.id AS assignment_id, s.id AS shift_id, s.starts_at, s.ends_at, s.branch_id, "
                        + "b.name AS branch_name, s.status AS shift_status, a.status AS assignment_status, "
                        + "a.response_status, a.responded_at, a.response_note, "
                        + "COALESCE(eb.full_name, ub.username) AS assigned_by_name, a.assigned_at, "
                        + "r.check_in_at, r.check_out_at, r.attendance_state, "
                        + "(SELECT ev.id FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.event_type = 'check_in' AND ev.result = 'pending_review' "
                        + "ORDER BY ev.id DESC LIMIT 1) AS pending_check_in_id, "
                        + "(SELECT ev.id FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.event_type = 'check_out' AND ev.result = 'pending_review' "
                        + "ORDER BY ev.id DESC LIMIT 1) AS pending_check_out_id, "
                        + "(SELECT ev.occurred_at FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.event_type = 'check_in' AND ev.result = 'pending_review' "
                        + "ORDER BY ev.id DESC LIMIT 1) AS pending_check_in_at, "
                        + "(SELECT ev.occurred_at FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.event_type = 'check_out' AND ev.result = 'pending_review' "
                        + "ORDER BY ev.id DESC LIMIT 1) AS pending_check_out_at, "
                        + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.result = 'pending_review') AS pending_events, "
                        + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
                        + "AND ev.result = 'rejected') AS rejected_events "
                        + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "JOIN branches b ON b.id = s.branch_id "
                        + "LEFT JOIN users ub ON ub.id = a.assigned_by "
                        + "LEFT JOIN employees eb ON eb.user_id = ub.id "
                        + "LEFT JOIN attendance_records r ON r.assignment_id = a.id "
                        + "WHERE a.employee_id = ? AND s.status <> 'cancelled' "
                        + "AND (a.status <> 'cancelled' OR a.response_status = 'rejected') "
                        + "AND DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00')) BETWEEN ? AND ? "
                        + "ORDER BY s.starts_at, a.id",
                employeeId, java.sql.Date.valueOf(start), java.sql.Date.valueOf(end));
        Instant now = clock.now();
        List<Map<String, Object>> rows = new ArrayList<>();
        long pending = 0;
        long accepted = 0;
        long rejected = 0;
        for (Map<String, Object> r : raw) {
            Map<String, Object> row = new LinkedHashMap<>(r);
            String response = String.valueOf(r.get("response_status"));
            row.put("sheet_status", "rejected".equals(response) ? null : AttendanceSheetService.sheetStatus(r, now));
            row.remove("attendance_state");
            row.remove("pending_events");
            row.remove("rejected_events");
            rows.add(row);
            switch (response) {
                case "pending" -> pending++;
                case "rejected" -> rejected++;
                default -> accepted++;
            }
        }
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("total", rows.size());
        summary.put("pending", pending);
        summary.put("accepted", accepted);
        summary.put("rejected", rejected);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("employee", Map.of("id", employee.get("id"), "full_name", employee.get("full_name"),
                "employee_code", employee.get("employee_code")));
        result.put("from", start.toString());
        result.put("to", end.toString());
        result.put("summary", summary);
        result.put("rows", rows);
        return result;
    }

    // ---------------------------------------------------------------- swaps

    private Map<String, Object> ownAssignment(long assignmentId, long employeeId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT a.*, s.starts_at, s.ends_at, s.branch_id FROM shift_assignments a "
                        + "JOIN shifts s ON s.id = a.shift_id WHERE a.id = ? AND a.employee_id = ?",
                assignmentId, employeeId);
        if (rows.isEmpty()) {
            throw ApiException.forbidden("Phân ca không thuộc bạn.");
        }
        return rows.get(0);
    }

    public List<Map<String, Object>> swapOptions(long assignmentId) {
        access.require("swaps.self");
        Map<String, Object> me = me();
        Map<String, Object> from = ownAssignment(assignmentId, id(me.get("id")));
        return jdbc.queryForList(
                "SELECT a.id, s.starts_at, s.ends_at, e.full_name FROM shift_assignments a "
                        + "JOIN shifts s ON s.id = a.shift_id JOIN employees e ON e.id = a.employee_id "
                        + "WHERE a.employee_id <> ? AND a.status = 'assigned' AND s.status = 'scheduled' "
                        + "AND s.branch_id = ? AND s.starts_at > ? ORDER BY s.starts_at",
                me.get("id"), from.get("branch_id"), java.sql.Timestamp.from(Instant.now()));
    }

    @Transactional
    public long requestSwap(long from, long to, String reason) {
        if (reason == null || reason.isBlank() || from == to) {
            throw ApiException.badRequest("Chọn ca khác và nhập lý do.");
        }
        access.require("swaps.self");
        Map<String, Object> me = me();
        Map<String, Object> own = ownAssignment(from, id(me.get("id")));
        List<Map<String, Object>> targets = jdbc.queryForList(
                "SELECT a.*, s.starts_at, s.branch_id FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "WHERE a.id = ? AND a.status = 'assigned' AND s.status = 'scheduled'",
                to);
        Instant now = Instant.now();
        if (targets.isEmpty()
                || id(targets.get(0).get("employee_id")) == id(me.get("id"))
                || id(targets.get(0).get("branch_id")) != id(own.get("branch_id"))
                || instant(targets.get(0).get("starts_at")).isBefore(now)
                || instant(own.get("starts_at")).isBefore(now)) {
            throw ApiException.badRequest("Chỉ đổi ca tương lai với nhân viên khác cùng chi nhánh.");
        }
        Map<String, Object> target = targets.get(0);
        Long requestId = Db.insert(jdbc,
                "INSERT INTO shift_swap_requests (from_assignment_id, to_assignment_id, requested_by, "
                        + "from_employee_id, to_employee_id, reason) VALUES (?, ?, ?, ?, ?, ?)", from, to, access.userId(), own.get("employee_id"), target.get("employee_id"),
                reason.trim());
        notifyUsers(notifier.employeeUsers(List.of(id(target.get("employee_id")))),
                "Yêu cầu đổi ca mới", reason.trim(), requestId);
        return requestId;
    }

    public List<Map<String, Object>> swaps() {
        boolean managing = access.can("swaps.review");
        if (!managing) {
            access.require("swaps.self");
        }
        String sql = "SELECT r.*, f.full_name AS from_name, t.full_name AS to_name, tf.user_id AS target_user_id, "
                + "sf.starts_at AS from_start, st.starts_at AS to_start FROM shift_swap_requests r "
                + "JOIN shift_assignments af ON af.id = r.from_assignment_id "
                + "JOIN shift_assignments at ON at.id = r.to_assignment_id "
                + "JOIN employees f ON f.id = r.from_employee_id JOIN employees t ON t.id = r.to_employee_id "
                + "JOIN employees tf ON tf.id = r.to_employee_id "
                + "JOIN shifts sf ON sf.id = af.shift_id JOIN shifts st ON st.id = at.shift_id "
                + (managing ? "" : "WHERE r.requested_by = ? OR tf.user_id = ? ") + "ORDER BY r.id DESC";
        return managing ? jdbc.queryForList(sql)
                : jdbc.queryForList(sql, access.userId(), access.userId());
    }

    /**
     * Counterpart answers first ({@code review=false}); a manager who is not involved then approves
     * ({@code review=true}). Approval swaps both assignments' employees, keeping assignment ids.
     */
    @Transactional
    public void respondSwap(long id, boolean accept, boolean review) {
        access.require(review ? "swaps.review" : "swaps.self");
        List<Map<String, Object>> found = jdbc.queryForList(
                "SELECT * FROM shift_swap_requests WHERE id = ? FOR UPDATE", id);
        if (found.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy yêu cầu đổi ca.");
        }
        Map<String, Object> r = found.get(0);
        if (!"pending".equals(r.get("status"))) {
            throw ApiException.conflict("Yêu cầu đã được xử lý.");
        }
        Map<String, Object> a = jdbc.queryForMap("SELECT * FROM shift_assignments WHERE id = ?",
                r.get("from_assignment_id"));
        Map<String, Object> b = jdbc.queryForMap("SELECT * FROM shift_assignments WHERE id = ?",
                r.get("to_assignment_id"));
        if (id(a.get("employee_id")) != id(r.get("from_employee_id"))
                || id(b.get("employee_id")) != id(r.get("to_employee_id"))) {
            throw ApiException.conflict("Người được phân ca đã thay đổi. Hãy tạo yêu cầu đổi ca mới.");
        }
        long actor = access.userId();
        long requestedBy = id(r.get("requested_by"));
        List<Long> participants = notifier.employeeUsers(
                List.of(id(r.get("from_employee_id")), id(r.get("to_employee_id"))));
        if (!review) {
            Map<String, Object> me = me();
            if (id(b.get("employee_id")) != id(me.get("id")) || !"pending".equals(r.get("counterpart_status"))) {
                throw ApiException.forbidden("Chỉ người nhận được phản hồi một lần.");
            }
            if (accept) {
                jdbc.update("UPDATE shift_swap_requests SET counterpart_status = 'accepted' WHERE id = ?", id);
            } else {
                jdbc.update("UPDATE shift_swap_requests SET counterpart_status = 'rejected', status = 'rejected', "
                        + "reviewed_by = ?, reviewed_at = CURRENT_TIMESTAMP WHERE id = ?", actor, id);
            }
            notifyUsers(List.of(requestedBy), "Phản hồi đổi ca",
                    accept ? "Người nhận đã đồng ý; yêu cầu đang chờ quản lý duyệt."
                            : "Người nhận đã từ chối đổi ca.", id);
            if (accept) {
                notifyUsers(notifier.reviewers("swaps.review", participants), "Đổi ca chờ duyệt",
                        "Hai bên đã đồng ý đổi ca. Vui lòng kiểm tra yêu cầu.", id);
            }
            return;
        }
        if (!jdbc.queryForList("SELECT id FROM employees WHERE user_id = ? AND id IN (?, ?)",
                actor, a.get("employee_id"), b.get("employee_id")).isEmpty() || requestedBy == actor) {
            throw ApiException.forbidden("Người tham gia không được tự duyệt đổi ca.");
        }
        if (accept) {
            if (!"accepted".equals(r.get("counterpart_status")) || !"assigned".equals(a.get("status"))
                    || !"assigned".equals(b.get("status"))) {
                throw ApiException.conflict("Cần người nhận đồng ý và hai phân ca còn hiệu lực.");
            }
            if (!jdbc.queryForList("SELECT id FROM attendance_events WHERE assignment_id IN (?, ?)",
                    a.get("id"), b.get("id")).isEmpty()) {
                throw ApiException.conflict("Ca đã có lịch sử điểm danh, không thể đổi.");
            }
            Map<String, Object> sa = jdbc.queryForMap("SELECT * FROM shifts WHERE id = ?", a.get("shift_id"));
            Map<String, Object> sb = jdbc.queryForMap("SELECT * FROM shifts WHERE id = ?", b.get("shift_id"));
            Instant now = Instant.now();
            if (instant(sa.get("starts_at")).isBefore(now) || instant(sb.get("starts_at")).isBefore(now)) {
                throw ApiException.conflict("Ca đã bắt đầu.");
            }
            List<Long> ignoring = List.of(id(a.get("id")), id(b.get("id")));
            available(id(b.get("employee_id")), sa, ignoring);
            available(id(a.get("employee_id")), sb, ignoring);
            if (id(a.get("shift_id")) == id(b.get("shift_id"))) {
                throw ApiException.conflict("Hai phân ca phải thuộc hai ca khác nhau.");
            }
            // employee_id is not part of a unique key alone; (shift_id, employee_id) stays unique across shifts.
            jdbc.update("UPDATE shift_assignments SET employee_id = ?, assigned_by = ? WHERE id = ?",
                    b.get("employee_id"), actor, a.get("id"));
            jdbc.update("UPDATE shift_assignments SET employee_id = ?, assigned_by = ? WHERE id = ?",
                    a.get("employee_id"), actor, b.get("id"));
        }
        jdbc.update("UPDATE shift_swap_requests SET status = ?, reviewed_by = ?, reviewed_at = CURRENT_TIMESTAMP "
                + "WHERE id = ?", accept ? "approved" : "rejected", actor, id);
        List<Long> recipients = new ArrayList<>();
        recipients.add(requestedBy);
        recipients.addAll(participants);
        notifyUsers(recipients, "Kết quả duyệt đổi ca",
                accept ? "Yêu cầu đã được duyệt. Lịch ca của bạn đã cập nhật."
                        : "Yêu cầu đổi ca đã bị từ chối. Lịch ca được giữ nguyên.", id);
    }
}
