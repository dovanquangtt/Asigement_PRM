package vn.anhemquan.prm.service;

import vn.anhemquan.prm.dto.Evidence;

import vn.anhemquan.prm.repository.Db;
import static vn.anhemquan.prm.service.AttendanceSupport.flag;
import static vn.anhemquan.prm.service.AttendanceSupport.instant;
import static vn.anhemquan.prm.service.AttendanceSupport.ts;

import com.fasterxml.jackson.core.type.TypeReference;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.exception.ApiException;

/** Check-in/out, device registration, branch attendance setup and exception review. */
@Service
public class AttendanceService {

    private static final Pattern BSSID = Pattern.compile("^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$");
    private static final List<String> TYPES = List.of("check_in", "check_out");

    private final AttendanceSupport sup;
    private final JdbcTemplate jdbc;
    private final AttendanceClock clock;

    public AttendanceService(AttendanceSupport sup, JdbcTemplate jdbc, AttendanceClock clock) {
        this.sup = sup;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    // ---- context / devices ---------------------------------------------------------------------

    public Map<String, Object> context(long assignmentId) {
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        Map<String, Object> row = sup.one(
                "SELECT a.id AS assignment_id, s.*, b.latitude, b.longitude, b.geofence_radius_m, b.require_gps, "
                        + "b.require_wifi, b.require_registered_device FROM shift_assignments a "
                        + "JOIN shifts s ON s.id = a.shift_id JOIN branches b ON b.id = s.branch_id "
                        + "WHERE a.id = ? AND a.employee_id = ? AND a.status = 'assigned'", assignmentId, me.get("id"));
        if (row == null) {
            throw ApiException.badRequest("Phân ca không hợp lệ hoặc không thuộc bạn.");
        }
        return row;
    }

    @Transactional
    public void registerDevice(String deviceIdentifier, String platform) {
        if (deviceIdentifier == null || deviceIdentifier.isBlank()) {
            throw ApiException.badRequest("Thiếu thông tin thiết bị thực tế.");
        }
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        Map<String, Object> existing = sup.one(
                "SELECT * FROM employee_devices WHERE device_identifier = ?", deviceIdentifier);
        if (existing != null) {
            if (((Number) existing.get("employee_id")).longValue() != ((Number) me.get("id")).longValue()
                    || existing.get("revoked_at") != null) {
                throw ApiException.badRequest("Thiết bị đã đăng ký cho tài khoản khác hoặc bị thu hồi.");
            }
            return;
        }
        jdbc.update("INSERT INTO employee_devices (employee_id, device_identifier, platform) VALUES (?, ?, ?)",
                me.get("id"), deviceIdentifier, platform);
    }

    public List<Map<String, Object>> myDevices() {
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        return jdbc.queryForList(
                "SELECT * FROM employee_devices WHERE employee_id = ? AND revoked_at IS NULL ORDER BY id DESC",
                me.get("id"));
    }

    public List<Map<String, Object>> devices() {
        sup.access.require("attendance.review");
        Long scope = sup.scope();
        return jdbc.queryForList(
                "SELECT d.*, e.full_name FROM employee_devices d JOIN employees e ON e.id = d.employee_id "
                        + (scope == null ? "" : "WHERE e.branch_id = ? ") + "ORDER BY d.id DESC",
                scope == null ? new Object[0] : new Object[] {scope});
    }

    @Transactional
    public void reviewDevice(long deviceId, boolean revoke) {
        sup.access.require("attendance.review");
        Map<String, Object> d = sup.one("SELECT * FROM employee_devices WHERE id = ?", deviceId);
        if (d == null) {
            throw ApiException.notFound("Không tìm thấy thiết bị.");
        }
        Map<String, Object> employee = sup.one("SELECT * FROM employees WHERE id = ?", d.get("employee_id"));
        sup.requireBranch(((Number) employee.get("branch_id")).longValue());
        if (employee.get("user_id") != null
                && ((Number) employee.get("user_id")).longValue() == sup.access.userId()) {
            throw ApiException.forbidden("Không thể tự duyệt thiết bị của mình.");
        }
        if (revoke) {
            jdbc.update("UPDATE employee_devices SET approved_by = NULL, revoked_at = ? WHERE id = ?",
                    ts(clock.now()), deviceId);
        } else {
            jdbc.update("UPDATE employee_devices SET approved_by = ?, revoked_at = NULL WHERE id = ?",
                    sup.access.userId(), deviceId);
        }
        sup.audit("device.review", "employee_devices", deviceId, null);
        sup.notify(sup.notifier.employeeUsers(List.of(((Number) d.get("employee_id")).longValue())),
                "Thiết bị điểm danh",
                revoke ? "Thiết bị đã bị thu hồi quyền điểm danh." : "Thiết bị đã được duyệt.",
                "employee_devices", deviceId);
    }

    @Transactional
    public void configureBranch(long branchId, Double latitude, Double longitude, Integer radius, String ssid,
            String bssid, Boolean requireOvertimeApproval) {
        if (latitude == null || longitude == null || radius == null || ssid == null || bssid == null
                || !Double.isFinite(latitude) || !Double.isFinite(longitude) || Math.abs(latitude) > 90
                || Math.abs(longitude) > 180 || radius <= 0 || ssid.isBlank() || !BSSID.matcher(bssid).matches()) {
            throw ApiException.badRequest("Tọa độ, bán kính hoặc BSSID Wi-Fi không hợp lệ.");
        }
        sup.access.require("employees.manage");
        sup.requireBranch(branchId);
        if (requireOvertimeApproval != null && !sup.isAdmin()) {
            throw ApiException.forbidden("Chỉ Admin được thay đổi chính sách tăng ca.");
        }
        int updated = jdbc.update(
                "UPDATE branches SET latitude = ?, longitude = ?, geofence_radius_m = ?"
                        + (requireOvertimeApproval != null ? ", require_overtime_approval = ?" : "") + " WHERE id = ?",
                requireOvertimeApproval != null
                        ? new Object[] {latitude, longitude, radius, requireOvertimeApproval, branchId}
                        : new Object[] {latitude, longitude, radius, branchId});
        if (updated == 0) {
            throw ApiException.notFound("Không tìm thấy chi nhánh.");
        }
        jdbc.update("INSERT INTO branch_wifi (branch_id, ssid, bssid, is_active) VALUES (?, ?, ?, TRUE) "
                + "ON DUPLICATE KEY UPDATE ssid = VALUES(ssid), is_active = TRUE",
                branchId, ssid.trim(), bssid.toLowerCase());
    }

    // ---- check-in / check-out ------------------------------------------------------------------

    /** Read-only preflight. The final confirmation validates again inside its transaction. */
    public Map<String, Object> inspect(long assignmentId, Evidence evidence) {
        Map<String, Object> context = context(assignmentId);
        Map<String, Object> me = sup.me();
        return sup.validateEvidence(context, ((Number) me.get("id")).longValue(), evidence, clock.now());
    }

    /** Server-validated attendance; rejected attempts are stored, only accepted ones update the timesheet. */
    @Transactional
    public Map<String, Object> record(long assignmentId, String type, Evidence evidence) {
        if (!TYPES.contains(type)) {
            throw ApiException.badRequest("Loại điểm danh không hợp lệ.");
        }
        Instant now = clock.now();
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        Map<String, Object> s = sup.one(AttendanceSupport.SHIFT_SQL
                + "WHERE a.id = ? AND a.employee_id = ? AND a.status = 'assigned'", assignmentId, me.get("id"));
        if (s == null) {
            throw ApiException.badRequest("Phân ca không thuộc bạn hoặc đã hoàn tất.");
        }
        if (!List.of("scheduled", "in_progress").contains(s.get("status"))) {
            throw ApiException.badRequest("Ca đã đóng/hủy.");
        }
        sup.ensureNotVoided(assignmentId);
        List<Map<String, Object>> previous = jdbc.queryForList(
                "SELECT * FROM attendance_events WHERE assignment_id = ? AND result = 'accepted'", assignmentId);
        if (previous.stream().anyMatch(r -> type.equals(r.get("event_type")))) {
            throw ApiException.badRequest("Bạn đã xác nhận lần điểm danh này.");
        }
        if ("check_out".equals(type) && previous.stream().noneMatch(r -> "check_in".equals(r.get("event_type")))) {
            throw ApiException.badRequest("Cần vào ca trước khi ra ca.");
        }
        if (sup.outsideWindow(s, type, now)) {
            throw ApiException.badRequest("Ngoài khoảng giờ cho phép điểm danh ca này.");
        }
        Map<String, Object> checks = sup.validateEvidence(s, ((Number) me.get("id")).longValue(), evidence, now);
        boolean accepted = flag(checks.get("accepted"));
        @SuppressWarnings("unchecked")
        List<String> failures = (List<String>) checks.get("failures");
        Long eventId = Db.insert(jdbc,
                "INSERT INTO attendance_events (assignment_id, event_type, occurred_at, device_id, latitude, longitude, "
                        + "gps_accuracy_m, wifi_ssid, wifi_bssid, device_valid, gps_valid, wifi_valid, result, "
                        + "rejection_reason, confirmed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", assignmentId, type, ts(now), checks.get("device_id"), evidence.latitude(),
                evidence.longitude(), evidence.accuracy(), evidence.ssid(), evidence.bssid(),
                flag(checks.get("device_valid")), flag(checks.get("gps_valid")), flag(checks.get("wifi_valid")),
                accepted ? "accepted" : "rejected", accepted ? null : String.join("; ", failures),
                accepted ? ts(now) : null);
        if (accepted) {
            sup.applyRecord(s, assignmentId, type, now);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", eventId);
        result.put("accepted", accepted);
        result.put("message", accepted ? "Đã xác nhận " + ("check_in".equals(type) ? "vào ca" : "ra ca")
                : String.join("\n", failures));
        return result;
    }

    public List<Map<String, Object>> history() {
        boolean managing = sup.access.can("attendance.review");
        Long scope = managing ? sup.scope() : null;
        if (!managing) {
            sup.access.require("attendance.self");
        }
        long uid = sup.access.userId();
        String base = "SELECT ev.*, COALESCE(sender.full_name, e.full_name) AS full_name FROM attendance_events ev "
                + "JOIN shift_assignments a ON a.id = ev.assignment_id JOIN shifts s ON s.id = a.shift_id "
                + "JOIN employees e ON e.id = a.employee_id LEFT JOIN employees sender ON sender.user_id = ev.submitted_by ";
        String order = "ORDER BY ev.occurred_at DESC";
        if (managing) {
            return scope == null ? jdbc.queryForList(base + order)
                    : jdbc.queryForList(base + "WHERE s.branch_id = ? " + order, scope);
        }
        return jdbc.queryForList(base + "WHERE ev.submitted_by = ? OR (ev.submitted_by IS NULL AND e.user_id = ?) "
                + order, uid, uid);
    }

    // ---- employee submissions (exceptions) -----------------------------------------------------

    @Transactional
    public long submit(long assignmentId, String type, Evidence evidence, Long selectedDeviceId,
            List<String> collectionIssues) {
        if (!TYPES.contains(type) || evidence.deviceIdentifier() == null || evidence.deviceIdentifier().isBlank()) {
            throw ApiException.badRequest("Thiếu loại điểm danh hoặc thông tin thiết bị thực tế.");
        }
        Instant now = clock.now();
        sup.access.require("attendance.self");
        Map<String, Object> me = sup.me();
        long employeeId = ((Number) me.get("id")).longValue();
        Map<String, Object> shift = sup.one(AttendanceSupport.SHIFT_SQL
                + "WHERE a.id = ? AND a.employee_id = ? AND a.status = 'assigned'", assignmentId, employeeId);
        if (shift == null) {
            throw ApiException.badRequest("Phân ca không thuộc bạn hoặc không còn hiệu lực.");
        }
        sup.ensureEditable(assignmentId);
        if (!List.of("scheduled", "in_progress").contains(shift.get("status"))) {
            throw ApiException.badRequest("Ca đã đóng hoặc hủy.");
        }
        sup.ensureNotVoided(assignmentId);
        List<Map<String, Object>> previous = jdbc.queryForList(
                "SELECT * FROM attendance_events WHERE assignment_id = ? AND result IN ('accepted', 'pending_review')",
                assignmentId);
        Map<String, Object> currentRecord = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?",
                assignmentId);
        if (currentRecord != null
                && currentRecord.get("check_in".equals(type) ? "check_in_at" : "check_out_at") != null) {
            throw ApiException.badRequest("Đã có giờ công. Muốn sửa hãy gửi yêu cầu điều chỉnh.");
        }
        if (previous.stream().anyMatch(r -> type.equals(r.get("event_type")))) {
            throw ApiException.badRequest("Bạn đã gửi hoặc đã được duyệt lần điểm danh này.");
        }
        Map<String, Object> selected = null;
        if (selectedDeviceId != null) {
            selected = sup.one("SELECT * FROM employee_devices WHERE id = ? AND employee_id = ? AND revoked_at IS NULL",
                    selectedDeviceId, employeeId);
            if (selected == null) {
                throw ApiException.badRequest("Chỉ chọn thiết bị của chính tài khoản, chưa bị thu hồi.");
            }
        }
        Map<String, Object> checks = sup.validateEvidence(shift, employeeId, evidence, now);
        List<String> warnings = new ArrayList<>();
        @SuppressWarnings("unchecked")
        List<String> failures = (List<String>) checks.get("failures");
        warnings.addAll(failures);
        if (collectionIssues != null) {
            warnings.addAll(collectionIssues);
        }
        if (selected != null && !selected.get("device_identifier").equals(evidence.deviceIdentifier())) {
            warnings.add("Thiết bị được chọn khác thiết bị thực tế gửi yêu cầu");
        }
        if (sup.outsideWindow(shift, type, now)) {
            warnings.add("Gửi ngoài khoảng giờ điểm danh thông thường");
        }
        if ("check_out".equals(type) && (currentRecord == null || currentRecord.get("check_in_at") == null)) {
            warnings.add("Thiếu giờ vào hoặc giờ vào đang chờ xử lý");
        }
        boolean automatic = warnings.isEmpty();
        boolean validCoordinates = evidence.latitude() != null && evidence.longitude() != null
                && Double.isFinite(evidence.latitude()) && Double.isFinite(evidence.longitude())
                && Math.abs(evidence.latitude()) <= 90 && Math.abs(evidence.longitude()) <= 180;
        boolean validAccuracy = evidence.accuracy() != null && Double.isFinite(evidence.accuracy())
                && evidence.accuracy() >= 0;
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("warnings", warnings);
        snapshot.put("branch_latitude", shift.get("latitude"));
        snapshot.put("branch_longitude", shift.get("longitude"));
        snapshot.put("radius_m", checks.get("radius_m"));
        snapshot.put("distance_m", checks.get("distance_m"));
        Long id = Db.insert(jdbc,
                "INSERT INTO attendance_events (assignment_id, event_type, occurred_at, device_id, "
                        + "actual_device_identifier, selected_device_identifier, device_platform, submitted_by, "
                        + "evidence_collected_at, evidence_mocked, latitude, longitude, gps_accuracy_m, wifi_ssid, "
                        + "wifi_bssid, device_valid, gps_valid, wifi_valid, result, confirmed_at, checks_snapshot) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", assignmentId, type, ts(now),
                selected != null ? selected.get("id") : checks.get("device_id"), evidence.deviceIdentifier(),
                selected != null ? selected.get("device_identifier") : evidence.deviceIdentifier(),
                evidence.platform(), sup.access.userId(), ts(evidence.collectedAt()), evidence.isMocked(),
                validCoordinates ? evidence.latitude() : null, validCoordinates ? evidence.longitude() : null,
                validAccuracy ? evidence.accuracy() : null, evidence.ssid(), evidence.bssid(),
                flag(checks.get("device_valid")), flag(checks.get("gps_valid")), flag(checks.get("wifi_valid")),
                automatic ? "accepted" : "pending_review", automatic ? ts(now) : null, sup.toJson(snapshot));
        long branchId = ((Number) shift.get("branch_id")).longValue();
        if (automatic) {
            sup.applyRecord(shift, assignmentId, type, now);
            Map<String, Object> r = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?", assignmentId);
            if ("PENDING".equals(r.get("overtime_status"))) {
                sup.notify(sup.reviewers(branchId), "Tăng ca chờ xác nhận",
                        me.get("full_name") + " có " + r.get("overtime_requested_minutes") + " phút tăng ca.",
                        "attendance_records", ((Number) r.get("id")).longValue());
            }
        } else {
            sup.notify(sup.reviewers(branchId), "Điểm danh bất thường cần kiểm tra",
                    me.get("full_name") + " gửi " + ("check_in".equals(type) ? "vào ca" : "ra ca") + " #" + id + ". "
                            + warnings.size() + " cảnh báo.", "attendance_events", id);
        }
        sup.audit("attendance.submit", "attendance_events", id, null);
        return id;
    }

    public List<Map<String, Object>> submissions() {
        Long scope = sup.scope();
        return jdbc.queryForList(
                "SELECT ev.*, COALESCE(sender.full_name, e.full_name) AS full_name, "
                        + "COALESCE(sender.employee_code, e.employee_code) AS employee_code, b.name AS branch_name, "
                        + "s.starts_at, s.ends_at FROM attendance_events ev "
                        + "JOIN shift_assignments a ON a.id = ev.assignment_id JOIN employees e ON e.id = a.employee_id "
                        + "JOIN shifts s ON s.id = a.shift_id JOIN branches b ON b.id = s.branch_id "
                        + "LEFT JOIN employees sender ON sender.user_id = ev.submitted_by "
                        + "WHERE ev.submitted_by IS NOT NULL " + (scope == null ? "" : "AND s.branch_id = ? ")
                        + "ORDER BY CASE WHEN ev.result = 'pending_review' THEN 0 ELSE 1 END, ev.id DESC",
                scope == null ? new Object[0] : new Object[] {scope});
    }

    @Transactional
    public void reviewSubmission(long eventId, boolean approve, String note) {
        sup.scope();
        String reason = note == null ? "" : note.trim();
        Map<String, Object> event = sup.one(
                "SELECT * FROM attendance_events WHERE id = ? AND result = 'pending_review'", eventId);
        if (event == null) {
            throw ApiException.badRequest("Yêu cầu không tồn tại hoặc đã xử lý.");
        }
        long assignmentId = ((Number) event.get("assignment_id")).longValue();
        Map<String, Object> assigned = sup.one(
                "SELECT e.user_id FROM shift_assignments a JOIN employees e ON e.id = a.employee_id WHERE a.id = ?",
                assignmentId);
        Object senderId = event.get("submitted_by") != null ? event.get("submitted_by") : assigned.get("user_id");
        if (senderId != null && ((Number) senderId).longValue() == sup.access.userId()) {
            throw ApiException.forbidden("Không thể tự duyệt điểm danh của mình.");
        }
        List<?> warnings;
        if (event.get("checks_snapshot") == null) {
            warnings = List.of("Dữ liệu điểm danh cũ, cần đối chiếu thủ công");
        } else {
            try {
                Map<String, Object> snap = sup.json.readValue((String) event.get("checks_snapshot"),
                        new TypeReference<Map<String, Object>>() { });
                warnings = (List<?>) snap.get("warnings");
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
        if ((!approve || !warnings.isEmpty()) && reason.isEmpty()) {
            throw ApiException.badRequest("Cần nhập lý do khi từ chối hoặc duyệt yêu cầu có cảnh báo.");
        }
        Map<String, Object> branch = sup.one(
                "SELECT s.branch_id FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id WHERE a.id = ?",
                assignmentId);
        sup.requireBranch(((Number) branch.get("branch_id")).longValue());
        Instant now = clock.now();
        String type = (String) event.get("event_type");
        if (approve) {
            sup.ensureEditable(assignmentId);
            Map<String, Object> shift = sup.one(
                    "SELECT a.employee_id, a.status AS assignment_status, s.*, COALESCE(t.break_minutes, 0) AS break_minutes, "
                            + "COALESCE(t.late_grace_minutes, 0) AS late_grace_minutes FROM shift_assignments a "
                            + "JOIN shifts s ON s.id = a.shift_id LEFT JOIN shift_templates t ON t.id = s.template_id "
                            + "WHERE a.id = ?", assignmentId);
            boolean owner = senderId != null && !jdbc.queryForList(
                    "SELECT 1 FROM employees WHERE id = ? AND user_id = ?", shift.get("employee_id"), senderId)
                    .isEmpty();
            if (!owner || !"assigned".equals(shift.get("assignment_status"))
                    || !List.of("scheduled", "in_progress").contains(shift.get("status"))) {
                throw ApiException.badRequest("Phân ca đã đổi người, đóng hoặc hủy. Không thể duyệt.");
            }
            List<Map<String, Object>> previous = jdbc.queryForList(
                    "SELECT * FROM attendance_events WHERE assignment_id = ? AND result = 'accepted'", assignmentId);
            if (previous.stream().anyMatch(r -> type.equals(r.get("event_type")))) {
                throw ApiException.badRequest("Đã có lần điểm danh được duyệt.");
            }
            Map<String, Object> record = sup.one("SELECT * FROM attendance_records WHERE assignment_id = ?",
                    assignmentId);
            if (record != null && record.get("check_in".equals(type) ? "check_in_at" : "check_out_at") != null) {
                throw ApiException.badRequest("Đã có giờ công. Hãy xử lý bằng yêu cầu điều chỉnh.");
            }
            if ("check_out".equals(type) && (record == null || record.get("check_in_at") == null)) {
                throw ApiException.badRequest("Hãy duyệt vào ca trước khi duyệt ra ca.");
            }
            sup.applyRecord(shift, assignmentId, type, instant(event.get("occurred_at")));
            jdbc.update("UPDATE attendance_records SET approved_by = ?, approved_at = ? WHERE assignment_id = ?",
                    sup.access.userId(), ts(now), assignmentId);
        }
        jdbc.update("UPDATE attendance_events SET result = ?, reviewed_by = ?, reviewed_at = ?, review_note = ?, "
                        + "confirmed_at = ?, rejection_reason = ? WHERE id = ?",
                approve ? "accepted" : "rejected", sup.access.userId(), ts(now), reason,
                approve ? ts(now) : null, approve ? null : reason, eventId);
        sup.notify(senderId == null ? List.of() : List.of(((Number) senderId).longValue()),
                "Kết quả duyệt điểm danh",
                "Yêu cầu #" + eventId + " " + (approve ? "đã được duyệt" : "bị từ chối") + ". " + reason,
                "attendance_events", eventId);
        sup.audit(approve ? "attendance.approve" : "attendance.reject", "attendance_events", eventId, null);
    }
}
