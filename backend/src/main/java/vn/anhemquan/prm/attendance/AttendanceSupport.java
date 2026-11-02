package vn.anhemquan.prm.attendance;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import vn.anhemquan.prm.common.Access;
import vn.anhemquan.prm.common.ApiException;
import vn.anhemquan.prm.common.Notifier;

/** Shared rules of the attendance module (port of the private helpers in the Flutter repository). */
@Component
public class AttendanceSupport {

    public static final String SHIFT_SQL = "SELECT a.id AS assignment_id, s.*, b.latitude, b.longitude, "
            + "b.geofence_radius_m, b.require_gps, b.require_wifi, b.require_registered_device, "
            + "COALESCE(t.break_minutes, 0) AS break_minutes, COALESCE(t.late_grace_minutes, 0) AS late_grace_minutes "
            + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id JOIN branches b ON b.id = s.branch_id "
            + "LEFT JOIN shift_templates t ON t.id = s.template_id ";

    final JdbcTemplate jdbc;
    final Access access;
    final Notifier notifier;
    final ObjectMapper json;

    public AttendanceSupport(JdbcTemplate jdbc, Access access, Notifier notifier, ObjectMapper json) {
        this.jdbc = jdbc;
        this.access = access;
        this.notifier = notifier;
        this.json = json;
    }

    // ---- value helpers -------------------------------------------------------------------------

    public static Instant instant(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Instant i) {
            return i;
        }
        if (value instanceof Timestamp t) {
            return t.toInstant();
        }
        if (value instanceof OffsetDateTime o) {
            return o.toInstant();
        }
        return Instant.parse(value.toString());
    }

    public static long minutes(Instant from, Instant to) {
        return Duration.between(from, to).toMinutes();
    }

    public static int intOf(Object value) {
        return ((Number) value).intValue();
    }

    public static boolean flag(Object value) {
        return Boolean.TRUE.equals(value);
    }

    public static Timestamp ts(Instant instant) {
        return instant == null ? null : Timestamp.from(instant);
    }

    public Map<String, Object> one(String sql, Object... args) {
        List<Map<String, Object>> rows = jdbc.queryForList(sql, args);
        return rows.isEmpty() ? null : rows.get(0);
    }

    /** Serialises a row for audit/before snapshots (timestamps as ISO instants). */
    public String toJson(Object value) {
        try {
            return json.writeValueAsString(jsonSafe(value));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private Object jsonSafe(Object value) {
        if (value instanceof Map<?, ?> map) {
            Map<String, Object> copy = new LinkedHashMap<>();
            map.forEach((k, v) -> copy.put(String.valueOf(k), jsonSafe(v)));
            return copy;
        }
        if (value instanceof Timestamp || value instanceof OffsetDateTime || value instanceof Instant) {
            return instant(value).toString();
        }
        return value;
    }

    public void audit(String action, String entity, long id, Object detail) {
        notifier.audit(access.userId(), action, entity, id, null, toJson(detail == null ? Map.of() : detail));
    }

    public void notify(List<Long> users, String title, String body, String entity, long entityId) {
        notifier.notify(access.userId(), users, title, body, entity, entityId);
    }

    // ---- identity and scope --------------------------------------------------------------------

    /** Active employee profile of the signed-in user (requires profile.self). */
    public Map<String, Object> me() {
        access.require("profile.self");
        Map<String, Object> row = one(
                "SELECT * FROM employees WHERE user_id = ? AND status = 'active'", access.userId());
        if (row == null) {
            throw ApiException.badRequest("Tài khoản chưa được liên kết hồ sơ nhân viên đang làm việc.");
        }
        return row;
    }

    public boolean isAdmin() {
        return !jdbc.queryForList(
                "SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles r ON r.id = ur.role_id "
                        + "WHERE u.id = ? AND u.is_active AND r.code = 'admin'", access.userId()).isEmpty();
    }

    /** Branch a reviewer may handle; null means every branch (Admin). */
    public Long scope() {
        access.require("attendance.review");
        if (isAdmin()) {
            return null;
        }
        return ((Number) me().get("branch_id")).longValue();
    }

    public void requireBranch(long branchId) {
        Long scope = scope();
        if (scope != null && scope != branchId) {
            throw ApiException.forbidden("Chỉ được xử lý chấm công trong chi nhánh của mình.");
        }
    }

    public List<Long> reviewers(long branchId) {
        return jdbc.queryForList(
                "SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id "
                        + "JOIN roles r ON r.id = ur.role_id "
                        + "LEFT JOIN employees e ON e.user_id = u.id AND e.status = 'active' "
                        + "WHERE u.is_active AND (r.code = 'admin' OR (r.code = 'manager' AND e.branch_id = ?))",
                Long.class, branchId);
    }

    public Map<String, Object> ownAssignment(long assignmentId, long employeeId) {
        Map<String, Object> row = one(
                "SELECT a.*, s.starts_at, s.ends_at, s.branch_id, s.status AS shift_status FROM shift_assignments a "
                        + "JOIN shifts s ON s.id = a.shift_id WHERE a.id = ? AND a.employee_id = ?",
                assignmentId, employeeId);
        if (row == null) {
            throw ApiException.badRequest("Phân ca không thuộc bạn.");
        }
        return row;
    }

    public void ensureEditable(long assignmentId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT r.locked_at FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id "
                        + "LEFT JOIN attendance_records r ON r.assignment_id = a.id WHERE a.id = ? AND "
                        + "(r.locked_at IS NOT NULL OR EXISTS (SELECT 1 FROM payslips p "
                        + "JOIN payroll_periods pp ON pp.id = p.period_id WHERE p.employee_id = a.employee_id "
                        + "AND p.status IN ('approved', 'paid') "
                        + "AND DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00')) BETWEEN pp.starts_on AND pp.ends_on))",
                assignmentId);
        if (!rows.isEmpty()) {
            throw ApiException.of(org.springframework.http.HttpStatus.BAD_REQUEST, "ATTENDANCE_LOCKED",
                    "Bảng công hoặc kỳ lương đã chốt, không thể thay đổi.");
        }
    }

    /** A voided timesheet (reviewer cancelled it) cannot be punched or adjusted by the employee any more. */
    public void ensureNotVoided(long assignmentId) {
        if (!jdbc.queryForList("SELECT 1 FROM attendance_records WHERE assignment_id = ? "
                + "AND attendance_state = 'VOIDED'", assignmentId).isEmpty()) {
            throw ApiException.of(org.springframework.http.HttpStatus.BAD_REQUEST, "ATTENDANCE_VOIDED",
                    AttendanceSheetService.VOIDED_MESSAGE);
        }
    }

    // ---- evidence validation -------------------------------------------------------------------

    /** Compares the evidence with device registrations, branch GPS fence and Wi-Fi; never trusts the client. */
    public Map<String, Object> validateEvidence(Map<String, Object> s, long employeeId, Evidence ev, Instant clock) {
        String deviceId = ev.deviceIdentifier();
        List<Map<String, Object>> approved = jdbc.queryForList(
                "SELECT * FROM employee_devices WHERE device_identifier = ? AND employee_id = ? "
                        + "AND revoked_at IS NULL AND approved_by IS NOT NULL", deviceId, employeeId);
        boolean deviceValid = !approved.isEmpty();
        Map<String, Object> registration = one("SELECT * FROM employee_devices WHERE device_identifier = ?", deviceId);
        String deviceStatus = registration == null ? "unregistered"
                : ((Number) registration.get("employee_id")).longValue() != employeeId ? "another_employee"
                : registration.get("revoked_at") != null ? "revoked"
                : registration.get("approved_by") == null ? "pending" : "approved";

        boolean gpsValid = false;
        Double distanceMeters = null;
        int radius = intOf(s.get("geofence_radius_m"));
        if (s.get("latitude") != null && s.get("longitude") != null && ev.latitude() != null
                && ev.longitude() != null && ev.accuracy() != null && Double.isFinite(ev.latitude())
                && Math.abs(ev.latitude()) <= 90 && Double.isFinite(ev.longitude())
                && Math.abs(ev.longitude()) <= 180 && Double.isFinite(ev.accuracy()) && !ev.isMocked()) {
            double lat1 = Math.toRadians(((Number) s.get("latitude")).doubleValue());
            double lat2 = Math.toRadians(ev.latitude());
            double dl = lat2 - lat1;
            double dn = Math.toRadians(ev.longitude() - ((Number) s.get("longitude")).doubleValue());
            double a = Math.pow(Math.sin(dl / 2), 2) + Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(dn / 2), 2);
            double distance = 6371000 * 2 * Math.atan2(
                    Math.sqrt(Math.min(1, Math.max(0, a))), Math.sqrt(Math.min(1, Math.max(0, 1 - a))));
            distanceMeters = distance;
            gpsValid = distance <= radius && ev.accuracy() >= 0 && ev.accuracy() <= Math.min(100, radius);
        }

        boolean wifiValid = ev.bssid() != null && ev.ssid() != null && !jdbc.queryForList(
                "SELECT 1 FROM branch_wifi WHERE branch_id = ? AND lower(bssid) = ? AND ssid = ? AND is_active",
                s.get("branch_id"), ev.bssid().toLowerCase(), ev.ssid()).isEmpty();

        boolean fresh = Duration.between(clock, ev.collectedAt()).abs().compareTo(Duration.ofMinutes(2)) <= 0;
        boolean requireDevice = flag(s.get("require_registered_device"));
        boolean requireGps = flag(s.get("require_gps"));
        boolean requireWifi = flag(s.get("require_wifi"));
        List<String> failures = new ArrayList<>();
        if (requireDevice && !deviceValid) {
            failures.add("Thiết bị chưa được quản lý duyệt");
        }
        if (requireGps && !gpsValid) {
            failures.add("GPS ngoài phạm vi, thiếu chính xác hoặc vị trí giả");
        }
        if (requireWifi && !wifiValid) {
            failures.add("Wi-Fi không đúng chi nhánh");
        }
        if (!fresh) {
            failures.add("Dữ liệu xác thực đã quá hạn");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("accepted", failures.isEmpty());
        result.put("device_valid", deviceValid);
        result.put("device_status", deviceStatus);
        result.put("registration_id", registration == null ? null : registration.get("id"));
        result.put("gps_valid", gpsValid);
        result.put("wifi_valid", wifiValid);
        result.put("device_ok", !requireDevice || deviceValid);
        result.put("gps_ok", !requireGps || gpsValid);
        result.put("wifi_ok", !requireWifi || wifiValid);
        result.put("fresh", fresh);
        result.put("device_id", approved.isEmpty() ? null : approved.get(0).get("id"));
        result.put("distance_m", distanceMeters);
        result.put("radius_m", radius);
        result.put("failures", failures);
        return result;
    }

    public boolean outsideWindow(Map<String, Object> s, String type, Instant clock) {
        Instant start = instant(s.get("starts_at"));
        Instant end = instant(s.get("ends_at"));
        return clock.isBefore(start.minus(Duration.ofHours(1))) || clock.isAfter(end.plus(Duration.ofHours(12)))
                || ("check_in".equals(type) && clock.isAfter(end));
    }

    // ---- record maintenance --------------------------------------------------------------------

    /** Applies an accepted check-in/out to attendance_records and recalculates the derived metrics. */
    public void applyRecord(Map<String, Object> s, long assignmentId, String type, Instant clock) {
        ensureEditable(assignmentId);
        Instant start = instant(s.get("starts_at"));
        Instant end = instant(s.get("ends_at"));
        int breakMinutes = intOf(s.get("break_minutes"));
        if ("check_in".equals(type)) {
            long late = Math.max(0, minutes(start, clock) - intOf(s.get("late_grace_minutes")));
            Map<String, Object> current = one("SELECT id FROM attendance_records WHERE assignment_id = ?", assignmentId);
            if (current == null) {
                jdbc.update("INSERT INTO attendance_records (assignment_id, check_in_at, late_minutes, status) "
                        + "VALUES (?, ?, ?, 'present')", assignmentId, ts(clock), late);
            } else {
                jdbc.update("UPDATE attendance_records SET check_in_at = ?, late_minutes = ?, status = 'present' "
                        + "WHERE id = ?", ts(clock), late, current.get("id"));
            }
            jdbc.update("UPDATE shifts SET status = 'in_progress' WHERE id = ?", s.get("id"));
        } else {
            Map<String, Object> record = one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
            if (record == null || record.get("check_in_at") == null) {
                throw ApiException.badRequest("Cần vào ca trước khi ra ca.");
            }
            Instant inAt = instant(record.get("check_in_at"));
            if (clock.isBefore(inAt)) {
                throw ApiException.badRequest("Giờ ra ca trước giờ vào ca.");
            }
            long worked = Math.max(0, minutes(inAt, clock) - breakMinutes);
            long planned = minutes(start, end) - breakMinutes;
            jdbc.update("UPDATE attendance_records SET check_out_at = ?, worked_minutes = ?, overtime_minutes = ? "
                    + "WHERE id = ?", ts(clock), worked, Math.max(0, worked - planned), record.get("id"));
        }
        refreshMetrics(assignmentId);
    }

    /** Recomputes late/worked/overtime and the overtime approval state from the stored times. */
    public void refreshMetrics(long assignmentId) {
        Map<String, Object> r = one(
                "SELECT r.*, s.starts_at, s.ends_at, b.require_overtime_approval, "
                        + "COALESCE(t.break_minutes, 0) AS break_minutes, COALESCE(t.late_grace_minutes, 0) AS late_grace_minutes "
                        + "FROM attendance_records r JOIN shift_assignments a ON a.id = r.assignment_id "
                        + "JOIN shifts s ON s.id = a.shift_id JOIN branches b ON b.id = s.branch_id "
                        + "LEFT JOIN shift_templates t ON t.id = s.template_id WHERE a.id = ?", assignmentId);
        if (r == null) {
            return;
        }
        Instant inAt = instant(r.get("check_in_at"));
        Instant outAt = instant(r.get("check_out_at"));
        if (outAt != null && (inAt == null || outAt.isBefore(inAt))) {
            throw ApiException.badRequest("Giờ ra phải từ giờ vào trở đi.");
        }
        long late = inAt == null ? 0
                : Math.max(0, minutes(instant(r.get("starts_at")), inAt) - intOf(r.get("late_grace_minutes")));
        long worked = inAt == null || outAt == null ? 0
                : Math.max(0, minutes(inAt, outAt) - intOf(r.get("break_minutes")));
        long extra = outAt == null ? 0 : Math.min(worked, Math.max(0, minutes(instant(r.get("ends_at")), outAt)));
        boolean needsReview = flag(r.get("require_overtime_approval")) && extra > 0;
        String status = (String) r.get("overtime_status");
        boolean previousDecision = intOf(r.get("overtime_requested_minutes")) == extra
                && ("APPROVED".equals(status) || "REJECTED".equals(status));
        String otState = needsReview ? (previousDecision ? status : "PENDING") : "NOT_REQUIRED";
        String arrival = inAt == null ? null : late > 0 ? "LATE" : "ON_TIME";
        String state = inAt == null ? "MISSING_CHECK_IN" : outAt == null ? "IN_PROGRESS" : "COMPLETED";
        long overtime = !needsReview || "APPROVED".equals(otState) ? extra : 0;
        jdbc.update("UPDATE attendance_records SET worked_minutes = ?, late_minutes = ?, arrival_status = ?, "
                        + "attendance_state = ?, overtime_requested_minutes = ?, overtime_status = ?, overtime_minutes = ?"
                        + (previousDecision ? ""
                        : ", overtime_reviewed_by = NULL, overtime_reviewed_at = NULL, overtime_review_note = NULL")
                        + " WHERE assignment_id = ?",
                worked, late, arrival, state, needsReview ? extra : 0, otState, overtime, assignmentId);
    }
}
