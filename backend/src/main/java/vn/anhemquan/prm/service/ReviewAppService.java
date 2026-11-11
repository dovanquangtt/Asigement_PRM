package vn.anhemquan.prm.service;

import static vn.anhemquan.prm.repository.AppRows.num;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.repository.AppRows;
import vn.anhemquan.prm.dto.AppDto.AdminSummary;
import vn.anhemquan.prm.dto.AppDto.AuditEntry;
import vn.anhemquan.prm.dto.AppDto.DeviceItem;
import vn.anhemquan.prm.dto.AppDto.ExceptionItem;
import vn.anhemquan.prm.dto.AppDto.ListItem;
import vn.anhemquan.prm.dto.AppDto.ManagerSummary;
import vn.anhemquan.prm.dto.AppDto.Page;
import vn.anhemquan.prm.dto.AppDto.Report;
import vn.anhemquan.prm.dto.AppDto.ReportRow;
import vn.anhemquan.prm.dto.AppDto.ReviewDetail;
import vn.anhemquan.prm.dto.AppDto.Verification;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;

/**
 * Manager (permission attendance.review, branch scoped) and Admin (permission users.manage, optional branch
 * filter) reporting: summary, list, detail, exceptions, devices and grouped reports.
 */
@Service
public class ReviewAppService {

    private static final Set<String> STATUSES = Set.of("SUCCESS", "PENDING_REVIEW", "REJECTED", "IN_PROGRESS",
            "MISSING_CHECK_IN", "MISSING_CHECK_OUT", "NOT_STARTED", "VOIDED");
    private static final Set<String> GROUPS = Set.of("employee", "branch", "date");

    private final AttendanceSupport sup;
    private final AttendanceManagementService management;
    private final AttendanceService attendance;
    private final AttendanceClock clock;
    private final AppRows rows;
    private final JdbcTemplate jdbc;
    private final Access access;
    private final Notifier notifier;

    public ReviewAppService(AttendanceSupport sup, AttendanceManagementService management,
            AttendanceService attendance, AttendanceClock clock, AppRows rows, JdbcTemplate jdbc, Access access,
            Notifier notifier) {
        this.sup = sup;
        this.management = management;
        this.attendance = attendance;
        this.clock = clock;
        this.rows = rows;
        this.jdbc = jdbc;
        this.access = access;
        this.notifier = notifier;
    }

    // ---- scope ---------------------------------------------------------------------------------

    /** Checks the role and returns the branch every query must be limited to (null = all branches). */
    private Long branchFilter(boolean admin, Long requestedBranch) {
        if (admin) {
            access.require("users.manage");
            return requestedBranch;
        }
        Long scope = sup.scope(); // requires attendance.review; null for Admin
        if (scope != null && requestedBranch != null && !scope.equals(requestedBranch)) {
            throw ApiException.forbidden("Chỉ được xử lý chấm công trong chi nhánh của mình.");
        }
        return scope != null ? scope : requestedBranch;
    }

    private LocalDate today() {
        return clock.now().atZone(AppTime.ZONE).toLocalDate();
    }

    private List<Map<String, Object>> dayRows(LocalDate date, Long branch, Long shiftId, String q) {
        StringBuilder where = new StringBuilder("a.status <> 'cancelled' AND s.status <> 'cancelled' AND "
                + AppRows.SHIFT_DAY + " = ?");
        List<Object> args = new ArrayList<>();
        args.add(java.sql.Date.valueOf(date));
        if (branch != null) {
            where.append(" AND s.branch_id = ?");
            args.add(branch);
        }
        if (shiftId != null) {
            where.append(" AND s.id = ?");
            args.add(shiftId);
        }
        if (q != null && !q.isBlank()) {
            where.append(" AND (e.full_name LIKE ? OR e.employee_code LIKE ?)");
            args.add("%" + q.trim() + "%");
            args.add("%" + q.trim() + "%");
        }
        return rows.rows(where + " ORDER BY s.starts_at, e.full_name", args.toArray());
    }

    private static boolean hasException(Map<String, Object> r) {
        return num(r.get("pending_events")) > 0 || num(r.get("pending_adjustments")) > 0
                || "PENDING".equals(r.get("overtime_status"));
    }

    // ---- summary -------------------------------------------------------------------------------

    private long[] counts(List<Map<String, Object>> day, Instant now) {
        Set<Object> checkedIn = new LinkedHashSet<>();
        long working = 0;
        long completed = 0;
        long late = 0;
        long notCheckedIn = 0;
        long exceptions = 0;
        for (Map<String, Object> r : day) {
            boolean in = r.get("check_in_at") != null;
            boolean out = r.get("check_out_at") != null;
            if (in) {
                checkedIn.add(r.get("employee_id"));
            }
            if (in && !out) {
                working++;
            }
            if (in && out) {
                completed++;
            }
            if (num(r.get("late_minutes")) > 0) {
                late++;
            }
            // Never "absent" before the shift starts; a pending check-in is an exception, not a no-show.
            if (!in && !AppRows.isVoided(r) && num(r.get("pending_in")) == 0
                    && !AttendanceSupport.instant(r.get("starts_at")).isAfter(now)) {
                notCheckedIn++;
            }
            if (hasException(r)) {
                exceptions++;
            }
        }
        return new long[] {checkedIn.size(), working, completed, late, notCheckedIn, exceptions};
    }

    private long employeeCount(Long branch) {
        return branch == null
                ? jdbc.queryForObject("SELECT COUNT(*) FROM employees WHERE status = 'active'", Long.class)
                : jdbc.queryForObject("SELECT COUNT(*) FROM employees WHERE status = 'active' AND branch_id = ?",
                        Long.class, branch);
    }

    public ManagerSummary managerSummary(LocalDate date, Long branchId) {
        Long branch = branchFilter(false, branchId);
        LocalDate day = date != null ? date : today();
        long[] c = counts(dayRows(day, branch, null, null), clock.now());
        return new ManagerSummary(day, branch, employeeCount(branch), c[0], c[1], c[2], c[3], c[4], c[5]);
    }

    public AdminSummary adminSummary(LocalDate date, Long branchId) {
        Long branch = branchFilter(true, branchId);
        LocalDate day = date != null ? date : today();
        long[] c = counts(dayRows(day, branch, null, null), clock.now());
        long shifts = jdbc.queryForObject("SELECT COUNT(*) FROM shifts s WHERE s.status <> 'cancelled' AND "
                + AppRows.SHIFT_DAY + " = ?" + (branch == null ? "" : " AND s.branch_id = ?"), Long.class,
                branch == null ? new Object[] {java.sql.Date.valueOf(day)}
                        : new Object[] {java.sql.Date.valueOf(day), branch});
        long branches = jdbc.queryForObject("SELECT COUNT(*) FROM branches", Long.class);
        return new AdminSummary(day, branch, employeeCount(branch), c[0], c[1], c[2], c[3], c[4], c[5], branches,
                shifts);
    }

    // ---- list / exceptions ---------------------------------------------------------------------

    private Map<Long, Map<String, Object>> lastEvents(List<Map<String, Object>> list) {
        return rows.events(list.stream().filter(r -> r.get("last_event_id") != null)
                .map(r -> num(r.get("last_event_id"))).toList());
    }

    private Verification verificationOf(Map<String, Object> r, Map<Long, Map<String, Object>> events) {
        return rows.verification(r.get("last_event_id") == null ? null : events.get(num(r.get("last_event_id"))), r);
    }

    public Page<ListItem> list(boolean admin, LocalDate date, Long branchId, Long shiftId, String status, String q,
            int page, int size) {
        Long branch = branchFilter(admin, branchId);
        if (status != null && !status.isBlank() && !STATUSES.contains(status)) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Trạng thái lọc không hợp lệ.");
        }
        Instant now = clock.now();
        List<Map<String, Object>> day = dayRows(date != null ? date : today(), branch, shiftId, q);
        List<Map<String, Object>> filtered = status == null || status.isBlank() ? day
                : day.stream().filter(r -> status.equals(rows.status(r, now))).toList();
        Page<Map<String, Object>> paged = Page.of(filtered, page, size);
        Map<Long, Map<String, Object>> events = lastEvents(paged.items());
        List<ListItem> items = paged.items().stream().map(r -> new ListItem(num(r.get("assignment_id")),
                rows.employee(r), rows.shift(r), AttendanceSupport.instant(r.get("check_in_at")),
                AttendanceSupport.instant(r.get("check_out_at")), rows.status(r, now),
                num(r.get("late_minutes")) > 0, num(r.get("late_minutes")), num(r.get("worked_minutes")),
                rows.brief(verificationOf(r, events)))).toList();
        return new Page<>(items, paged.page(), paged.size(), paged.totalItems(), paged.totalPages());
    }

    public Page<ExceptionItem> exceptions(boolean admin, LocalDate date, Long branchId, int page, int size) {
        Long branch = branchFilter(admin, branchId);
        Instant now = clock.now();
        List<Map<String, Object>> flagged = dayRows(date != null ? date : today(), branch, null, null).stream()
                .filter(ReviewAppService::hasException).toList();
        Page<Map<String, Object>> paged = Page.of(flagged, page, size);
        Map<Long, Map<String, Object>> events = lastEvents(paged.items());
        List<ExceptionItem> items = paged.items().stream().map(r -> new ExceptionItem(num(r.get("assignment_id")),
                rows.employee(r), rows.shift(r), AttendanceSupport.instant(r.get("check_in_at")),
                AttendanceSupport.instant(r.get("check_out_at")), rows.status(r, now),
                num(r.get("late_minutes")) > 0, num(r.get("late_minutes")), num(r.get("worked_minutes")),
                rows.brief(verificationOf(r, events)),
                String.join("; ", rows.exceptionsOf(r, rows.eventsOf(num(r.get("assignment_id"))))))).toList();
        return new Page<>(items, paged.page(), paged.size(), paged.totalItems(), paged.totalPages());
    }

    // ---- detail --------------------------------------------------------------------------------

    public ReviewDetail detail(boolean admin, long attendanceId) {
        branchFilter(admin, null);
        // 404 / branch 403 are enforced by the existing case detail (also returns the audit trail).
        Map<String, Object> caseDetail = management.caseDetail(attendanceId);
        Map<String, Object> row = rows.rows("a.id = ?", attendanceId).get(0);
        Instant now = clock.now();
        List<Map<String, Object>> events = rows.eventsOf(attendanceId);
        Map<String, Object> last = events.isEmpty() ? null : events.get(events.size() - 1);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> audit = (List<Map<String, Object>>) caseDetail.get("audit");
        List<AuditEntry> log = audit.stream().map(a -> new AuditEntry(AppRows.str(a.get("action")),
                AppRows.str(a.get("actor_name")), AttendanceSupport.instant(a.get("created_at")),
                AppRows.str(a.get("after_json")))).toList();
        return new ReviewDetail(rows.historyItem(row, now), rows.employee(row), rows.shift(row),
                rows.attendance(row, now), rows.verification(last, row),
                events.stream().map(e -> rows.eventInfo(e, row)).toList(), rows.exceptionsOf(row, events), log);
    }

    // ---- devices (admin) -----------------------------------------------------------------------

    private static String mask(String identifier) {
        if (identifier == null) {
            return null;
        }
        return identifier.length() <= 8 ? "…" + identifier.substring(Math.max(0, identifier.length() - 2))
                : identifier.substring(0, 4) + "…" + identifier.substring(identifier.length() - 4);
    }

    public Page<DeviceItem> devices(String status, String q, int page, int size) {
        access.require("users.manage");
        StringBuilder where = new StringBuilder("WHERE 1 = 1");
        List<Object> args = new ArrayList<>();
        if (status != null && !status.isBlank()) {
            switch (status) {
                case "REVOKED" -> where.append(" AND d.revoked_at IS NOT NULL");
                case "PENDING" -> where.append(" AND d.revoked_at IS NULL AND d.approved_by IS NULL");
                case "APPROVED" -> where.append(" AND d.revoked_at IS NULL AND d.approved_by IS NOT NULL");
                default -> throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
                        "Trạng thái lọc không hợp lệ.");
            }
        }
        if (q != null && !q.isBlank()) {
            where.append(" AND (e.full_name LIKE ? OR e.employee_code LIKE ?)");
            args.add("%" + q.trim() + "%");
            args.add("%" + q.trim() + "%");
        }
        List<DeviceItem> all = jdbc.queryForList(
                "SELECT d.id, d.employee_id, e.full_name, e.employee_code, d.device_identifier, d.platform, "
                        + "d.registered_at, d.revoked_at, d.approved_by, u.username AS approver "
                        + "FROM employee_devices d JOIN employees e ON e.id = d.employee_id "
                        + "LEFT JOIN users u ON u.id = d.approved_by " + where + " ORDER BY d.id DESC",
                args.toArray()).stream().map(d -> new DeviceItem(num(d.get("id")), num(d.get("employee_id")),
                        AppRows.str(d.get("full_name")), AppRows.str(d.get("employee_code")),
                        mask(AppRows.str(d.get("device_identifier"))), AppRows.str(d.get("platform")),
                        AttendanceSupport.instant(d.get("registered_at")),
                        d.get("revoked_at") != null ? "REVOKED" : d.get("approved_by") == null ? "PENDING"
                                : "APPROVED", AppRows.str(d.get("approver")),
                        AttendanceSupport.instant(d.get("revoked_at")))).toList();
        return Page.of(all, page, size);
    }

    @Transactional
    public void revokeDevice(long id, String reason) {
        access.require("users.manage");
        attendance.reviewDevice(id, true);
        notifier.audit(access.userId(), "device.revoke", "employee_devices", id, null,
                sup.toJson(Map.of("reason", reason == null ? "" : reason.trim())));
    }

    @Transactional
    public void approveDevice(long id) {
        access.require("users.manage");
        attendance.reviewDevice(id, false);
    }

    // ---- report (admin) ------------------------------------------------------------------------

    public Report report(LocalDate from, LocalDate to, String groupBy, Long branchId) {
        Long branch = branchFilter(true, branchId);
        LocalDate end = to != null ? to : today();
        LocalDate start = from != null ? from : end.withDayOfMonth(1);
        String group = groupBy == null || groupBy.isBlank() ? "employee" : groupBy;
        if (!GROUPS.contains(group) || end.isBefore(start)
                || ChronoUnit.DAYS.between(start, end) + 1 > EmployeeAppService.MAX_RANGE_DAYS) {
            throw ApiException.of(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Tham số báo cáo không hợp lệ.");
        }
        List<Object> args = new ArrayList<>(List.of(java.sql.Date.valueOf(start), java.sql.Date.valueOf(end)));
        String where = "a.status <> 'cancelled' AND s.status <> 'cancelled' AND " + AppRows.SHIFT_DAY
                + " BETWEEN ? AND ?";
        if (branch != null) {
            where += " AND s.branch_id = ?";
            args.add(branch);
        }
        Instant now = clock.now();
        Map<String, long[]> acc = new LinkedHashMap<>();
        Map<String, String> labels = new LinkedHashMap<>();
        for (Map<String, Object> r : rows.rows(where + " ORDER BY s.starts_at, e.full_name", args.toArray())) {
            String key = switch (group) {
                case "branch" -> String.valueOf(num(r.get("branch_id")));
                case "date" -> AppRows.localDate(r.get("starts_at")).toString();
                default -> String.valueOf(num(r.get("employee_id")));
            };
            labels.putIfAbsent(key, switch (group) {
                case "branch" -> AppRows.str(r.get("branch_name"));
                case "date" -> key;
                default -> AppRows.str(r.get("full_name"));
            });
            long[] a = acc.computeIfAbsent(key, k -> new long[7]);
            String status = rows.status(r, now);
            a[0]++;
            if ("SUCCESS".equals(status)) {
                a[1]++;
            }
            if (num(r.get("late_minutes")) > 0) {
                a[2]++;
            }
            if ("MISSING_CHECK_IN".equals(status) || "MISSING_CHECK_OUT".equals(status)) {
                a[3]++;
            }
            if (hasException(r)) {
                a[4]++;
            }
            if ("VOIDED".equals(status)) {
                a[5]++;
            }
            a[6] += num(r.get("worked_minutes"));
        }
        List<ReportRow> result = new ArrayList<>();
        acc.forEach((key, a) -> result.add(new ReportRow(key, labels.get(key), a[0], a[1], a[2], a[3], a[4], a[5],
                a[6])));
        return new Report(group, start, end, result);
    }
}
