package vn.anhemquan.prm.attendance;

import vn.anhemquan.prm.service.AttendanceClock;

import vn.anhemquan.prm.repository.Db;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

class AttendanceIntegrationTest extends AbstractIntegrationTest {

    static final AtomicInteger SEQ = new AtomicInteger((int) (System.currentTimeMillis() / 1000 % 1_000_000) * 10);
    static final String PASSWORD = "Passw0rd!!";
    static final double LAT = 10.7769;
    static final double LON = 106.7009;
    static final String BSSID = "aa:bb:cc:dd:ee:ff";
    static final Instant NOW = Instant.parse("2026-10-27T03:00:00Z");

    @MockBean
    AttendanceClock clock;

    @BeforeEach
    void fixClock() {
        when(clock.now()).thenReturn(NOW);
    }

    /** Branch + people created per test so tests never depend on each other's data. */
    class World {
        final int n = SEQ.incrementAndGet();
        final long branch = insertBranch(n);
        final long otherBranch = insertBranch(1000 + n);
        final String admin = "adm" + n;
        final String manager = "mgr" + n;
        final String otherManager = "omg" + n;
        final String employee = "emp" + n;
        final long adminUser = createUser(admin, PASSWORD, "admin", admin + "@x.vn");
        final long managerUser = createUser(manager, PASSWORD, "manager", manager + "@x.vn");
        final long otherManagerUser = createUser(otherManager, PASSWORD, "manager", otherManager + "@x.vn");
        final long employeeUser = createUser(employee, PASSWORD, "employee", employee + "@x.vn");
        final long adminEmp = insertEmployee(adminUser, "A" + n, branch);
        final long managerEmp = insertEmployee(managerUser, "M" + n, branch);
        final long otherManagerEmp = insertEmployee(otherManagerUser, "O" + n, otherBranch);
        final long employeeEmp = insertEmployee(employeeUser, "E" + n, branch);

        String tokenOf(String user) {
            try {
                return login(user, PASSWORD);
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
    }

    long insertBranch(int n) {
        Long id = Db.insert(jdbc,"INSERT INTO branches (code, name, latitude, longitude, geofence_radius_m) "
                + "VALUES (?, ?, ?, ?, 100)", "ATT" + n, "Branch " + n, LAT, LON);
        jdbc.update("INSERT INTO branch_wifi (branch_id, ssid, bssid) VALUES (?, 'AnhEm', ?)", id, BSSID);
        return id;
    }

    long insertEmployee(long userId, String code, long branch) {
        return Db.insert(jdbc,"INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                + "VALUES (?, ?, ?, ?, DATE '2026-01-01')", userId, code, "Name " + code,
                branch);
    }

    /** Shift from NOW+startOffset to NOW+endOffset (minutes), assigned to the employee. Returns assignment id. */
    long assign(World w, long employee, long createdBy, int startOffset, int endOffset) {
        Instant start = NOW.plus(Duration.ofMinutes(startOffset));
        Instant end = NOW.plus(Duration.ofMinutes(endOffset));
        Long shift = Db.insert(jdbc,"INSERT INTO shifts (branch_id, starts_at, ends_at, created_by) "
                + "VALUES (?, ?, ?, ?)", w.branch, Timestamp.from(start),
                Timestamp.from(end), createdBy);
        return Db.insert(jdbc,"INSERT INTO shift_assignments (shift_id, employee_id, assigned_by) "
                + "VALUES (?, ?, ?)", shift, employee, createdBy);
    }

    long approvedDevice(long employee, String identifier, long approver) {
        return Db.insert(jdbc,"INSERT INTO employee_devices (employee_id, device_identifier, platform, "
                + "approved_by) VALUES (?, ?, 'android', ?)", employee, identifier, approver);
    }

    Map<String, Object> evidence(String device, double lat) {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("deviceIdentifier", device);
        e.put("platform", "android");
        e.put("collectedAt", NOW.toString());
        e.put("latitude", lat);
        e.put("longitude", LON);
        e.put("accuracy", 10.0);
        e.put("ssid", "AnhEm");
        e.put("bssid", BSSID);
        e.put("mocked", false);
        return e;
    }

    ResultActions send(String token, String url, Object body) throws Exception {
        return mvc.perform(post(url).header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body)));
    }

    ResultActions fetch(String token, String url) throws Exception {
        return mvc.perform(get(url).header("Authorization", "Bearer " + token));
    }

    Map<String, Object> record(long assignment) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT * FROM attendance_records WHERE assignment_id = ?", assignment);
        return rows.isEmpty() ? null : rows.get(0);
    }

    long unreadNotifications(long user, String title) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.title = ?", Long.class, user, title);
    }

    // ---------------------------------------------------------------------------------------------

    @Test
    void validCheckInIsAcceptedAndRecordsLateness() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -10, 230);
        approvedDevice(w.employeeEmp, "dev-" + w.n, w.managerUser);
        String token = w.tokenOf(w.employee);

        send(token, "/api/attendance/assignments/" + a + "/record",
                Map.of("type", "check_in", "evidence", evidence("dev-" + w.n, LAT)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accepted").value(true))
                .andExpect(jsonPath("$.message").value("Đã xác nhận vào ca"));

        Map<String, Object> r = record(a);
        assertEquals("present", r.get("status"));
        assertEquals(10, ((Number) r.get("late_minutes")).intValue());
        assertEquals("LATE", r.get("arrival_status"));
        assertEquals("IN_PROGRESS", r.get("attendance_state"));
        assertEquals("in_progress", jdbc.queryForObject(
                "SELECT s.status FROM shifts s JOIN shift_assignments sa ON sa.shift_id = s.id WHERE sa.id = ?",
                String.class, a));

        send(token, "/api/attendance/assignments/" + a + "/record",
                Map.of("type", "check_in", "evidence", evidence("dev-" + w.n, LAT)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Bạn đã xác nhận lần điểm danh này."));
    }

    @Test
    void unapprovedDeviceAndFarGpsAreRejectedButStored() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -5, 235);
        String token = w.tokenOf(w.employee);

        send(token, "/api/attendance/assignments/" + a + "/record",
                Map.of("type", "check_in", "evidence", evidence("unknown-" + w.n, LAT + 0.01)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accepted").value(false))
                .andExpect(jsonPath("$.message").value(
                        "Thiết bị chưa được quản lý duyệt\nGPS ngoài phạm vi, thiếu chính xác hoặc vị trí giả"));

        assertNull(record(a));
        assertEquals("rejected", jdbc.queryForObject(
                "SELECT result FROM attendance_events WHERE assignment_id = ?", String.class, a));
    }

    @Test
    void checkOutNeedsCheckInAndComputesWorkedMinutes() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -60, 60);
        approvedDevice(w.employeeEmp, "dev-" + w.n, w.managerUser);
        String token = w.tokenOf(w.employee);

        send(token, "/api/attendance/assignments/" + a + "/record",
                Map.of("type", "check_out", "evidence", evidence("dev-" + w.n, LAT)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Cần vào ca trước khi ra ca."));

        // Check in one hour ago, check out now.
        when(clock.now()).thenReturn(NOW.minus(Duration.ofMinutes(60)));
        Map<String, Object> early = evidence("dev-" + w.n, LAT);
        early.put("collectedAt", NOW.minus(Duration.ofMinutes(60)).toString());
        send(token, "/api/attendance/assignments/" + a + "/record", Map.of("type", "check_in", "evidence", early))
                .andExpect(jsonPath("$.accepted").value(true));
        when(clock.now()).thenReturn(NOW);
        send(token, "/api/attendance/assignments/" + a + "/record",
                Map.of("type", "check_out", "evidence", evidence("dev-" + w.n, LAT)))
                .andExpect(jsonPath("$.accepted").value(true));

        Map<String, Object> r = record(a);
        assertEquals(60, ((Number) r.get("worked_minutes")).intValue());
        assertEquals("COMPLETED", r.get("attendance_state"));
    }

    @Test
    void submissionWithWarningsWaitsForReviewAndNotifiesScopedReviewers() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -5, 235);
        String token = w.tokenOf(w.employee);

        send(token, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence("phone-" + w.n, LAT)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").isNumber());

        assertNull(record(a));
        assertEquals("pending_review", jdbc.queryForObject(
                "SELECT result FROM attendance_events WHERE assignment_id = ?", String.class, a));
        assertEquals(1, unreadNotifications(w.managerUser, "Điểm danh bất thường cần kiểm tra"));
        assertEquals(1, unreadNotifications(w.adminUser, "Điểm danh bất thường cần kiểm tra"));
        assertEquals(0, unreadNotifications(w.otherManagerUser, "Điểm danh bất thường cần kiểm tra"));

        // A second pending submission of the same type is blocked.
        send(token, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence("phone-" + w.n, LAT)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Bạn đã gửi hoặc đã được duyệt lần điểm danh này."));
    }

    @Test
    void reviewerMustGiveReasonThenApprovalRecordsWorkTimeAndNotifiesSender() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -5, 235);
        String employeeToken = w.tokenOf(w.employee);
        send(employeeToken, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence("phone-" + w.n, LAT))).andExpect(status().isOk());
        long eventId = jdbc.queryForObject("SELECT id FROM attendance_events WHERE assignment_id = ?", Long.class, a);
        String managerToken = w.tokenOf(w.manager);

        send(managerToken, "/api/attendance/submissions/" + eventId + "/review", Map.of("approve", true, "note", ""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(
                        "Cần nhập lý do khi từ chối hoặc duyệt yêu cầu có cảnh báo."));
        send(w.tokenOf(w.otherManager), "/api/attendance/submissions/" + eventId + "/review",
                Map.of("approve", true, "note", "ok"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ được xử lý chấm công trong chi nhánh của mình."));
        send(employeeToken, "/api/attendance/submissions/" + eventId + "/review",
                Map.of("approve", true, "note", "ok")).andExpect(status().isForbidden());

        send(managerToken, "/api/attendance/submissions/" + eventId + "/review",
                Map.of("approve", true, "note", "Đã xác minh với quản lý ca")).andExpect(status().isOk());

        Map<String, Object> r = record(a);
        assertEquals("present", r.get("status"));
        assertEquals(w.managerUser, ((Number) r.get("approved_by")).longValue());
        assertEquals(1, unreadNotifications(w.employeeUser, "Kết quả duyệt điểm danh"));

        fetch(managerToken, "/api/attendance/submissions").andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id == " + eventId + ")].result").value("accepted"));
    }

    @Test
    void rejectionKeepsEvidenceAndAllowsResubmission() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -5, 235);
        String employeeToken = w.tokenOf(w.employee);
        send(employeeToken, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence("phone-" + w.n, LAT))).andExpect(status().isOk());
        long eventId = jdbc.queryForObject("SELECT id FROM attendance_events WHERE assignment_id = ?", Long.class, a);

        send(w.tokenOf(w.manager), "/api/attendance/submissions/" + eventId + "/review",
                Map.of("approve", false, "note", "Không đúng vị trí")).andExpect(status().isOk());

        assertEquals("rejected", jdbc.queryForObject("SELECT result FROM attendance_events WHERE id = ?",
                String.class, eventId));
        assertNull(record(a));
        send(employeeToken, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence("phone-" + w.n, LAT))).andExpect(status().isOk());
        assertEquals(2L, jdbc.queryForObject("SELECT COUNT(*) FROM attendance_events WHERE assignment_id = ?",
                Long.class, a));
    }

    @Test
    void adminCannotApproveOwnSubmission() throws Exception {
        World w = new World();
        long a = assign(w, w.adminEmp, w.adminUser, -5, 235);
        String adminToken = w.tokenOf(w.admin);
        send(adminToken, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence("admin-phone-" + w.n, LAT)))
                .andExpect(status().isOk());
        long eventId = jdbc.queryForObject("SELECT id FROM attendance_events WHERE assignment_id = ?", Long.class, a);

        send(adminToken, "/api/attendance/submissions/" + eventId + "/review",
                Map.of("approve", true, "note", "tự duyệt"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Không thể tự duyệt điểm danh của mình."));
    }

    @Test
    void deviceReviewIsScopedAndCannotBeSelfApproved() throws Exception {
        World w = new World();
        String employeeToken = w.tokenOf(w.employee);
        send(employeeToken, "/api/devices", Map.of("deviceIdentifier", "dv-" + w.n, "platform", "android"))
                .andExpect(status().isOk());
        long device = jdbc.queryForObject("SELECT id FROM employee_devices WHERE device_identifier = ?",
                Long.class, "dv-" + w.n);

        send(w.tokenOf(w.otherManager), "/api/devices/" + device + "/approve", Map.of())
                .andExpect(status().isForbidden());
        send(employeeToken, "/api/devices/" + device + "/approve", Map.of()).andExpect(status().isForbidden());
        send(w.tokenOf(w.manager), "/api/devices/" + device + "/approve", Map.of()).andExpect(status().isOk());
        assertEquals(w.managerUser, jdbc.queryForObject("SELECT approved_by FROM employee_devices WHERE id = ?",
                Long.class, device).longValue());

        send(w.tokenOf(w.manager), "/api/devices/" + device + "/revoke", Map.of()).andExpect(status().isOk());
        assertNotNull(jdbc.queryForObject("SELECT revoked_at FROM employee_devices WHERE id = ?",
                Timestamp.class, device));
        send(employeeToken, "/api/devices", Map.of("deviceIdentifier", "dv-" + w.n, "platform", "android"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Thiết bị đã đăng ký cho tài khoản khác hoặc bị thu hồi."));
    }

    @Test
    void adjustmentKeepsOriginalTimesRejectsSelfApprovalAndStaleChanges() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -120, -10);
        String employeeToken = w.tokenOf(w.employee);
        String managerToken = w.tokenOf(w.manager);
        Instant in = NOW.minus(Duration.ofMinutes(118));
        Instant out = NOW.minus(Duration.ofMinutes(12));

        send(employeeToken, "/api/attendance/assignments/" + a + "/adjustments", Map.of("reason", "  "))
                .andExpect(status().isBadRequest());
        send(employeeToken, "/api/attendance/assignments/" + a + "/adjustments",
                Map.of("checkIn", in.toString(), "checkOut", out.toString(), "reason", "Quên điểm danh"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").isNumber());
        long request = jdbc.queryForObject(
                "SELECT id FROM attendance_adjustment_requests ORDER BY id DESC LIMIT 1", Long.class);
        assertNotNull(record(a));
        assertNull(record(a).get("check_in_at"));

        send(employeeToken, "/api/attendance/assignments/" + a + "/adjustments",
                Map.of("checkIn", in.toString(), "reason", "lần hai"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Đã có yêu cầu điều chỉnh đang chờ duyệt."));
        send(employeeToken, "/api/attendance/adjustments/" + request + "/review",
                Map.of("approve", true, "note", "ok")).andExpect(status().isForbidden());
        send(managerToken, "/api/attendance/adjustments/" + request + "/review", Map.of("approve", true, "note", ""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhập nhận xét xử lý."));

        send(managerToken, "/api/attendance/adjustments/" + request + "/review",
                Map.of("approve", true, "note", "Đã đối chiếu")).andExpect(status().isOk());
        Map<String, Object> r = record(a);
        assertEquals("adjusted", r.get("status"));
        assertEquals(in, vn.anhemquan.prm.util.AppTime.toInstant(r.get("check_in_at")));
        assertEquals(106, ((Number) r.get("worked_minutes")).intValue());
        assertEquals(1, unreadNotifications(w.employeeUser, "Kết quả điều chỉnh công"));
        send(managerToken, "/api/attendance/adjustments/" + request + "/review",
                Map.of("approve", true, "note", "lại")).andExpect(status().isBadRequest());

        fetch(managerToken, "/api/attendance/assignments/" + a + "/detail").andExpect(status().isOk())
                .andExpect(jsonPath("$.record.status").value("adjusted"))
                .andExpect(jsonPath("$.adjustments[0].status").value("approved"))
                .andExpect(jsonPath("$.can_review").value(true));
    }

    @Test
    void staleAdjustmentIsRejectedWhenTimesChangedMeanwhile() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -120, -10);
        String employeeToken = w.tokenOf(w.employee);
        send(employeeToken, "/api/attendance/assignments/" + a + "/adjustments",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(118)).toString(), "reason", "Thiếu giờ vào"))
                .andExpect(status().isOk());
        long request = jdbc.queryForObject(
                "SELECT id FROM attendance_adjustment_requests ORDER BY id DESC LIMIT 1", Long.class);
        // Someone else changes the record after the request was filed.
        jdbc.update("UPDATE attendance_records SET check_in_at = ? WHERE assignment_id = ?",
                Timestamp.from(NOW.minus(Duration.ofMinutes(100))), a);

        send(w.tokenOf(w.manager), "/api/attendance/adjustments/" + request + "/review",
                Map.of("approve", true, "note", "duyệt"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Giờ công đã thay đổi sau khi gửi; cần kiểm tra lại yêu cầu."));
    }

    @Test
    void overtimeNeedsApprovalWhenBranchRequiresItAndRejectedOvertimeIsNotCounted() throws Exception {
        World w = new World();
        jdbc.update("UPDATE branches SET require_overtime_approval = TRUE WHERE id = ?", w.branch);
        long a = assign(w, w.employeeEmp, w.managerUser, -180, -60);
        long recordId = Db.insert(jdbc,"INSERT INTO attendance_records (assignment_id) VALUES (?)", a);
        jdbc.update("UPDATE attendance_records SET check_in_at = ?, check_out_at = ? WHERE id = ?",
                Timestamp.from(NOW.minus(Duration.ofMinutes(180))), Timestamp.from(NOW.minus(Duration.ofMinutes(30))),
                recordId);
        // Recalculation happens whenever a record is touched through the service; trigger it via adjustment review.
        String employeeToken = w.tokenOf(w.employee);
        send(employeeToken, "/api/attendance/assignments/" + a + "/adjustments",
                Map.of("checkOut", NOW.minus(Duration.ofMinutes(30)).toString(), "reason", "Ra ca muộn"))
                .andExpect(status().isOk());
        long request = jdbc.queryForObject(
                "SELECT id FROM attendance_adjustment_requests ORDER BY id DESC LIMIT 1", Long.class);
        String managerToken = w.tokenOf(w.manager);
        send(managerToken, "/api/attendance/adjustments/" + request + "/review",
                Map.of("approve", true, "note", "ok")).andExpect(status().isOk());

        Map<String, Object> r = record(a);
        assertEquals("PENDING", r.get("overtime_status"));
        assertEquals(30, ((Number) r.get("overtime_requested_minutes")).intValue());
        assertEquals(0, ((Number) r.get("overtime_minutes")).intValue());

        send(employeeToken, "/api/attendance/assignments/" + a + "/overtime/review",
                Map.of("approve", true, "note", "x")).andExpect(status().isForbidden());
        send(managerToken, "/api/attendance/assignments/" + a + "/overtime/review",
                Map.of("approve", false, "note", "Không được giao")).andExpect(status().isOk());
        r = record(a);
        assertEquals("REJECTED", r.get("overtime_status"));
        assertEquals(0, ((Number) r.get("overtime_minutes")).intValue());
        assertEquals(30, ((Number) r.get("overtime_requested_minutes")).intValue());
        send(managerToken, "/api/attendance/assignments/" + a + "/overtime/review",
                Map.of("approve", true, "note", "lại"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Không có tăng ca đang chờ duyệt."));
    }

    @Test
    void closingTheDayLocksRecordsAgainstFurtherChanges() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -180, -60);
        long recordId = Db.insert(jdbc,"INSERT INTO attendance_records (assignment_id) VALUES (?)", a);
        jdbc.update("UPDATE attendance_records SET check_in_at = ?, check_out_at = ?, status = 'present' "
                        + "WHERE id = ?", Timestamp.from(NOW.minus(Duration.ofMinutes(180))),
                Timestamp.from(NOW.minus(Duration.ofMinutes(60))), recordId);
        String managerToken = w.tokenOf(w.manager);

        fetch(managerToken, "/api/attendance/management?date=2026-10-27").andExpect(status().isOk())
                .andExpect(jsonPath("$.date").value("2026-10-27"))
                .andExpect(jsonPath("$.rows[?(@.assignment_id == " + a + ")].work_state").value("COMPLETED"));

        send(managerToken, "/api/attendance/days/close", Map.of("date", "2026-10-27", "note", "Chốt ngày"))
                .andExpect(status().isOk());
        assertNotNull(record(a).get("locked_at"));

        send(w.tokenOf(w.employee), "/api/attendance/assignments/" + a + "/adjustments",
                Map.of("checkOut", NOW.minus(Duration.ofMinutes(50)).toString(), "reason", "Sửa muộn"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Bảng công hoặc kỳ lương đã chốt, không thể thay đổi."));
    }

    @Test
    void closingRefusesIncompleteShiftsAndEmptyDays() throws Exception {
        World w = new World();
        assign(w, w.employeeEmp, w.managerUser, -180, -60);
        String managerToken = w.tokenOf(w.manager);

        send(managerToken, "/api/attendance/days/close", Map.of("date", "2026-10-27"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Còn ca chưa hoàn tất hoặc tăng ca chưa xử lý."));
        send(managerToken, "/api/attendance/days/close", Map.of("date", "2020-01-01"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Không có ca để chốt."));
    }

    @Test
    void managerOverviewIsBranchScopedWhileAdminSeesAll() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, w.managerUser, -180, -60);

        fetch(w.tokenOf(w.manager), "/api/attendance/management?date=2026-10-27").andExpect(status().isOk())
                .andExpect(jsonPath("$.rows[?(@.assignment_id == " + a + ")]").isNotEmpty())
                .andExpect(jsonPath("$.rows[?(@.assignment_id == " + a + ")].work_state").value("MISSING_CHECK_IN"));
        fetch(w.tokenOf(w.otherManager), "/api/attendance/management?date=2026-10-27")
                .andExpect(jsonPath("$.rows[?(@.assignment_id == " + a + ")]").isEmpty());
        fetch(w.tokenOf(w.admin), "/api/attendance/management?date=2026-10-27")
                .andExpect(jsonPath("$.rows[?(@.assignment_id == " + a + ")]").isNotEmpty());
        fetch(w.tokenOf(w.employee), "/api/attendance/management?date=2026-10-27").andExpect(status().isForbidden());
        fetch(w.tokenOf(w.otherManager), "/api/attendance/assignments/" + a + "/detail")
                .andExpect(status().isForbidden());
        fetch(w.tokenOf(w.employee), "/api/attendance/management?date=2026-10-27&self=true")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rows[?(@.assignment_id == " + a + ")]").isNotEmpty());
    }

    @Test
    void branchConfigurationValidatesInputAndOnlyAdminChangesOvertimePolicy() throws Exception {
        World w = new World();
        String managerToken = w.tokenOf(w.manager);
        Map<String, Object> ok = new LinkedHashMap<>();
        ok.put("latitude", 10.5);
        ok.put("longitude", 106.5);
        ok.put("radiusM", 80);
        ok.put("ssid", "Quan");
        ok.put("bssid", "AA:BB:CC:00:11:22");

        Map<String, Object> bad = new LinkedHashMap<>(ok);
        bad.put("bssid", "not-a-mac");
        putJson(managerToken, "/api/branches/" + w.branch + "/attendance-config", bad)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Tọa độ, bán kính hoặc BSSID Wi-Fi không hợp lệ."));
        putJson(managerToken, "/api/branches/" + w.otherBranch + "/attendance-config", ok)
                .andExpect(status().isForbidden());
        putJson(managerToken, "/api/branches/" + w.branch + "/attendance-config", ok).andExpect(status().isOk());
        assertEquals(80, jdbc.queryForObject("SELECT geofence_radius_m FROM branches WHERE id = ?", Integer.class,
                w.branch));
        assertTrue(jdbc.queryForObject("SELECT COUNT(*) FROM branch_wifi WHERE branch_id = ? "
                + "AND bssid = 'aa:bb:cc:00:11:22'", Long.class, w.branch) == 1);

        Map<String, Object> policy = new LinkedHashMap<>(ok);
        policy.put("requireOvertimeApproval", true);
        putJson(managerToken, "/api/branches/" + w.branch + "/attendance-config", policy)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ Admin được thay đổi chính sách tăng ca."));
        putJson(w.tokenOf(w.admin), "/api/branches/" + w.branch + "/attendance-config", policy)
                .andExpect(status().isOk());
        assertTrue(jdbc.queryForObject("SELECT require_overtime_approval FROM branches WHERE id = ?",
                Boolean.class, w.branch));
    }

    @Test
    void requestsWithoutTokenAreUnauthorized() throws Exception {
        mvc.perform(get("/api/attendance/history")).andExpect(status().isUnauthorized());
    }

    private ResultActions putJson(String token, String url, Object body) throws Exception {
        return mvc.perform(put(url).header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body)));
    }
}
