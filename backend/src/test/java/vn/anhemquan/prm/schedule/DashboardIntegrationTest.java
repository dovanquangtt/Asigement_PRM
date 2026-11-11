package vn.anhemquan.prm.schedule;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import vn.anhemquan.prm.repository.Db;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** M12 dashboard statistics: numbers for one branch, scoping by role and range validation. */
class DashboardIntegrationTest extends AbstractIntegrationTest {

    static final String PW = "Passw0rd!";
    // A far-away month keeps the numbers independent from rows other tests leave behind.
    static final LocalDate DAY = LocalDate.of(2035, 3, 15);

    long branch;
    long emp1;
    long managerUser;
    String managerToken;
    String adminToken;
    String employeeToken;
    String otherManagerToken;

    private long employee(String code, String name, long branchId, Long userId) {
        return Db.insert(jdbc,
                "INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                        + "VALUES (?, ?, ?, ?, CURRENT_DATE)", userId, code, name, branchId);
    }

    private long branch(String name) {
        return Db.insert(jdbc, "INSERT INTO branches (code, name) VALUES (?, ?)",
                "D" + UUID.randomUUID().toString().substring(0, 8), name);
    }

    @BeforeEach
    void setUp() throws Exception {
        String s = UUID.randomUUID().toString().substring(0, 8);
        branch = branch("CN " + s);
        long otherBranch = branch("Khac " + s);
        managerUser = createUser("dm" + s, PW, "manager", null);
        employee("DM" + s, "Quan ly " + s, branch, managerUser);
        managerToken = login("dm" + s, PW);
        long other = createUser("do" + s, PW, "manager", null);
        employee("DO" + s, "Quan ly khac " + s, otherBranch, other);
        otherManagerToken = login("do" + s, PW);
        createUser("da" + s, PW, "admin", null);
        adminToken = login("da" + s, PW);
        long user1 = createUser("d1" + s, PW, "employee", null);
        emp1 = employee("D1" + s, "An " + s, branch, user1);
        employeeToken = login("d1" + s, PW);
    }

    private ResultActions send(String url, String token, String from, String to) throws Exception {
        MockHttpServletRequestBuilder b = get(url).header("Authorization", "Bearer " + token);
        if (from != null) {
            b.param("from", from).param("to", to);
        }
        return mvc.perform(b.accept(MediaType.APPLICATION_JSON));
    }

    private long shift(OffsetDateTime start, int staff) {
        return Db.insert(jdbc, "INSERT INTO shifts (branch_id, starts_at, ends_at, required_staff, status, created_by) "
                + "VALUES (?, ?, ?, ?, 'scheduled', ?)", branch, Timestamp.from(start.toInstant()),
                Timestamp.from(start.plusHours(8).toInstant()), staff, managerUser);
    }

    @Test
    void summaryCountsTheBranchesShiftsAttendanceHoursLeaveAndPayroll() throws Exception {
        OffsetDateTime noon = DAY.atTime(12, 0).atOffset(ZoneOffset.ofHours(7)).withOffsetSameInstant(ZoneOffset.UTC);
        long full = shift(noon, 2); // one person short
        shift(noon.plusDays(1), 1);
        long assignment = Db.insert(jdbc, "INSERT INTO shift_assignments (shift_id, employee_id, status, assigned_by) "
                + "VALUES (?, ?, 'assigned', ?)", full, emp1, managerUser);
        jdbc.update("INSERT INTO attendance_records (assignment_id, check_in_at, check_out_at, worked_minutes, "
                + "overtime_minutes, late_minutes, arrival_status, attendance_state, status) "
                + "VALUES (?, ?, ?, 450, 30, 5, 'LATE', 'COMPLETED', 'present')", assignment,
                Timestamp.from(noon.toInstant()), Timestamp.from(noon.plusHours(8).toInstant()));
        long type = Db.insert(jdbc, "INSERT INTO leave_types (code, name, is_paid) VALUES (?, ?, TRUE)",
                "DT" + UUID.randomUUID().toString().substring(0, 8), "Phep");
        jdbc.update("INSERT INTO leave_requests (employee_id, leave_type_id, starts_at, ends_at, requested_minutes, "
                + "reason, status) VALUES (?, ?, ?, ?, 480, 'x', 'pending')", emp1, type,
                Timestamp.from(noon.plusDays(3).toInstant()), Timestamp.from(noon.plusDays(3).plusHours(8).toInstant()));

        send("/api/dashboard/summary", managerToken, "2035-03-01", "2035-03-31")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.from").value("2035-03-01"))
                .andExpect(jsonPath("$.employees.active").value(2)) // the branch's manager and employee
                .andExpect(jsonPath("$.shifts.total").value(2))
                .andExpect(jsonPath("$.shifts.scheduled").value(2))
                .andExpect(jsonPath("$.shifts.assignments").value(1))
                .andExpect(jsonPath("$.shifts.understaffed").value(2))
                .andExpect(jsonPath("$.attendance.records").value(1))
                .andExpect(jsonPath("$.attendance.late").value(1))
                .andExpect(jsonPath("$.attendance.on_time").value(0))
                .andExpect(jsonPath("$.hours.worked_minutes").value(450))
                .andExpect(jsonPath("$.hours.overtime_minutes").value(30))
                .andExpect(jsonPath("$.hours.late_minutes").value(5))
                .andExpect(jsonPath("$.leave.pending").value(1))
                .andExpect(jsonPath("$.leave.approved").value(0))
                .andExpect(jsonPath("$.payroll.payslips").value(0));

        // The same month in another branch's view is empty; the range outside the month excludes everything.
        send("/api/dashboard/summary", otherManagerToken, "2035-03-01", "2035-03-31")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shifts.total").value(0))
                .andExpect(jsonPath("$.attendance.records").value(0))
                .andExpect(jsonPath("$.leave.pending").value(0));
        send("/api/dashboard/summary", managerToken, "2035-04-01", "2035-04-30")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shifts.total").value(0))
                .andExpect(jsonPath("$.hours.worked_minutes").value(0));
        // Admin sees every branch.
        // (rows of earlier runs stay in the shared test database, so only a lower bound is stable)
        send("/api/dashboard/summary", adminToken, "2035-03-01", "2035-03-31")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shifts.total").value(org.hamcrest.Matchers.greaterThanOrEqualTo(2)));
    }

    @Test
    void onlyReportViewersAndValidRangesAreAccepted() throws Exception {
        send("/api/dashboard/summary", employeeToken, "2035-03-01", "2035-03-31")
                .andExpect(status().isForbidden());
        send("/api/dashboard/summary", managerToken, "2035-03-31", "2035-03-01")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Khoảng ngày không hợp lệ."));
        send("/api/dashboard/summary", managerToken, "2033-01-01", "2035-12-31")
                .andExpect(status().isBadRequest());
        // Without a range the current month is used.
        String body = send("/api/dashboard/summary", managerToken, null, null)
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertTrue(json.readTree(body).get("from").asText().endsWith("-01"));
        mvc.perform(get("/api/dashboard/summary")).andExpect(status().isUnauthorized());
    }
}
