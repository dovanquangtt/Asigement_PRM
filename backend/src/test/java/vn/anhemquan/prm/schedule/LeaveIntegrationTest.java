package vn.anhemquan.prm.schedule;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import vn.anhemquan.prm.repository.Db;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** M06 leave: balances, requests, manager decisions, notifications and the rules around them. */
class LeaveIntegrationTest extends AbstractIntegrationTest {

    static final String PW = "Passw0rd!";

    long branch;
    long managerUser;
    long managerEmp;
    long emp1;
    long user1;
    long leaveType;
    String managerToken;
    String otherManagerToken;
    String adminToken;
    String token1;
    long otherManagerUser;

    private long employee(String code, String name, long branchId, Long userId) {
        return Db.insert(jdbc,
                "INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                        + "VALUES (?, ?, ?, ?, CURRENT_DATE)", userId, code, name, branchId);
    }

    private long branch(String name) {
        return Db.insert(jdbc, "INSERT INTO branches (code, name) VALUES (?, ?)",
                "L" + UUID.randomUUID().toString().substring(0, 8), name);
    }

    @BeforeEach
    void setUp() throws Exception {
        String s = UUID.randomUUID().toString().substring(0, 8);
        branch = branch("CN " + s);
        long otherBranch = branch("Khac " + s);
        managerUser = createUser("lm" + s, PW, "manager", null);
        managerEmp = employee("LM" + s, "Quan ly " + s, branch, managerUser);
        managerToken = login("lm" + s, PW);
        otherManagerUser = createUser("lo" + s, PW, "manager", null);
        employee("LO" + s, "Quan ly khac " + s, otherBranch, otherManagerUser);
        otherManagerToken = login("lo" + s, PW);
        createUser("la" + s, PW, "admin", null);
        adminToken = login("la" + s, PW);
        user1 = createUser("l1" + s, PW, "employee", null);
        emp1 = employee("L1" + s, "An " + s, branch, user1);
        token1 = login("l1" + s, PW);
        leaveType = Db.insert(jdbc, "INSERT INTO leave_types (code, name, is_paid) VALUES (?, ?, TRUE)",
                "T" + s, "Phep nam " + s);
    }

    private ResultActions send(MockHttpServletRequestBuilder b, String token, Object body) throws Exception {
        b.header("Authorization", "Bearer " + token);
        if (body != null) {
            b.contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body));
        }
        return mvc.perform(b);
    }

    private OffsetDateTime future(int days) {
        return OffsetDateTime.now(ZoneOffset.UTC).plusDays(days).withNano(0);
    }

    private void grant(long employee, int minutes) {
        jdbc.update("INSERT INTO leave_balances (employee_id, leave_type_id, year, granted_minutes, used_minutes) "
                + "VALUES (?, ?, ?, ?, 0)", employee, leaveType, OffsetDateTime.now(ZoneOffset.UTC).getYear(),
                minutes);
    }

    private long request(String token, OffsetDateTime start, OffsetDateTime end) throws Exception {
        send(post("/api/schedule/leave-requests"), token, Map.of("leaveTypeId", leaveType,
                "start", start.toString(), "end", end.toString(), "reason", "Việc gia đình"))
                .andExpect(status().isCreated());
        return jdbc.queryForObject("SELECT MAX(id) FROM leave_requests", Long.class);
    }

    private ResultActions review(long id, String token, boolean approve, String note) throws Exception {
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("approve", approve);
        body.put("note", note);
        return send(post("/api/schedule/leave-requests/" + id + "/review"), token, body);
    }

    private int notificationsFor(long userId, String title) {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM notification_recipients r JOIN notifications n ON n.id = r.notification_id "
                        + "WHERE r.user_id = ? AND n.title = ?", Integer.class, userId, title);
    }

    private long balanceRemaining(String token) throws Exception {
        String res = send(get("/api/schedule/leave-balances"), token, null).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        for (var row : json.readTree(res)) {
            if (row.get("leave_type_id").asLong() == leaveType) {
                return row.get("remaining_minutes").asLong();
            }
        }
        throw new AssertionError("leave type missing from balances");
    }

    @Test
    void employeeSeesBalanceAndRequestNotifiesOnlyTheOwnBranchManagersAndAdmin() throws Exception {
        assertEquals(0, balanceRemaining(token1));
        grant(emp1, 960);
        assertEquals(960, balanceRemaining(token1));

        request(token1, future(10), future(10).plusHours(8));

        assertEquals(480, balanceRemaining(token1)); // the pending request is already deducted
        assertEquals(1, notificationsFor(managerUser, "Yêu cầu nghỉ phép mới"));
        assertEquals(0, notificationsFor(otherManagerUser, "Yêu cầu nghỉ phép mới"));
    }

    @Test
    void managerApprovesDeductsBalanceAndNotifiesEmployee() throws Exception {
        grant(emp1, 960);
        long id = request(token1, future(10), future(10).plusHours(8));

        String list = send(get("/api/schedule/leave-requests/review"), managerToken, null)
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertEquals(id, json.readTree(list).get(0).get("id").asLong());
        assertEquals("pending", json.readTree(list).get(0).get("status").asText());
        // Another branch's manager does not see it; Admin does.
        assertTrue(json.readTree(send(get("/api/schedule/leave-requests/review"), otherManagerToken, null)
                .andReturn().getResponse().getContentAsString()).findValues("id").stream()
                .noneMatch(n -> n.asLong() == id));
        assertTrue(json.readTree(send(get("/api/schedule/leave-requests/review"), adminToken, null)
                .andReturn().getResponse().getContentAsString()).findValues("id").stream()
                .anyMatch(n -> n.asLong() == id));

        review(id, managerToken, true, "OK").andExpect(status().isNoContent());

        assertEquals("approved", jdbc.queryForObject("SELECT status FROM leave_requests WHERE id = ?",
                String.class, id));
        assertEquals(480, jdbc.queryForObject("SELECT used_minutes FROM leave_balances WHERE employee_id = ?",
                Integer.class, emp1));
        assertEquals(1, notificationsFor(user1, "Kết quả duyệt nghỉ phép"));
        review(id, managerToken, true, null).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Yêu cầu đã được xử lý."));
    }

    @Test
    void rejectionNeedsAReasonAndKeepsTheBalance() throws Exception {
        grant(emp1, 960);
        long id = request(token1, future(10), future(10).plusHours(8));

        review(id, managerToken, false, "  ").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhập lý do từ chối nghỉ phép."));
        review(id, managerToken, false, "Thiếu người").andExpect(status().isNoContent());

        assertEquals("rejected", jdbc.queryForObject("SELECT status FROM leave_requests WHERE id = ?",
                String.class, id));
        assertEquals(0, jdbc.queryForObject("SELECT used_minutes FROM leave_balances WHERE employee_id = ?",
                Integer.class, emp1));
        assertEquals(960, balanceRemaining(token1));
    }

    @Test
    void approvalNeedsEnoughDaysAndNoShiftInsideTheLeave() throws Exception {
        grant(emp1, 960);
        long tooLong = request(token1, future(10), future(10).plusDays(2).plusHours(8)); // 3 days > 2 granted
        review(tooLong, managerToken, true, null).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Không đủ số ngày phép còn lại."));

        OffsetDateTime start = future(20);
        String created = send(post("/api/schedule/shifts"), managerToken, Map.of("branchId", branch,
                "start", start.toString(), "end", start.plusHours(4).toString(), "requiredStaff", 1))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        long shift = json.readTree(created).get("id").asLong();
        send(post("/api/schedule/shifts/" + shift + "/assignments"), managerToken, Map.of("employeeId", emp1))
                .andExpect(status().isNoContent());
        long clash = request(token1, start, start.plusHours(8));
        review(clash, managerToken, true, null).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(
                        "Nhân viên đang có ca trong thời gian nghỉ. Hãy gỡ hoặc đổi ca trước khi duyệt."));
        assertEquals(0, jdbc.queryForObject("SELECT used_minutes FROM leave_balances WHERE employee_id = ?",
                Integer.class, emp1));
    }

    @Test
    void onlyAuthorisedReviewersAndNeverTheRequesterThemselves() throws Exception {
        grant(emp1, 960);
        long id = request(token1, future(10), future(10).plusHours(8));

        send(get("/api/schedule/leave-requests/review"), token1, null).andExpect(status().isForbidden());
        review(id, token1, true, null).andExpect(status().isForbidden());
        review(id, otherManagerToken, true, null).andExpect(status().isForbidden());

        // A manager's own request cannot be approved by that manager, but Admin can.
        grant(managerEmp, 960);
        long own = request(managerToken, future(12), future(12).plusHours(8));
        review(own, managerToken, true, null).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Không thể tự duyệt nghỉ phép của mình."));
        review(own, adminToken, true, null).andExpect(status().isNoContent());
        assertEquals("pending", jdbc.queryForObject("SELECT status FROM leave_requests WHERE id = ?",
                String.class, id));
        review(999_999_999L, adminToken, true, null).andExpect(status().isNotFound());
    }
}
