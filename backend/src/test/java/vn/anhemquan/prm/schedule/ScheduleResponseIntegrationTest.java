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
import vn.anhemquan.prm.common.Db;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Employees accept / reject assigned shifts; managers read a per-employee shift table. */
class ScheduleResponseIntegrationTest extends AbstractIntegrationTest {

    static final String PW = "Passw0rd!";

    long branch;
    long otherBranch;
    long managerUser;
    String managerToken;
    String otherManagerToken;
    String adminToken;
    long emp1;
    long emp2;
    long user1;
    long user2;
    String token1;
    String token2;

    private long employee(String code, String name, long branchId, Long userId) {
        return Db.insert(jdbc,
                "INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                        + "VALUES (?, ?, ?, ?, CURRENT_DATE)", userId, code, name, branchId);
    }

    private long branch(String name) {
        return Db.insert(jdbc, "INSERT INTO branches (code, name) VALUES (?, ?)",
                "R" + UUID.randomUUID().toString().substring(0, 8), name);
    }

    @BeforeEach
    void setUp() throws Exception {
        String s = UUID.randomUUID().toString().substring(0, 8);
        branch = branch("CN " + s);
        otherBranch = branch("Khac " + s);
        managerUser = createUser("rm" + s, PW, "manager", null);
        employee("RM" + s, "Quan ly " + s, branch, managerUser);
        managerToken = login("rm" + s, PW);
        long otherManager = createUser("ro" + s, PW, "manager", null);
        employee("RO" + s, "Quan ly khac " + s, otherBranch, otherManager);
        otherManagerToken = login("ro" + s, PW);
        createUser("ra" + s, PW, "admin", null);
        adminToken = login("ra" + s, PW);
        user1 = createUser("r1" + s, PW, "employee", null);
        user2 = createUser("r2" + s, PW, "employee", null);
        emp1 = employee("R1" + s, "An " + s, branch, user1);
        emp2 = employee("R2" + s, "Binh " + s, branch, user2);
        token1 = login("r1" + s, PW);
        token2 = login("r2" + s, PW);
    }

    private ResultActions send(MockHttpServletRequestBuilder b, String token, Object body) throws Exception {
        b.header("Authorization", "Bearer " + token);
        if (body != null) {
            b.contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body));
        }
        return mvc.perform(b);
    }

    private long createShift(OffsetDateTime start, int staff) throws Exception {
        String res = send(post("/api/schedule/shifts"), managerToken, Map.of("branchId", branch,
                "start", start.toString(), "end", start.plusHours(4).toString(), "requiredStaff", staff))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return json.readTree(res).get("id").asLong();
    }

    private long assign(long shift, long employee) throws Exception {
        send(post("/api/schedule/shifts/" + shift + "/assignments"), managerToken, Map.of("employeeId", employee))
                .andExpect(status().isNoContent());
        return jdbc.queryForObject("SELECT id FROM shift_assignments WHERE shift_id = ? AND employee_id = ?",
                Long.class, shift, employee);
    }

    private ResultActions respond(long assignment, String token, boolean accept, String note) throws Exception {
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("accept", accept);
        body.put("note", note);
        return send(post("/api/schedule/assignments/" + assignment + "/respond"), token, body);
    }

    private int notificationsFor(long userId, String title) {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM notification_recipients r JOIN notifications n ON n.id = r.notification_id "
                        + "WHERE r.user_id = ? AND n.title = ?", Integer.class, userId, title);
    }

    private OffsetDateTime future(int days) {
        return OffsetDateTime.now(ZoneOffset.UTC).plusDays(days).withNano(0);
    }

    @Test
    void newAssignmentIsPendingAndEmployeeIsAskedToRespond() throws Exception {
        long shift = createShift(future(3), 1);
        long assignment = assign(shift, emp1);

        assertEquals("pending", jdbc.queryForObject(
                "SELECT response_status FROM shift_assignments WHERE id = ?", String.class, assignment));
        assertEquals(1, notificationsFor(user1, "Bạn có ca làm mới"));
        String body = jdbc.queryForObject("SELECT n.body FROM notifications n JOIN notification_recipients r "
                + "ON r.notification_id = n.id WHERE r.user_id = ? AND n.title = 'Bạn có ca làm mới'",
                String.class, user1);
        assertTrue(body.contains("Hãy chấp nhận hoặc từ chối."));
        send(get("/api/schedule/my-schedule"), token1, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].response_status").value("pending"));
    }

    @Test
    void employeeAcceptsAndManagerIsNotified() throws Exception {
        long shift = createShift(future(3), 1);
        long assignment = assign(shift, emp1);

        respond(assignment, token1, true, null).andExpect(status().isNoContent());

        assertEquals("accepted", jdbc.queryForObject(
                "SELECT response_status FROM shift_assignments WHERE id = ?", String.class, assignment));
        assertEquals("assigned", jdbc.queryForObject(
                "SELECT status FROM shift_assignments WHERE id = ?", String.class, assignment));
        assertEquals(1, notificationsFor(managerUser, "Nhân viên chấp nhận ca"));
        assertEquals(0, notificationsFor(user1, "Nhân viên chấp nhận ca"));
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM audit_logs WHERE action = 'shift.accept' AND entity_id = ?",
                Integer.class, assignment));
    }

    @Test
    void rejectNeedsReasonFreesSlotAndNotifiesManager() throws Exception {
        long shift = createShift(future(3), 1);
        long assignment = assign(shift, emp1);

        respond(assignment, token1, false, "  ").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhập lý do từ chối ca."));
        respond(assignment, token1, false, "Bận việc gia đình").andExpect(status().isNoContent());

        assertEquals("rejected", jdbc.queryForObject(
                "SELECT response_status FROM shift_assignments WHERE id = ?", String.class, assignment));
        assertEquals("cancelled", jdbc.queryForObject(
                "SELECT status FROM shift_assignments WHERE id = ?", String.class, assignment));
        assertEquals(1, notificationsFor(managerUser, "Nhân viên từ chối ca"));
        String body = jdbc.queryForObject("SELECT n.body FROM notifications n JOIN notification_recipients r "
                + "ON r.notification_id = n.id WHERE r.user_id = ? AND n.title = 'Nhân viên từ chối ca'",
                String.class, managerUser);
        assertTrue(body.contains("Bận việc gia đình"));
        // the single slot is free again, so another employee can take the shift
        assign(shift, emp2);
    }

    @Test
    void cannotRespondTwiceToOthersAssignmentsOrToStartedShifts() throws Exception {
        long shift = createShift(future(3), 2);
        long assignment = assign(shift, emp1);

        respond(assignment, token2, true, null).andExpect(status().isForbidden());
        respond(assignment, token1, true, null).andExpect(status().isNoContent());
        respond(assignment, token1, false, "Đổi ý").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Ca đã được phản hồi hoặc không còn hiệu lực."));

        long pastShift = createShift(OffsetDateTime.now(ZoneOffset.UTC).minusHours(1).withNano(0), 1);
        long pastAssignment = assign(pastShift, emp2);
        respond(pastAssignment, token2, true, null).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message")
                        .value("Không thể phản hồi ca đã bắt đầu hoặc đã có chấm công."));
    }

    @Test
    void reassigningARejectedShiftAsksAgain() throws Exception {
        long shift = createShift(future(3), 1);
        long assignment = assign(shift, emp1);
        respond(assignment, token1, false, "Bận").andExpect(status().isNoContent());

        assertEquals(assignment, assign(shift, emp1));
        assertEquals("pending", jdbc.queryForObject(
                "SELECT response_status FROM shift_assignments WHERE id = ?", String.class, assignment));
        respond(assignment, token1, true, null).andExpect(status().isNoContent());
    }

    @Test
    void shiftTableListsEverythingIncludingRejectedAndScopesByBranch() throws Exception {
        long accepted = createShift(future(2), 1);
        long pending = createShift(future(3), 1);
        long rejected = createShift(future(4), 1);
        long removed = createShift(future(5), 1);
        respondAfterAssign(accepted, true, null);
        assign(pending, emp1);
        respondAfterAssign(rejected, false, "Không rảnh");
        assign(removed, emp1);
        send(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                .delete("/api/schedule/shifts/" + removed + "/assignments/" + emp1), managerToken, null)
                .andExpect(status().isNoContent());

        String from = future(0).toLocalDate().toString();
        String to = future(10).toLocalDate().toString();
        String res = send(get("/api/schedule/employees/" + emp1 + "/shifts").param("from", from).param("to", to),
                managerToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.employee.id").value(emp1))
                .andExpect(jsonPath("$.summary.total").value(3))
                .andExpect(jsonPath("$.summary.accepted").value(1))
                .andExpect(jsonPath("$.summary.pending").value(1))
                .andExpect(jsonPath("$.summary.rejected").value(1))
                .andReturn().getResponse().getContentAsString();
        List<Long> shiftIds = new java.util.ArrayList<>();
        json.readTree(res).get("rows").forEach(r -> shiftIds.add(r.get("shift_id").asLong()));
        assertEquals(List.of(accepted, pending, rejected), shiftIds);
        assertFalse(shiftIds.contains(removed));
        assertTrue(json.readTree(res).get("rows").get(2).get("sheet_status").isNull());
        assertEquals("NOT_STARTED", json.readTree(res).get("rows").get(0).get("sheet_status").asText());

        send(get("/api/schedule/employees/" + emp1 + "/shifts"), otherManagerToken, null)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ được xử lý chấm công trong chi nhánh của mình."));
        send(get("/api/schedule/employees/" + emp1 + "/shifts").param("from", from).param("to", to),
                adminToken, null).andExpect(status().isOk());
        send(get("/api/schedule/employees/" + emp1 + "/shifts"), token1, null).andExpect(status().isForbidden());
        send(get("/api/schedule/employees/" + emp1 + "/shifts").param("from", "2026-01-01").param("to", "2026-12-31"),
                managerToken, null).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Khoảng ngày không hợp lệ."));
    }

    private void respondAfterAssign(long shift, boolean accept, String note) throws Exception {
        long assignment = assign(shift, emp1);
        respond(assignment, token1, accept, note).andExpect(status().isNoContent());
    }

    @Test
    void employeeListIsBranchScoped() throws Exception {
        String inBranch = send(get("/api/schedule/employees"), managerToken, null)
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        List<Long> ids = new java.util.ArrayList<>();
        json.readTree(inBranch).forEach(e -> ids.add(e.get("id").asLong()));
        assertTrue(ids.contains(emp1) && ids.contains(emp2));
        json.readTree(inBranch).forEach(e -> assertEquals(branch, e.get("branch_id").asLong()));

        String all = send(get("/api/schedule/employees"), adminToken, null)
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertTrue(json.readTree(all).size() >= json.readTree(inBranch).size());
        send(get("/api/schedule/employees"), token1, null).andExpect(status().isForbidden());
    }

    @Test
    void employeeApiExposesResponseStatus() throws Exception {
        long shift = createShift(future(1), 1);
        long assignment = assign(shift, emp1);
        respond(assignment, token1, true, null).andExpect(status().isNoContent());
        // The mobile endpoint uses Vietnam business days; query a wide window around the shift.
        send(get("/api/employees/me/shifts")
                .param("from", future(0).toLocalDate().toString())
                .param("to", future(7).toLocalDate().toString()), token1, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].responseStatus").value("accepted"));
    }
}
