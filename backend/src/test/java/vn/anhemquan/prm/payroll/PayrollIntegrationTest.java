package vn.anhemquan.prm.payroll;

import vn.anhemquan.prm.repository.Db;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Payroll, stars, closures and account linking against PostgreSQL. */
class PayrollIntegrationTest extends AbstractIntegrationTest {

    private static final String PASSWORD = "Passw0rd!x";

    private String sfx;
    private long branchId;
    private long adminUser;
    private String adminToken;
    private long empUser;
    private long empId;
    private String empToken;
    private long otherUser;
    private long otherEmpId;
    private String otherToken;
    private List<Long> deactivated;
    private int counter;

    @BeforeEach
    void setUp() throws Exception {
        sfx = UUID.randomUUID().toString().substring(0, 8);
        // Payroll approval compares against ALL active employees: park the rest of the shared DB.
        deactivated = jdbc.queryForList("SELECT id FROM employees WHERE status = 'active'", Long.class);
        jdbc.update("UPDATE employees SET status = 'inactive' WHERE status = 'active'");
        branchId = Db.insert(jdbc,"INSERT INTO branches (code, name) VALUES (?, 'B')", "B" + sfx);
        adminUser = createUser("adm" + sfx, PASSWORD, "admin", null);
        adminToken = login("adm" + sfx, PASSWORD);
        empUser = createUser("emp" + sfx, PASSWORD, "employee", "emp" + sfx + "@example.com");
        empId = employee(empUser, "E" + sfx, "Nhan Vien A");
        empToken = login("emp" + sfx, PASSWORD);
        otherUser = createUser("oth" + sfx, PASSWORD, "employee", null);
        otherEmpId = employee(otherUser, "O" + sfx, "Nhan Vien B");
        otherToken = login("oth" + sfx, PASSWORD);
    }

    @AfterEach
    void restore() {
        for (Long id : deactivated) {
            jdbc.update("UPDATE employees SET status = 'active' WHERE id = ?", id);
        }
        jdbc.update("UPDATE employees SET status = 'inactive' WHERE id IN (?, ?)", empId, otherEmpId);
    }

    private long employee(Long userId, String code, String name) {
        return Db.insert(jdbc,"INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                + "VALUES (?, ?, ?, ?, DATE '2020-01-01')", userId, code, name, branchId);
    }

    private long contract(long employeeId, long salary, int standardMinutes) {
        return Db.insert(jdbc,"INSERT INTO contracts (employee_id, contract_number, contract_type, start_date, "
                + "salary_basis, base_salary_vnd, standard_minutes_per_month, status) "
                + "VALUES (?, ?, 'indefinite', DATE '2020-01-01', 'monthly', ?, ?, 'active')", employeeId, "C" + sfx + employeeId, salary, standardMinutes);
    }

    /** Creates a shift on the given day (UTC 02:00 = 09:00 Vietnam) with the employee assigned; returns assignment id. */
    private long assignment(long employeeId, String day) {
        counter++;
        long shift = Db.insert(jdbc,"INSERT INTO shifts (branch_id, starts_at, ends_at, created_by) "
                + "VALUES (?, ?, ?, ?)",
                branchId, day + " 02:00:00", day + " 10:00:00", adminUser);
        return Db.insert(jdbc,"INSERT INTO shift_assignments (shift_id, employee_id, assigned_by) "
                + "VALUES (?, ?, ?)", shift, employeeId, adminUser);
    }

    private long record(long assignmentId, int worked, int overtime, int requested, String otStatus) {
        return Db.insert(jdbc,"INSERT INTO attendance_records (assignment_id, check_in_at, check_out_at, "
                + "worked_minutes, overtime_minutes, overtime_requested_minutes, overtime_status, status) "
                + "VALUES (?, '2030-01-10 02:00:00', '2030-01-10 10:00:00', ?, ?, ?, ?, "
                + "'present')", assignmentId, worked, overtime, requested, otStatus);
    }

    private ResultActions call(MockHttpServletRequestBuilder builder, String token, Object body) throws Exception {
        builder.header("Authorization", "Bearer " + token);
        if (body != null) {
            builder.contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body));
        }
        return mvc.perform(builder);
    }

    private long createPeriod() throws Exception {
        String body = call(post("/api/payroll/periods"), adminToken, Map.of("code", "P" + sfx,
                "startsOn", "2030-01-01", "endsOn", "2030-01-31", "overtimeMultiplier", 1.5))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return json.readTree(body).get("id").asLong();
    }

    /** Monthly 12,480,000 / 12,480 min = 1,000 VND per minute. */
    private void seedPay() {
        contract(empId, 12_480_000, 12_480);
        contract(otherEmpId, 6_240_000, 12_480);
        long a1 = assignment(empId, "2030-01-10");
        record(a1, 480, 60, 0, "NOT_REQUIRED");
        long a2 = assignment(empId, "2030-01-11");
        record(a2, 500, 0, 30, "PENDING");
    }

    @Test
    void calculatesRegularAndOvertimePayWithPendingOvertimeExcluded() throws Exception {
        seedPay();
        long period = createPeriod();

        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(2))
                .andExpect(jsonPath("$.message").value("Đã hoàn tất 6 bước và lưu 2 phiếu lương nháp."));

        // regular = (480-60) + (500-0-30) = 890 min; overtime = 60 min.
        Map<String, Object> pay = jdbc.queryForMap("SELECT * FROM payslips WHERE period_id = ? AND employee_id = ?",
                period, empId);
        assertEquals(890, ((Number) pay.get("regular_minutes")).intValue());
        assertEquals(60, ((Number) pay.get("overtime_minutes")).intValue());
        assertEquals(890_000L, ((Number) pay.get("base_pay_vnd")).longValue());
        assertEquals(90_000L, ((Number) pay.get("overtime_pay_vnd")).longValue());
        assertEquals("calculating", jdbc.queryForObject("SELECT status FROM payroll_periods WHERE id = ?",
                String.class, period));
        assertEquals(6, jdbc.queryForObject("SELECT COUNT(*) FROM payroll_calculation_steps WHERE period_id = ?",
                Integer.class, period));
        // Employee without attendance: 0 pay but a draft payslip exists.
        assertEquals(0L, ((Number) jdbc.queryForMap("SELECT base_pay_vnd FROM payslips WHERE period_id = ? "
                + "AND employee_id = ?", period, otherEmpId).get("base_pay_vnd")).longValue());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM audit_logs WHERE action = 'payroll.calculate' "
                + "AND entity_id = ?", Integer.class, period));
    }

    @Test
    void hourlyContractAndRoundingFollowFlutterRules() throws Exception {
        jdbc.update("INSERT INTO contracts (employee_id, contract_number, contract_type, start_date, salary_basis, "
                + "base_salary_vnd, hourly_rate_vnd, status) VALUES (?, ?, 'part_time', DATE '2020-01-01', 'hourly', "
                + "0, 35000, 'active')", empId, "H" + sfx);
        contract(otherEmpId, 1, 12_480);
        long a1 = assignment(empId, "2030-01-10");
        record(a1, 100, 10, 0, "NOT_REQUIRED");
        long period = createPeriod();

        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null).andExpect(status().isOk());

        // 35000/60 = 583.333.. per minute; regular 90 -> 52500; overtime 10*583.33*1.5 = 8750.
        Map<String, Object> pay = jdbc.queryForMap("SELECT * FROM payslips WHERE period_id = ? AND employee_id = ?",
                period, empId);
        assertEquals(52_500L, ((Number) pay.get("base_pay_vnd")).longValue());
        assertEquals(8_750L, ((Number) pay.get("overtime_pay_vnd")).longValue());
    }

    @Test
    void approvalRequiresFreshCalculationAndNotifiesEmployees() throws Exception {
        seedPay();
        long period = createPeriod();
        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null).andExpect(status().isOk());
        long payslip = jdbc.queryForObject("SELECT id FROM payslips WHERE period_id = ? AND employee_id = ?",
                Long.class, period, empId);

        // Adding an item invalidates the checks and steps: must recalculate before approving.
        call(post("/api/payroll/payslips/" + payslip + "/items"), adminToken,
                Map.of("code", "BONUS", "name", "Thưởng", "type", "bonus", "amount", 50_000))
                .andExpect(status().isCreated());
        call(post("/api/payroll/periods/" + period + "/approve"), adminToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Chưa hoàn thành đủ 6 bước."));

        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null).andExpect(status().isOk());
        call(get("/api/payroll/payslips/" + payslip), adminToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.net_pay_vnd").value(1_030_000))
                .andExpect(jsonPath("$.checks.length()").value(6))
                .andExpect(jsonPath("$.checks_current").value(true))
                .andExpect(jsonPath("$.items[0].code").value("BONUS"));

        // Changing attendance after the calculation makes the result stale.
        jdbc.update("UPDATE attendance_records SET worked_minutes = worked_minutes + 1 WHERE assignment_id IN "
                + "(SELECT id FROM shift_assignments WHERE employee_id = ?)", empId);
        call(post("/api/payroll/periods/" + period + "/approve"), adminToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(
                        "Dữ liệu công/hợp đồng/phiếu lương đã đổi. Cần tính lại toàn kỳ trước khi duyệt."));

        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null).andExpect(status().isOk());
        call(post("/api/payroll/periods/" + period + "/approve"), adminToken, null).andExpect(status().isOk());

        assertEquals("approved", jdbc.queryForObject("SELECT status FROM payroll_periods WHERE id = ?",
                String.class, period));
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM payslips WHERE period_id = ? AND status = 'approved'",
                Integer.class, period));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.title = 'Bảng lương đã được duyệt' "
                + "AND n.related_id = ?", Integer.class, empUser, period));
        // Closed periods and payslips are immutable.
        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Kỳ lương chưa có chính sách hoặc đã được chốt."));
        call(post("/api/payroll/payslips/" + payslip + "/items"), adminToken,
                Map.of("code", "X", "name", "X", "type", "bonus", "amount", 1))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Phiếu đã chốt không thể thay đổi."));
    }

    @Test
    void approvalFailsWhenActiveEmployeeListChanged() throws Exception {
        seedPay();
        long period = createPeriod();
        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null).andExpect(status().isOk());
        employee(null, "N" + sfx, "Moi");

        call(post("/api/payroll/periods/" + period + "/approve"), adminToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Danh sách nhân viên đã đổi. Cần tính lại toàn kỳ."));
        jdbc.update("UPDATE employees SET status = 'inactive' WHERE employee_code = ?", "N" + sfx);
    }

    @Test
    void missingContractAndNegativeNetAreRejected() throws Exception {
        contract(empId, 1_000_000, 12_480);
        long period = createPeriod();
        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhân viên Nhan Vien B chưa có hợp đồng bao phủ kỳ lương."));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM payslips WHERE period_id = ?", Integer.class,
                period), "failed calculation must roll back");

        contract(otherEmpId, 1_000_000, 12_480);
        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null).andExpect(status().isOk());
        long payslip = jdbc.queryForObject("SELECT id FROM payslips WHERE period_id = ? AND employee_id = ?",
                Long.class, period, empId);
        call(post("/api/payroll/payslips/" + payslip + "/items"), adminToken,
                Map.of("code", "TAX", "name", "Thuế", "type", "tax", "amount", 10))
                .andExpect(status().isCreated());
        call(post("/api/payroll/periods/" + period + "/calculate"), adminToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Thực lĩnh âm, cần kiểm tra khoản khấu trừ."));
    }

    @Test
    void employeesOnlyCalculateAndSeeTheirOwnPayslip() throws Exception {
        seedPay();
        long period = createPeriod();

        call(post("/api/payroll/periods/" + period + "/calculate"), empToken, Map.of("employeeId", otherEmpId))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ tính phiếu lương của chính mình."));
        call(post("/api/payroll/periods/" + period + "/calculate"), empToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(1))
                .andExpect(jsonPath("$.payslip_id").isNumber());
        // An employee run does not move the period into the calculating state.
        assertEquals("draft", jdbc.queryForObject("SELECT status FROM payroll_periods WHERE id = ?", String.class,
                period));

        long mine = jdbc.queryForObject("SELECT id FROM payslips WHERE period_id = ? AND employee_id = ?",
                Long.class, period, empId);
        call(get("/api/payroll/payslips/" + mine), empToken, null).andExpect(status().isOk());
        call(get("/api/payroll/payslips/" + mine), otherToken, null)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Không có quyền xem phiếu lương này."));
        call(get("/api/payroll/payslips"), empToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1));
        // Only payroll managers may create periods or contracts.
        call(post("/api/payroll/periods"), empToken, Map.of("code", "Z" + sfx, "startsOn", "2030-02-01",
                "endsOn", "2030-02-28", "overtimeMultiplier", 1.5)).andExpect(status().isForbidden());
    }

    @Test
    void periodAndContractValidation() throws Exception {
        call(post("/api/payroll/periods"), adminToken, Map.of("code", "Q" + sfx, "startsOn", "2030-02-10",
                "endsOn", "2030-02-01", "overtimeMultiplier", 1.5))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Kỳ lương hoặc hệ số tăng ca không hợp lệ."));
        call(post("/api/payroll/periods"), adminToken, Map.of("code", "Q" + sfx, "startsOn", "2030-02-01",
                "endsOn", "2030-02-28", "overtimeMultiplier", 0.5)).andExpect(status().isBadRequest());
        call(post("/api/payroll/contracts"), adminToken, Map.of("employeeId", empId, "contractNumber", "  ",
                "monthlySalary", 1, "standardMinutes", 1, "startsOn", "2030-01-01"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Thông tin hợp đồng không hợp lệ."));
        call(post("/api/payroll/contracts"), adminToken, Map.of("employeeId", empId, "contractNumber", "K" + sfx,
                "monthlySalary", 9_000_000, "standardMinutes", 12_480, "startsOn", "2030-01-01"))
                .andExpect(status().isCreated());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM contracts WHERE contract_number = ?",
                Integer.class, "K" + sfx));
    }

    @Test
    void starsAreReadOnlyAndEmployeesSeeOnlyTheirOwn() throws Exception {
        long managerUser = createUser("mgr" + sfx, PASSWORD, "manager", null);
        long managerEmp = employee(managerUser, "M" + sfx, "Quan Ly");
        // Awarding stars was removed from the API: existing events are only listed.
        jdbc.update("INSERT INTO star_events (employee_id, stars_delta, reason, awarded_by) VALUES (?, 3, 'Tot', ?)",
                empId, managerUser);
        String managerToken = login("mgr" + sfx, PASSWORD);

        call(post("/api/stars"), managerToken, Map.of("employeeId", empId, "delta", 1, "reason", "x"))
                .andExpect(status().is4xxClientError());
        call(get("/api/stars"), empToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].total_stars").value(3));
        jdbc.update("UPDATE employees SET status = 'inactive' WHERE id = ?", managerEmp);
    }

    @Test
    void closureFlowRequiresCheckoutAllowsResubmitAfterRejectionAndClosesShift() throws Exception {
        long manager = createUser("mgr" + sfx, PASSWORD, "manager", null);
        String managerToken = login("mgr" + sfx, PASSWORD);
        long assignment = assignment(empId, "2030-01-10");

        call(post("/api/closures"), empToken, Map.of("assignmentId", assignment, "note", "  ", "photoUrl", "u"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Cần ghi chú và ảnh chụp đóng ca."));
        call(post("/api/closures"), empToken, Map.of("assignmentId", assignment, "note", "Xong", "photoUrl", "a.jpg"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Cần điểm danh ra ca trước khi đóng ca."));
        call(post("/api/closures"), otherToken, Map.of("assignmentId", assignment, "note", "Xong", "photoUrl", "a.jpg"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Phân ca không thuộc bạn."));

        record(assignment, 480, 0, 0, "NOT_REQUIRED");
        String created = call(post("/api/closures"), empToken,
                Map.of("assignmentId", assignment, "note", "Xong", "photoUrl", "a.jpg"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        long closure = json.readTree(created).get("id").asLong();
        call(post("/api/closures"), empToken, Map.of("assignmentId", assignment, "note", "Xong", "photoUrl", "b.jpg"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.message").value("Đã gửi báo cáo đóng ca."));

        // The employee has no review permission; the submitter cannot review either.
        call(post("/api/closures/" + closure + "/review"), empToken, Map.of("approve", true))
                .andExpect(status().isForbidden());
        jdbc.update("UPDATE user_roles SET role_id = (SELECT id FROM roles WHERE code = 'manager') WHERE user_id = ?",
                empUser);
        call(post("/api/closures/" + closure + "/review"), empToken, Map.of("approve", true))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Không thể tự duyệt hoặc duyệt lại."));
        jdbc.update("UPDATE user_roles SET role_id = (SELECT id FROM roles WHERE code = 'employee') WHERE user_id = ?",
                empUser);

        call(post("/api/closures/" + closure + "/review"), managerToken, Map.of("approve", false))
                .andExpect(status().isOk());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.related_entity = 'shift_closures' "
                + "AND n.related_id = ?", Integer.class, empUser, closure));
        call(post("/api/closures/" + closure + "/review"), managerToken, Map.of("approve", false))
                .andExpect(status().isBadRequest());

        call(post("/api/closures"), empToken, Map.of("assignmentId", assignment, "note", "Bo sung", "photoUrl", "c.jpg"))
                .andExpect(status().isCreated());
        call(get("/api/closures"), empToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].status").value("submitted"))
                .andExpect(jsonPath("$[0].photos.length()").value(2));

        call(post("/api/closures/" + closure + "/review"), managerToken, Map.of("approve", true))
                .andExpect(status().isOk());
        assertEquals("completed", jdbc.queryForObject("SELECT status FROM shift_assignments WHERE id = ?",
                String.class, assignment));
        assertEquals("closed", jdbc.queryForObject("SELECT s.status FROM shifts s JOIN shift_assignments a "
                + "ON a.shift_id = s.id WHERE a.id = ?", String.class, assignment));
        assertTrue(manager > 0);
    }

    @Test
    void accountLinkingAndEmailRules() throws Exception {
        long orphanUser = createUser("orph" + sfx, PASSWORD, "employee", null);
        long unlinkedEmp = employee(null, "U" + sfx, "Chua lien ket");
        jdbc.update("UPDATE users SET google_subject = 'sub-" + sfx + "' WHERE id = ?", empUser);

        call(put("/api/accounts/users/" + empUser + "/email"), adminToken, Map.of("email", "not-an-email"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Email không hợp lệ."));
        call(put("/api/accounts/users/" + empUser + "/email"), empToken, Map.of("email", "a@b.vn"))
                .andExpect(status().isForbidden());
        call(put("/api/accounts/users/" + empUser + "/email"), adminToken, Map.of("email", " New." + sfx + "@Example.com "))
                .andExpect(status().isOk());
        Map<String, Object> user = jdbc.queryForMap("SELECT email, google_subject FROM users WHERE id = ?", empUser);
        assertEquals("new." + sfx + "@example.com", user.get("email"));
        assertEquals(null, user.get("google_subject"));

        call(get("/api/accounts/unlinked"), adminToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.username == 'orph" + sfx + "')]").isNotEmpty())
                .andExpect(jsonPath("$[?(@.username == 'emp" + sfx + "')]").isEmpty());
        call(put("/api/accounts/employees/" + empId + "/user"), adminToken, Map.of("userId", orphanUser))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Hồ sơ đã có tài khoản hoặc không tồn tại."));
        call(put("/api/accounts/employees/" + unlinkedEmp + "/user"), adminToken, Map.of("userId", 999_999_999L))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Tài khoản không hợp lệ."));
        call(put("/api/accounts/employees/" + unlinkedEmp + "/user"), adminToken, Map.of("userId", orphanUser))
                .andExpect(status().isOk());
        assertEquals(orphanUser, jdbc.queryForObject("SELECT user_id FROM employees WHERE id = ?", Long.class,
                unlinkedEmp));
        jdbc.update("UPDATE employees SET status = 'inactive' WHERE id = ?", unlinkedEmp);
    }
}
