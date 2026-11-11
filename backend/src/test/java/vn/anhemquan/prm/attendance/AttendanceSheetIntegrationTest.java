package vn.anhemquan.prm.attendance;

import vn.anhemquan.prm.service.AttendanceClock;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import vn.anhemquan.prm.repository.Db;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

/** Attendance sheet (per employee, date range) and reviewers' direct edit / void. */
class AttendanceSheetIntegrationTest extends AbstractIntegrationTest {

    static final String PASSWORD = "Passw0rd!!";
    /** 03:00 UTC = 10:00 in Vietnam, 2026-10-27. */
    static final Instant NOW = Instant.parse("2026-10-27T03:00:00Z");
    static final String DAY = "2026-10-27";
    static final String LOCKED = "Bảng công hoặc kỳ lương đã chốt, không thể thay đổi.";
    static final String VOIDED = "Công đã bị hủy. Hãy liên hệ quản lý.";

    @MockBean
    AttendanceClock clock;

    @BeforeEach
    void fixClock() {
        when(clock.now()).thenReturn(NOW);
    }

    /** Branches and people created per test (unique suffix, safe on a shared database). */
    class World {
        final String sfx = UUID.randomUUID().toString().substring(0, 8);
        final long branch = insertBranch("SHA" + sfx);
        final long otherBranch = insertBranch("SHB" + sfx);
        final String admin = "sadm" + sfx;
        final String manager = "smgr" + sfx;
        final String otherManager = "somg" + sfx;
        final String employee = "semp" + sfx;
        final String colleague = "scol" + sfx;
        final long adminUser = createUser(admin, PASSWORD, "admin", admin + "@x.vn");
        final long managerUser = createUser(manager, PASSWORD, "manager", manager + "@x.vn");
        final long otherManagerUser = createUser(otherManager, PASSWORD, "manager", otherManager + "@x.vn");
        final long employeeUser = createUser(employee, PASSWORD, "employee", employee + "@x.vn");
        final long colleagueUser = createUser(colleague, PASSWORD, "employee", colleague + "@x.vn");
        final long adminEmp = insertEmployee(adminUser, "SA" + sfx, branch);
        final long managerEmp = insertEmployee(managerUser, "SM" + sfx, branch);
        final long otherManagerEmp = insertEmployee(otherManagerUser, "SO" + sfx, otherBranch);
        final long employeeEmp = insertEmployee(employeeUser, "SE" + sfx, branch);
        final long colleagueEmp = insertEmployee(colleagueUser, "SC" + sfx, branch);

        String tokenOf(String user) {
            try {
                return login(user, PASSWORD);
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
    }

    long insertBranch(String code) {
        return Db.insert(jdbc, "INSERT INTO branches (code, name) VALUES (?, ?)", code, "Branch " + code);
    }

    long insertEmployee(long userId, String code, long branch) {
        return Db.insert(jdbc, "INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                + "VALUES (?, ?, ?, ?, DATE '2026-01-01')", userId, code, "Name " + code, branch);
    }

    /** Shift from NOW+start to NOW+end minutes in the world's branch, assigned to the employee. */
    long assign(World w, long employee, int startOffset, int endOffset) {
        Long shift = Db.insert(jdbc, "INSERT INTO shifts (branch_id, starts_at, ends_at, created_by) VALUES (?, ?, ?, ?)",
                w.branch, Timestamp.from(NOW.plus(Duration.ofMinutes(startOffset))),
                Timestamp.from(NOW.plus(Duration.ofMinutes(endOffset))), w.adminUser);
        return Db.insert(jdbc, "INSERT INTO shift_assignments (shift_id, employee_id, assigned_by) VALUES (?, ?, ?)",
                shift, employee, w.adminUser);
    }

    long record(long assignment, Integer inOffset, Integer outOffset, int worked) {
        return Db.insert(jdbc, "INSERT INTO attendance_records (assignment_id, check_in_at, check_out_at, "
                + "worked_minutes, status, attendance_state) VALUES (?, ?, ?, ?, 'present', ?)", assignment,
                inOffset == null ? null : Timestamp.from(NOW.plus(Duration.ofMinutes(inOffset))),
                outOffset == null ? null : Timestamp.from(NOW.plus(Duration.ofMinutes(outOffset))), worked,
                outOffset != null ? "COMPLETED" : "IN_PROGRESS");
    }

    long event(long assignment, String type, String result, int offset) {
        return Db.insert(jdbc, "INSERT INTO attendance_events (assignment_id, event_type, occurred_at, device_valid, "
                + "gps_valid, wifi_valid, result, rejection_reason) VALUES (?, ?, ?, TRUE, TRUE, TRUE, ?, ?)",
                assignment, type, Timestamp.from(NOW.plus(Duration.ofMinutes(offset))), result,
                "rejected".equals(result) ? "Sai Wi-Fi" : null);
    }

    ResultActions send(String token, String url, Object body) throws Exception {
        return mvc.perform(post(url).header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body)));
    }

    ResultActions fetch(String token, String url) throws Exception {
        return mvc.perform(get(url).header("Authorization", "Bearer " + token));
    }

    JsonNode body(ResultActions result) throws Exception {
        return json.readTree(result.andReturn().getResponse().getContentAsString());
    }

    String statusOf(JsonNode sheet, long assignment) {
        for (JsonNode row : sheet.get("rows")) {
            if (row.get("assignment_id").asLong() == assignment) {
                return row.get("sheet_status").asText();
            }
        }
        return null;
    }

    Map<String, Object> recordRow(long assignment) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT * FROM attendance_records WHERE assignment_id = ?", assignment);
        return rows.isEmpty() ? null : rows.get(0);
    }

    long notifications(long user, String title) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.title = ?", Long.class, user, title);
    }

    long audits(String action, long recordId) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM audit_logs WHERE action = ? AND entity_id = ?",
                Long.class, action, recordId);
    }

    Map<String, Object> evidence() {
        Map<String, Object> e = new LinkedHashMap<>();
        e.put("deviceIdentifier", "dev-sheet");
        e.put("platform", "android");
        e.put("collectedAt", NOW.toString());
        e.put("latitude", 10.7769);
        e.put("longitude", 106.7009);
        e.put("accuracy", 10.0);
        e.put("ssid", "AnhEm");
        e.put("bssid", "aa:bb:cc:dd:ee:ff");
        e.put("mocked", false);
        return e;
    }

    String sheetUrl(Long employeeId, String from, String to) {
        return "/api/attendance/sheet?from=" + from + "&to=" + to + (employeeId == null ? "" : "&employeeId=" + employeeId);
    }

    // ---------------------------------------------------------------------------------------------

    @Test
    void employeeSeesOnlyOwnSheetWithClearStatuses() throws Exception {
        World w = new World();
        long success = assign(w, w.employeeEmp, -240, -60);
        record(success, -235, -60, 175);
        long pending = assign(w, w.employeeEmp, -30, 200);
        event(pending, "check_in", "pending_review", -20);
        long rejected = assign(w, w.employeeEmp, -20, 180);
        event(rejected, "check_in", "rejected", -15);
        long missing = assign(w, w.employeeEmp, -300, -100);
        long notStarted = assign(w, w.employeeEmp, 30, 200);
        long colleagueShift = assign(w, w.colleagueEmp, -240, -60);

        JsonNode sheet = body(fetch(w.tokenOf(w.employee), sheetUrl(null, DAY, DAY)).andExpect(status().isOk())
                .andExpect(jsonPath("$.employee.id").value(w.employeeEmp)));

        assertEquals("SUCCESS", statusOf(sheet, success));
        assertEquals("PENDING_REVIEW", statusOf(sheet, pending));
        assertEquals("REJECTED", statusOf(sheet, rejected));
        assertEquals("MISSING_CHECK_IN", statusOf(sheet, missing));
        assertEquals("NOT_STARTED", statusOf(sheet, notStarted));
        assertNull(statusOf(sheet, colleagueShift), "another employee's row must not be visible");
        JsonNode summary = sheet.get("summary");
        assertEquals(5, summary.get("total").asInt());
        assertEquals(1, summary.get("success").asInt());
        assertEquals(1, summary.get("pending_review").asInt());
        assertEquals(1, summary.get("rejected").asInt());
        assertEquals(1, summary.get("missing").asInt());
        assertEquals(175, summary.get("worked_minutes").asInt());
        for (JsonNode row : sheet.get("rows")) {
            if (row.get("assignment_id").asLong() == rejected) {
                assertEquals("Sai Wi-Fi", row.get("last_rejection_reason").asText());
            }
        }

        fetch(w.tokenOf(w.employee), sheetUrl(w.colleagueEmp, DAY, DAY)).andExpect(status().isForbidden());
    }

    @Test
    void sheetRangeIsValidated() throws Exception {
        World w = new World();
        String token = w.tokenOf(w.employee);

        fetch(token, sheetUrl(null, "2026-10-28", "2026-10-27")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Khoảng ngày không hợp lệ."));
        // 94 days is one too many; 93 days (Sep 30 - Dec 31) is still allowed.
        fetch(token, sheetUrl(null, "2026-09-29", "2026-12-31")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Khoảng ngày không hợp lệ."));
        fetch(token, sheetUrl(null, "2026-09-30", "2026-12-31")).andExpect(status().isOk());
    }

    @Test
    void reviewersScopeFollowsBranchAndEmployeeListIsScoped() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);
        record(a, -235, -60, 175);

        JsonNode asManager = body(fetch(w.tokenOf(w.manager), sheetUrl(w.employeeEmp, DAY, DAY))
                .andExpect(status().isOk()));
        assertEquals("SUCCESS", statusOf(asManager, a));
        fetch(w.tokenOf(w.admin), sheetUrl(w.employeeEmp, DAY, DAY)).andExpect(status().isOk());
        fetch(w.tokenOf(w.otherManager), sheetUrl(w.employeeEmp, DAY, DAY)).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ được xử lý chấm công trong chi nhánh của mình."));

        JsonNode managerList = body(fetch(w.tokenOf(w.manager), "/api/attendance/sheet/employees")
                .andExpect(status().isOk()));
        List<Long> ids = new java.util.ArrayList<>();
        managerList.forEach(n -> ids.add(n.get("id").asLong()));
        assertTrue(ids.contains(w.employeeEmp) && ids.contains(w.colleagueEmp));
        assertTrue(!ids.contains(w.otherManagerEmp), "other branch employee must be hidden from the manager");

        JsonNode own = body(fetch(w.tokenOf(w.employee), "/api/attendance/sheet/employees").andExpect(status().isOk()));
        assertEquals(1, own.size());
        assertEquals(w.employeeEmp, own.get(0).get("id").asLong());
    }

    @Test
    void employeeCannotEditOrVoid() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);
        String token = w.tokenOf(w.employee);

        send(token, "/api/attendance/assignments/" + a + "/admin-edit",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(235)).toString(), "reason", "x"))
                .andExpect(status().isForbidden());
        send(token, "/api/attendance/assignments/" + a + "/void", Map.of("reason", "x"))
                .andExpect(status().isForbidden());
        assertNull(recordRow(a));
    }

    @Test
    void managerOutsideBranchCannotEditOrVoid() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);
        String token = w.tokenOf(w.otherManager);

        send(token, "/api/attendance/assignments/" + a + "/admin-edit",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(235)).toString(), "reason", "x"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ được xử lý chấm công trong chi nhánh của mình."));
        send(token, "/api/attendance/assignments/" + a + "/void", Map.of("reason", "x"))
                .andExpect(status().isForbidden());
        assertNull(recordRow(a));
    }

    @Test
    void adminEditRecalculatesMinutesClosesOpenItemsAndNotifies() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);
        long recordId = record(a, -235, null, 0);
        long pendingEvent = event(a, "check_out", "pending_review", -55);
        long request = Db.insert(jdbc, "INSERT INTO attendance_adjustment_requests (attendance_id, requested_by, "
                + "requested_check_out, reason) VALUES (?, ?, ?, 'quên ra ca')", recordId, w.employeeUser,
                Timestamp.from(NOW.minus(Duration.ofMinutes(60))));
        String token = w.tokenOf(w.manager);
        String url = "/api/attendance/assignments/" + a + "/admin-edit";

        send(token, url, Map.of("checkOut", NOW.minus(Duration.ofMinutes(60)).toString(), "reason", " "))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value("Nhập lý do chỉnh công."));
        send(token, url, Map.of("reason", "không có giờ")).andExpect(status().isBadRequest());
        send(token, url, Map.of("checkOut", NOW.minus(Duration.ofMinutes(300)).toString(), "reason", "sai giờ"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Giờ ra phải từ giờ vào trở đi."));
        assertNull(recordRow(a).get("check_out_at"), "failed edit must roll back");

        // Only the check-out is supplied; the existing check-in (5 minutes after the start) is kept.
        send(token, url, Map.of("checkOut", NOW.minus(Duration.ofMinutes(60)).toString(), "reason", "quên ra ca"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sheet_status").value("SUCCESS"))
                .andExpect(jsonPath("$.worked_minutes").value(175))
                .andExpect(jsonPath("$.late_minutes").value(5));

        Map<String, Object> r = recordRow(a);
        assertEquals("adjusted", r.get("status"));
        assertEquals("COMPLETED", r.get("attendance_state"));
        assertEquals(w.managerUser, ((Number) r.get("approved_by")).longValue());
        assertEquals("rejected", jdbc.queryForObject("SELECT result FROM attendance_events WHERE id = ?",
                String.class, pendingEvent));
        assertEquals("Đã chỉnh công trực tiếp: quên ra ca", jdbc.queryForObject(
                "SELECT rejection_reason FROM attendance_events WHERE id = ?", String.class, pendingEvent));
        assertEquals("cancelled", jdbc.queryForObject(
                "SELECT status FROM attendance_adjustment_requests WHERE id = ?", String.class, request));
        assertEquals(1, notifications(w.employeeUser, "Giờ công đã được chỉnh"));
        assertEquals(1, audits("attendance.admin_edit", recordId));
    }

    @Test
    void adminEditCreatesMissingRecord() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);

        send(w.tokenOf(w.admin), "/api/attendance/assignments/" + a + "/admin-edit",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(240)).toString(),
                        "checkOut", NOW.minus(Duration.ofMinutes(60)).toString(), "reason", "quên chấm công"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sheet_status").value("SUCCESS"))
                .andExpect(jsonPath("$.worked_minutes").value(180))
                .andExpect(jsonPath("$.late_minutes").value(0));
        assertNotNull(recordRow(a));
    }

    @Test
    void voidBlocksEmployeeUntilReviewerRestoresByEditing() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);
        long recordId = record(a, -235, -60, 175);
        long inEvent = event(a, "check_in", "accepted", -235);
        long outEvent = event(a, "check_out", "accepted", -60);
        String employeeToken = w.tokenOf(w.employee);
        String reviewer = w.tokenOf(w.manager);
        String voidUrl = "/api/attendance/assignments/" + a + "/void";

        send(reviewer, voidUrl, Map.of("reason", "")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhập lý do hủy công."));
        send(reviewer, voidUrl, Map.of("reason", "chấm hộ"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sheet_status").value("VOIDED"))
                .andExpect(jsonPath("$.worked_minutes").value(0));

        Map<String, Object> r = recordRow(a);
        assertEquals("absent", r.get("status"));
        assertEquals("VOIDED", r.get("attendance_state"));
        assertNull(r.get("check_in_at"));
        assertNull(r.get("check_out_at"));
        for (long id : new long[] {inEvent, outEvent}) {
            assertEquals("rejected", jdbc.queryForObject("SELECT result FROM attendance_events WHERE id = ?",
                    String.class, id));
        }
        assertEquals(1, notifications(w.employeeUser, "Công bị hủy"));
        assertEquals(1, audits("attendance.void", recordId));
        assertEquals("VOIDED", statusOf(body(fetch(employeeToken, sheetUrl(null, DAY, DAY))), a));

        send(employeeToken, "/api/attendance/assignments/" + a + "/record",
                Map.of("type", "check_in", "evidence", evidence()))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value(VOIDED));
        send(employeeToken, "/api/attendance/assignments/" + a + "/submit",
                Map.of("type", "check_in", "evidence", evidence()))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value(VOIDED));
        send(employeeToken, "/api/attendance/assignments/" + a + "/adjustments",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(235)).toString(), "reason", "xin sửa"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value(VOIDED));

        // Editing the voided record restores it.
        send(reviewer, "/api/attendance/assignments/" + a + "/admin-edit",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(235)).toString(),
                        "checkOut", NOW.minus(Duration.ofMinutes(60)).toString(), "reason", "nhầm lẫn, khôi phục"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.sheet_status").value("SUCCESS"))
                .andExpect(jsonPath("$.worked_minutes").value(175));
        Map<String, Object> restored = recordRow(a);
        assertEquals("adjusted", restored.get("status"));
        assertEquals("COMPLETED", restored.get("attendance_state"));
    }

    @Test
    void lockedTimesheetCannotBeEditedOrVoided() throws Exception {
        World w = new World();
        long a = assign(w, w.employeeEmp, -240, -60);
        long recordId = record(a, -235, -60, 175);
        jdbc.update("UPDATE attendance_records SET locked_at = ? WHERE id = ?", Timestamp.from(NOW), recordId);
        String token = w.tokenOf(w.admin);

        send(token, "/api/attendance/assignments/" + a + "/admin-edit",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(230)).toString(), "reason", "x"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value(LOCKED));
        send(token, "/api/attendance/assignments/" + a + "/void", Map.of("reason", "x"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value(LOCKED));
        assertEquals("present", recordRow(a).get("status"));
    }

    @Test
    void reviewerCannotEditOwnTimesheet() throws Exception {
        World w = new World();
        long own = assign(w, w.adminEmp, -240, -60);
        String token = w.tokenOf(w.admin);

        send(token, "/api/attendance/assignments/" + own + "/admin-edit",
                Map.of("checkIn", NOW.minus(Duration.ofMinutes(235)).toString(), "reason", "tự sửa"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Không được tự sửa công của mình."));
        send(token, "/api/attendance/assignments/" + own + "/void", Map.of("reason", "tự hủy"))
                .andExpect(status().isForbidden());
        assertNull(recordRow(own));
    }
}
