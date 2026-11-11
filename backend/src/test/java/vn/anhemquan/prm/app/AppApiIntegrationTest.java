package vn.anhemquan.prm.app;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
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
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import vn.anhemquan.prm.service.AttendanceClock;
import vn.anhemquan.prm.repository.Db;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

/**
 * Contract tests for backend/docs/api-app-contract.md. Every test builds its own branch and people (names carry a
 * per-run suffix, so repeated runs against the same database never collide).
 */
class AppApiIntegrationTest extends AbstractIntegrationTest {

    static final AtomicInteger SEQ = new AtomicInteger();
    static final String RUN = Long.toString(System.currentTimeMillis(), 36);
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

    record Person(String username, long user, long employee) {
    }

    class World {
        final int n = SEQ.incrementAndGet();
        final String tag = n + RUN;
        final long branch = insertBranch("APP" + tag);
        final long otherBranch = insertBranch("APPO" + tag);
        final Person admin = person("appadm" + tag, "admin", "AA" + tag, branch);
        final Person manager = person("appmgr" + tag, "manager", "AM" + tag, branch);
        final Person otherManager = person("appomg" + tag, "manager", "AO" + tag, otherBranch);
        final Person employee = person("appemp" + tag, "employee", "AE" + tag, branch);
        final Person colleague = person("appcol" + tag, "employee", "AC" + tag, branch);

        String token(Person p) {
            try {
                return login(p.username(), PASSWORD);
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }
    }

    long insertBranch(String code) {
        long id = Db.insert(jdbc, "INSERT INTO branches (code, name, latitude, longitude, geofence_radius_m) "
                + "VALUES (?, ?, ?, ?, 100)", code, "Chi nhánh " + code, LAT, LON);
        jdbc.update("INSERT INTO branch_wifi (branch_id, ssid, bssid) VALUES (?, 'AnhEm', ?)", id, BSSID);
        return id;
    }

    Person person(String username, String role, String code, long branch) {
        long user = createUser(username, PASSWORD, role, username + "@x.vn");
        long employee = Db.insert(jdbc, "INSERT INTO employees (user_id, employee_code, full_name, branch_id, "
                + "hire_date) VALUES (?, ?, ?, ?, DATE '2026-01-01')", user, code, "Name " + code, branch);
        return new Person(username, user, employee);
    }

    long assign(World w, Person p, int startOffsetMinutes, int endOffsetMinutes) {
        long shift = Db.insert(jdbc, "INSERT INTO shifts (branch_id, starts_at, ends_at, created_by) VALUES (?, ?, ?, ?)",
                w.branch, Timestamp.from(NOW.plus(Duration.ofMinutes(startOffsetMinutes))),
                Timestamp.from(NOW.plus(Duration.ofMinutes(endOffsetMinutes))), w.manager.user());
        return Db.insert(jdbc, "INSERT INTO shift_assignments (shift_id, employee_id, assigned_by) VALUES (?, ?, ?)",
                shift, p.employee(), w.manager.user());
    }

    String deviceOf(World w, Person p) {
        return "device-" + p.username();
    }

    void approvedDevice(World w, Person p) {
        jdbc.update("INSERT INTO employee_devices (employee_id, device_identifier, platform, approved_by) "
                + "VALUES (?, ?, 'android', ?)", p.employee(), deviceOf(w, p), w.manager.user());
    }

    void pendingDevice(World w, Person p) {
        jdbc.update("INSERT INTO employee_devices (employee_id, device_identifier, platform) VALUES (?, ?, 'android')",
                p.employee(), deviceOf(w, p));
    }

    Map<String, Object> punch(String device, double latitude) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("deviceIdentifier", device);
        body.put("devicePlatform", "android");
        body.put("deviceModel", "Pixel");
        body.put("latitude", latitude);
        body.put("longitude", LON);
        body.put("accuracyMeters", 10.0);
        body.put("locationCollectedAt", NOW.toString());
        body.put("mockLocation", false);
        body.put("wifiSsid", "AnhEm");
        body.put("wifiBssid", BSSID);
        return body;
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

    // ---- employee ------------------------------------------------------------------------------

    @Test
    void profileAndShiftsOfTheSignedInEmployee() throws Exception {
        World w = new World();
        long a = assign(w, w.employee, -10, 230);
        String token = w.token(w.employee);

        fetch(token, "/api/employees/me").andExpect(status().isOk())
                .andExpect(jsonPath("$.employeeCode").value("AE" + w.tag))
                .andExpect(jsonPath("$.branchName").value("Chi nhánh APP" + w.tag))
                .andExpect(jsonPath("$.avatarUrl").isEmpty());
        fetch(token, "/api/employees/me/shifts?from=2026-10-27&to=2026-10-27").andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].assignmentId").value(a))
                .andExpect(jsonPath("$[0].status").value("NOT_STARTED"));
    }

    @Test
    void todayStateFollowsTheAttendanceLifecycle() throws Exception {
        World w = new World();
        String token = w.token(w.employee);
        fetch(token, "/api/attendance/me/today").andExpect(status().isOk())
                .andExpect(jsonPath("$.state").value("NO_SHIFT")).andExpect(jsonPath("$.canCheckIn").value(false))
                .andExpect(jsonPath("$.shift").isEmpty()).andExpect(jsonPath("$.date").value("2026-10-27"));

        long a = assign(w, w.employee, -10, 230);
        approvedDevice(w, w.employee);
        fetch(token, "/api/attendance/me/today").andExpect(jsonPath("$.state").value("NOT_CHECKED_IN"))
                .andExpect(jsonPath("$.canCheckIn").value(true)).andExpect(jsonPath("$.canCheckOut").value(false))
                .andExpect(jsonPath("$.shift.assignmentId").value(a))
                .andExpect(jsonPath("$.verification.gps").value("UNKNOWN"))
                .andExpect(jsonPath("$.employee.fullName").value("Name AE" + w.tag));

        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT)).andExpect(status().isCreated());
        fetch(token, "/api/attendance/me/today").andExpect(jsonPath("$.state").value("WORKING"))
                .andExpect(jsonPath("$.canCheckIn").value(false)).andExpect(jsonPath("$.canCheckOut").value(true))
                .andExpect(jsonPath("$.attendance.checkInAt").value(NOW.toString()))
                .andExpect(jsonPath("$.attendance.arrivalStatus").value("LATE"));

        send(token, "/api/attendance/check-out", punch(deviceOf(w, w.employee), LAT)).andExpect(status().isCreated());
        fetch(token, "/api/attendance/me/today").andExpect(jsonPath("$.state").value("COMPLETED"))
                .andExpect(jsonPath("$.canCheckIn").value(false)).andExpect(jsonPath("$.canCheckOut").value(false))
                .andExpect(jsonPath("$.attendance.status").value("SUCCESS"));
    }

    @Test
    void checkInReturnsServerTimeBranchAndVerificationWithDistance() throws Exception {
        World w = new World();
        long a = assign(w, w.employee, -10, 230);
        approvedDevice(w, w.employee);
        String token = w.token(w.employee);

        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT)).andExpect(status().isCreated())
                .andExpect(jsonPath("$.type").value("CHECK_IN")).andExpect(jsonPath("$.result").value("ACCEPTED"))
                .andExpect(jsonPath("$.attendanceId").value(a)).andExpect(jsonPath("$.eventId").isNumber())
                .andExpect(jsonPath("$.serverTime").value(NOW.toString()))
                .andExpect(jsonPath("$.employee.fullName").value("Name AE" + w.tag))
                .andExpect(jsonPath("$.branch.id").value(w.branch))
                .andExpect(jsonPath("$.branch.name").value("Chi nhánh APP" + w.tag))
                .andExpect(jsonPath("$.shift.assignmentId").value(a))
                .andExpect(jsonPath("$.verification.gps").value("VERIFIED"))
                .andExpect(jsonPath("$.verification.device").value("VERIFIED"))
                .andExpect(jsonPath("$.verification.wifi").value("VERIFIED"))
                .andExpect(jsonPath("$.verification.distanceMeters").value(0.0))
                .andExpect(jsonPath("$.verification.radiusMeters").value(100))
                .andExpect(jsonPath("$.verification.warnings.length()").value(0))
                .andExpect(jsonPath("$.attendance.checkInAt").value(NOW.toString()))
                .andExpect(jsonPath("$.attendance.lateMinutes").value(10))
                .andExpect(jsonPath("$.status").value("WORKING"))
                .andExpect(jsonPath("$.message").value("Chấm công vào thành công"));
    }

    @Test
    void duplicateCheckInIsAConflictWithItsOwnCode() throws Exception {
        World w = new World();
        assign(w, w.employee, -10, 230);
        approvedDevice(w, w.employee);
        String token = w.token(w.employee);
        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT)).andExpect(status().isCreated());

        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("DUPLICATE_ATTENDANCE"))
                .andExpect(jsonPath("$.message").isNotEmpty());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM attendance_events WHERE assignment_id IN "
                + "(SELECT a.id FROM shift_assignments a WHERE a.employee_id = ?)", Integer.class,
                w.employee.employee()));
    }

    @Test
    void unregisteredAndRevokedDevicesAreRejected() throws Exception {
        World w = new World();
        assign(w, w.employee, -10, 230);
        String token = w.token(w.employee);

        send(token, "/api/attendance/check-in", punch("never-registered-" + w.tag, LAT))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("DEVICE_NOT_REGISTERED"));

        approvedDevice(w, w.employee);
        jdbc.update("UPDATE employee_devices SET revoked_at = ? WHERE device_identifier = ?", Timestamp.from(NOW),
                deviceOf(w, w.employee));
        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("DEVICE_REVOKED"));

        // A device that belongs to a colleague is "not registered" for this employee.
        approvedDevice(w, w.colleague);
        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.colleague), LAT))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("DEVICE_NOT_REGISTERED"));
    }

    @Test
    void noShiftAndInvalidCoordinatesHaveSpecificCodes() throws Exception {
        World w = new World();
        approvedDevice(w, w.employee);
        String token = w.token(w.employee);
        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("NO_SHIFT"));

        assign(w, w.employee, -10, 230);
        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), 123.0))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
        send(token, "/api/attendance/check-in", Map.of("deviceIdentifier", "x"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void outsideRadiusIsSavedAsAnExceptionWithWarningsAndDistance() throws Exception {
        World w = new World();
        long a = assign(w, w.employee, -10, 230);
        approvedDevice(w, w.employee);
        String token = w.token(w.employee);

        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT + 0.01))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.result").value("PENDING_REVIEW"))
                .andExpect(jsonPath("$.verification.gps").value("FAILED"))
                .andExpect(jsonPath("$.verification.warnings.length()").value(1))
                .andExpect(jsonPath("$.status").value("ATTENDANCE_EXCEPTION"))
                .andExpect(jsonPath("$.attendance.checkInAt").isEmpty());
        double distance = body(fetch(token, "/api/attendance/me/" + a)).get("events").get(0).get("distanceMeters")
                .asDouble();
        assertTrue(distance > 1000 && distance < 1200, "distance was " + distance);

        fetch(token, "/api/attendance/me/today").andExpect(jsonPath("$.state").value("ATTENDANCE_EXCEPTION"))
                .andExpect(jsonPath("$.canCheckIn").value(false))
                .andExpect(jsonPath("$.pendingExceptions.length()").value(1))
                .andExpect(jsonPath("$.pendingExceptions[0].eventType").value("CHECK_IN"));
    }

    @Test
    void checkOutCompletesTheSameAttendanceRecord() throws Exception {
        World w = new World();
        long a = assign(w, w.employee, -10, 230);
        approvedDevice(w, w.employee);
        String token = w.token(w.employee);
        send(token, "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT)).andExpect(status().isCreated());

        send(token, "/api/attendance/check-out", punch(deviceOf(w, w.employee), LAT)).andExpect(status().isCreated())
                .andExpect(jsonPath("$.type").value("CHECK_OUT")).andExpect(jsonPath("$.attendanceId").value(a))
                .andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.attendance.checkOutAt").value(NOW.toString()))
                .andExpect(jsonPath("$.message").value("Chấm công ra thành công"));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM attendance_records WHERE assignment_id = ?",
                Integer.class, a));
        assertNotNull(jdbc.queryForObject("SELECT check_out_at FROM attendance_records WHERE assignment_id = ?",
                Timestamp.class, a));
        send(token, "/api/attendance/check-out", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("DUPLICATE_ATTENDANCE"));
    }

    @Test
    void historyIsPaginatedAndDetailIsOwnOnly() throws Exception {
        World w = new World();
        long a1 = assign(w, w.employee, -1440 - 10, -1440 + 230);
        long a2 = assign(w, w.employee, -2880 - 10, -2880 + 230);
        long a3 = assign(w, w.employee, -4320 - 10, -4320 + 230);
        long other = assign(w, w.colleague, -10, 230);
        String token = w.token(w.employee);

        fetch(token, "/api/attendance/me/history?page=0&size=2").andExpect(status().isOk())
                .andExpect(jsonPath("$.items.length()").value(2)).andExpect(jsonPath("$.totalItems").value(3))
                .andExpect(jsonPath("$.totalPages").value(2)).andExpect(jsonPath("$.size").value(2))
                .andExpect(jsonPath("$.items[0].attendanceId").value(a1))
                .andExpect(jsonPath("$.items[1].attendanceId").value(a2))
                .andExpect(jsonPath("$.items[0].status").value("MISSING_CHECK_IN"))
                .andExpect(jsonPath("$.items[0].date").value("2026-10-26"));
        fetch(token, "/api/attendance/me/history?page=1&size=2").andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].attendanceId").value(a3));
        fetch(token, "/api/attendance/me/history?from=2026-10-26&to=2026-10-26")
                .andExpect(jsonPath("$.totalItems").value(1));

        fetch(token, "/api/attendance/me/" + a1).andExpect(status().isOk())
                .andExpect(jsonPath("$.item.attendanceId").value(a1))
                .andExpect(jsonPath("$.events.length()").value(0));
        fetch(token, "/api/attendance/me/" + other).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));
    }

    // ---- manager -------------------------------------------------------------------------------

    @Test
    void managerSummaryCountsNoShowsOnlyAfterTheShiftStarted() throws Exception {
        World w = new World();
        Person third = person("appthird" + w.tag, "employee", "AT" + w.tag, w.branch);
        assign(w, w.employee, -10, 230); // started, checks in
        assign(w, w.colleague, -30, 200); // started, never checks in
        assign(w, third, 60, 300); // starts in an hour: must not count as absent
        approvedDevice(w, w.employee);
        send(w.token(w.employee), "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isCreated());
        long employees = jdbc.queryForObject("SELECT COUNT(*) FROM employees WHERE branch_id = ? AND status = 'active'",
                Long.class, w.branch);

        fetch(w.token(w.manager), "/api/manager/attendance/summary?date=2026-10-27").andExpect(status().isOk())
                .andExpect(jsonPath("$.date").value("2026-10-27")).andExpect(jsonPath("$.branchId").value(w.branch))
                .andExpect(jsonPath("$.totalEmployees").value(employees)).andExpect(jsonPath("$.checkedIn").value(1))
                .andExpect(jsonPath("$.working").value(1)).andExpect(jsonPath("$.completed").value(0))
                .andExpect(jsonPath("$.late").value(1)).andExpect(jsonPath("$.notCheckedIn").value(1))
                .andExpect(jsonPath("$.exceptions").value(0));
    }

    @Test
    void managerListSupportsFiltersAndPaging() throws Exception {
        World w = new World();
        assign(w, w.employee, -10, 230);
        assign(w, w.colleague, -30, 200);
        approvedDevice(w, w.employee);
        send(w.token(w.employee), "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isCreated());
        String manager = w.token(w.manager);

        fetch(manager, "/api/manager/attendance?date=2026-10-27").andExpect(status().isOk())
                .andExpect(jsonPath("$.totalItems").value(2)).andExpect(jsonPath("$.items.length()").value(2))
                .andExpect(jsonPath("$.items[0].employee.fullName").value("Name AC" + w.tag))
                .andExpect(jsonPath("$.items[1].verification.gps").value("VERIFIED"))
                .andExpect(jsonPath("$.items[0].verification.gps").value("UNKNOWN"));
        fetch(manager, "/api/manager/attendance?date=2026-10-27&status=IN_PROGRESS")
                .andExpect(jsonPath("$.totalItems").value(1))
                .andExpect(jsonPath("$.items[0].employee.employeeCode").value("AE" + w.tag));
        fetch(manager, "/api/manager/attendance?date=2026-10-27&q=AC" + w.tag)
                .andExpect(jsonPath("$.totalItems").value(1));
        fetch(manager, "/api/manager/attendance?date=2026-10-27&size=1&page=1")
                .andExpect(jsonPath("$.items.length()").value(1)).andExpect(jsonPath("$.totalPages").value(2));
        fetch(manager, "/api/manager/attendance?date=2026-10-27&status=NOPE").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void managerIsLimitedToTheirBranchAndRoles() throws Exception {
        World w = new World();
        long a = assign(w, w.employee, -10, 230);
        String other = w.token(w.otherManager);

        fetch(other, "/api/manager/attendance/" + a).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));
        fetch(w.token(w.manager), "/api/manager/attendance/summary?branchId=" + w.otherBranch)
                .andExpect(status().isForbidden());
        fetch(w.token(w.manager), "/api/manager/attendance/" + a).andExpect(status().isOk())
                .andExpect(jsonPath("$.shift.assignmentId").value(a))
                .andExpect(jsonPath("$.employee.employeeCode").value("AE" + w.tag));
        // Employees cannot use manager endpoints, managers cannot use admin endpoints.
        fetch(w.token(w.employee), "/api/manager/attendance/summary").andExpect(status().isForbidden());
        fetch(w.token(w.manager), "/api/admin/attendance/summary").andExpect(status().isForbidden());
        fetch(w.token(w.manager), "/api/admin/devices").andExpect(status().isForbidden());
    }

    @Test
    void exceptionsListShowsPendingSubmissionsWithAReasonAndAuditLogInDetail() throws Exception {
        World w = new World();
        long a = assign(w, w.employee, -10, 230);
        pendingDevice(w, w.employee);
        send(w.token(w.employee), "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.result").value("PENDING_REVIEW"))
                .andExpect(jsonPath("$.verification.device").value("FAILED"));
        String manager = w.token(w.manager);

        fetch(manager, "/api/manager/attendance/exceptions?date=2026-10-27").andExpect(status().isOk())
                .andExpect(jsonPath("$.totalItems").value(1))
                .andExpect(jsonPath("$.items[0].attendanceId").value(a))
                .andExpect(jsonPath("$.items[0].reason").isNotEmpty())
                .andExpect(jsonPath("$.items[0].status").value("PENDING_REVIEW"));
        fetch(manager, "/api/manager/attendance/summary?date=2026-10-27").andExpect(jsonPath("$.exceptions").value(1))
                .andExpect(jsonPath("$.notCheckedIn").value(0)); // a pending check-in is not a no-show
        JsonNode detail = body(fetch(manager, "/api/manager/attendance/" + a));
        assertEquals(1, detail.get("events").size());
        assertEquals("PENDING_REVIEW", detail.get("events").get(0).get("result").asText());
        assertTrue(detail.get("auditLog").size() >= 1);
        assertEquals("attendance.submit", detail.get("auditLog").get(0).get("action").asText());
    }

    // ---- admin ---------------------------------------------------------------------------------

    @Test
    void adminSummaryListAndReportsCoverTheWholeSystem() throws Exception {
        World w = new World();
        assign(w, w.employee, -10, 230);
        assign(w, w.colleague, -300, -60); // ended, never checked in
        approvedDevice(w, w.employee);
        send(w.token(w.employee), "/api/attendance/check-in", punch(deviceOf(w, w.employee), LAT))
                .andExpect(status().isCreated());
        String admin = w.token(w.admin);

        fetch(admin, "/api/admin/attendance/summary?date=2026-10-27&branchId=" + w.branch).andExpect(status().isOk())
                .andExpect(jsonPath("$.totalBranches").isNumber()).andExpect(jsonPath("$.totalShifts").value(2))
                .andExpect(jsonPath("$.checkedIn").value(1)).andExpect(jsonPath("$.notCheckedIn").value(1));
        JsonNode all = body(fetch(admin, "/api/admin/attendance/summary?date=2026-10-27"));
        assertTrue(all.get("totalBranches").asLong() >= 2);
        assertTrue(all.get("totalShifts").asLong() >= 2);
        fetch(admin, "/api/admin/attendance?date=2026-10-27&branchId=" + w.branch + "&status=MISSING_CHECK_IN")
                .andExpect(jsonPath("$.totalItems").value(1))
                .andExpect(jsonPath("$.items[0].employee.employeeCode").value("AC" + w.tag));

        fetch(admin, "/api/admin/reports/attendance?from=2026-10-27&to=2026-10-27&groupBy=employee&branchId=" + w.branch)
                .andExpect(status().isOk()).andExpect(jsonPath("$.groupBy").value("employee"))
                .andExpect(jsonPath("$.rows.length()").value(2))
                .andExpect(jsonPath("$.rows[?(@.label == 'Name AE" + w.tag + "')].late").value(1))
                .andExpect(jsonPath("$.rows[?(@.label == 'Name AC" + w.tag + "')].missing").value(1));
        fetch(admin, "/api/admin/reports/attendance?from=2026-10-27&to=2026-10-27&groupBy=branch&branchId=" + w.branch)
                .andExpect(jsonPath("$.rows.length()").value(1)).andExpect(jsonPath("$.rows[0].key")
                        .value(String.valueOf(w.branch))).andExpect(jsonPath("$.rows[0].totalShifts").value(2));
        fetch(admin, "/api/admin/reports/attendance?from=2026-10-27&to=2026-10-27&groupBy=date&branchId=" + w.branch)
                .andExpect(jsonPath("$.rows[0].key").value("2026-10-27"));
        fetch(admin, "/api/admin/reports/attendance?groupBy=nonsense").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void adminDevicesListMaskIdentifiersAndCanBeRevokedAndApproved() throws Exception {
        World w = new World();
        pendingDevice(w, w.employee);
        String identifier = deviceOf(w, w.employee);
        String masked = identifier.substring(0, 4) + "…" + identifier.substring(identifier.length() - 4);
        String admin = w.token(w.admin);

        JsonNode pending = body(fetch(admin, "/api/admin/devices?status=PENDING&q=AE" + w.tag));
        assertEquals(1, pending.get("totalItems").asInt());
        JsonNode device = pending.get("items").get(0);
        assertEquals(masked, device.get("deviceIdentifierMasked").asText());
        assertEquals("PENDING", device.get("status").asText());
        assertEquals("AE" + w.tag, device.get("employeeCode").asText());
        long id = device.get("id").asLong();

        send(admin, "/api/admin/devices/" + id + "/approve", Map.of()).andExpect(status().isNoContent());
        fetch(admin, "/api/admin/devices?status=APPROVED&q=AE" + w.tag).andExpect(jsonPath("$.totalItems").value(1))
                .andExpect(jsonPath("$.items[0].approvedByName").value(w.admin.username()));

        send(admin, "/api/admin/devices/" + id + "/revoke", Map.of("reason", "Mất máy")).andExpect(status().isNoContent());
        fetch(admin, "/api/admin/devices?status=REVOKED&q=AE" + w.tag).andExpect(jsonPath("$.totalItems").value(1))
                .andExpect(jsonPath("$.items[0].revokedAt").isNotEmpty());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM audit_logs WHERE action = 'device.revoke' "
                + "AND entity_id = ?", Integer.class, id));
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.title = 'Thiết bị điểm danh'",
                Integer.class, w.employee.user()));
        // A revoked device can no longer punch.
        assign(w, w.employee, -10, 230);
        send(w.token(w.employee), "/api/attendance/check-in", punch(identifier, LAT))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.code").value("DEVICE_REVOKED"));
    }
}
