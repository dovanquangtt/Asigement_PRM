package vn.anhemquan.prm.service;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.util.AppTime;

/**
 * M12 Dashboard: HR, shift, attendance, leave, hours and payroll statistics for a date range (Vietnam calendar
 * days). Admin sees every branch, a manager only the own branch.
 */
@Service
public class DashboardService {

    private static final String LOCAL_DAY = "DATE(CONVERT_TZ(%s, '+00:00', '+07:00'))";

    private final JdbcTemplate jdbc;
    private final Access access;
    private final AttendanceClock clock;

    public DashboardService(JdbcTemplate jdbc, Access access, AttendanceClock clock) {
        this.jdbc = jdbc;
        this.access = access;
        this.clock = clock;
    }

    private static long num(Object value) {
        return value == null ? 0 : ((Number) value).longValue();
    }

    /** Null for Admin (all branches), otherwise the caller's branch. */
    private Long scope() {
        access.require("reports.view");
        boolean admin = !jdbc.queryForList(
                "SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id "
                        + "WHERE u.id = ? AND u.is_active AND r.code = 'admin'", access.userId()).isEmpty();
        if (admin) {
            return null;
        }
        List<Long> branch = jdbc.queryForList(
                "SELECT branch_id FROM employees WHERE user_id = ? AND status = 'active'", Long.class,
                access.userId());
        if (branch.isEmpty()) {
            throw ApiException.forbidden("Tài khoản chưa được liên kết hồ sơ nhân viên đang làm việc.");
        }
        return branch.get(0);
    }

    private Map<String, Object> row(String sql, List<Object> args) {
        return jdbc.queryForMap(sql, args.toArray());
    }

    public Map<String, Object> summary(LocalDate from, LocalDate to) {
        Long scope = scope();
        LocalDate today = clock.now().atZone(AppTime.ZONE).toLocalDate();
        LocalDate start = from != null ? from : today.withDayOfMonth(1);
        LocalDate end = to != null ? to : start.withDayOfMonth(start.lengthOfMonth());
        if (end.isBefore(start) || ChronoUnit.DAYS.between(start, end) > 366) {
            throw ApiException.badRequest("Khoảng ngày không hợp lệ.");
        }
        java.sql.Date a = java.sql.Date.valueOf(start);
        java.sql.Date b = java.sql.Date.valueOf(end);
        String shiftRange = LOCAL_DAY.formatted("s.starts_at") + " BETWEEN ? AND ?"
                + (scope == null ? "" : " AND s.branch_id = ?");
        List<Object> shiftArgs = new ArrayList<>(List.of(a, b));
        if (scope != null) {
            shiftArgs.add(scope);
        }

        List<Object> branchArg = scope == null ? List.of() : List.of(scope);
        Map<String, Object> employees = row(
                "SELECT COUNT(*) AS total, COALESCE(SUM(user_id IS NOT NULL), 0) AS with_account FROM employees "
                        + "WHERE status = 'active'" + (scope == null ? "" : " AND branch_id = ?"), branchArg);

        Map<String, Long> byStatus = new LinkedHashMap<>();
        long totalShifts = 0;
        for (Map<String, Object> r : jdbc.queryForList(
                "SELECT s.status, COUNT(*) AS n FROM shifts s WHERE " + shiftRange + " GROUP BY s.status",
                shiftArgs.toArray())) {
            byStatus.put((String) r.get("status"), num(r.get("n")));
            totalShifts += num(r.get("n"));
        }
        long assignments = num(row("SELECT COUNT(*) AS n FROM shift_assignments x JOIN shifts s ON s.id = x.shift_id "
                + "WHERE x.status <> 'cancelled' AND s.status <> 'cancelled' AND " + shiftRange, shiftArgs).get("n"));
        long understaffed = num(row("SELECT COUNT(*) AS n FROM shifts s WHERE s.status <> 'cancelled' AND "
                + shiftRange + " AND (SELECT COUNT(*) FROM shift_assignments x WHERE x.shift_id = s.id "
                + "AND x.status <> 'cancelled') < s.required_staff", shiftArgs).get("n"));

        Map<String, Object> att = row(
                "SELECT COUNT(*) AS records, COALESCE(SUM(r.arrival_status = 'ON_TIME'), 0) AS on_time, "
                        + "COALESCE(SUM(r.arrival_status = 'LATE'), 0) AS late, "
                        + "COALESCE(SUM(r.check_in_at IS NOT NULL AND r.check_out_at IS NULL), 0) AS open, "
                        + "COALESCE(SUM(r.worked_minutes), 0) AS worked, COALESCE(SUM(r.overtime_minutes), 0) AS overtime, "
                        + "COALESCE(SUM(r.late_minutes), 0) AS late_minutes FROM attendance_records r "
                        + "JOIN shift_assignments x ON x.id = r.assignment_id JOIN shifts s ON s.id = x.shift_id "
                        + "WHERE x.status <> 'cancelled' AND r.attendance_state <> 'VOIDED' AND " + shiftRange,
                shiftArgs);
        long pendingExceptions = num(row("SELECT COUNT(*) AS n FROM attendance_events ev "
                + "JOIN shift_assignments x ON x.id = ev.assignment_id JOIN shifts s ON s.id = x.shift_id "
                + "WHERE ev.result = 'pending_review' AND " + shiftRange, shiftArgs).get("n"));

        List<Object> leaveArgs = new ArrayList<>(List.of(b, a));
        if (scope != null) {
            leaveArgs.add(scope);
        }
        Map<String, Map<String, Object>> leave = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.queryForList(
                "SELECT l.status, COUNT(*) AS n, COALESCE(SUM(l.requested_minutes), 0) AS minutes FROM leave_requests l "
                        + "JOIN employees e ON e.id = l.employee_id WHERE " + LOCAL_DAY.formatted("l.starts_at")
                        + " <= ? AND " + LOCAL_DAY.formatted("l.ends_at") + " >= ?"
                        + (scope == null ? "" : " AND e.branch_id = ?") + " GROUP BY l.status", leaveArgs.toArray())) {
            leave.put((String) r.get("status"), r);
        }

        Map<String, Map<String, Object>> pay = new LinkedHashMap<>();
        for (Map<String, Object> r : jdbc.queryForList(
                "SELECT p.status, COUNT(*) AS n, COALESCE(SUM(p.base_pay_vnd + p.overtime_pay_vnd), 0) AS gross "
                        + "FROM payslips p JOIN payroll_periods pp ON pp.id = p.period_id "
                        + "JOIN employees e ON e.id = p.employee_id WHERE pp.starts_on <= ? AND pp.ends_on >= ?"
                        + (scope == null ? "" : " AND e.branch_id = ?") + " GROUP BY p.status", leaveArgs.toArray())) {
            pay.put((String) r.get("status"), r);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("from", start.toString());
        result.put("to", end.toString());
        result.put("employees", Map.of("active", num(employees.get("total")),
                "with_account", num(employees.get("with_account"))));
        Map<String, Object> shifts = new LinkedHashMap<>();
        shifts.put("total", totalShifts);
        for (String status : List.of("scheduled", "in_progress", "closed", "cancelled")) {
            shifts.put(status, byStatus.getOrDefault(status, 0L));
        }
        shifts.put("assignments", assignments);
        shifts.put("understaffed", understaffed);
        result.put("shifts", shifts);
        Map<String, Object> attendance = new LinkedHashMap<>();
        attendance.put("records", num(att.get("records")));
        attendance.put("on_time", num(att.get("on_time")));
        attendance.put("late", num(att.get("late")));
        attendance.put("missing_check_out", num(att.get("open")));
        attendance.put("pending_exceptions", pendingExceptions);
        result.put("attendance", attendance);
        Map<String, Object> leaves = new LinkedHashMap<>();
        for (String status : List.of("pending", "approved", "rejected")) {
            leaves.put(status, num(leave.getOrDefault(status, Map.of()).get("n")));
        }
        leaves.put("approved_minutes", num(leave.getOrDefault("approved", Map.of()).get("minutes")));
        result.put("leave", leaves);
        result.put("hours", Map.of("worked_minutes", num(att.get("worked")),
                "overtime_minutes", num(att.get("overtime")), "late_minutes", num(att.get("late_minutes"))));
        Map<String, Object> payroll = new LinkedHashMap<>();
        payroll.put("payslips", pay.values().stream().mapToLong(r -> num(r.get("n"))).sum());
        for (String status : List.of("draft", "approved", "paid")) {
            payroll.put(status, num(pay.getOrDefault(status, Map.of()).get("n")));
        }
        payroll.put("gross_vnd", pay.values().stream().mapToLong(r -> num(r.get("gross"))).sum());
        result.put("payroll", payroll);
        return result;
    }
}
