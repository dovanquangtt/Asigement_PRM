package vn.anhemquan.prm.schedule;

import vn.anhemquan.prm.repository.Db;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class ScheduleIntegrationTest extends AbstractIntegrationTest {

    static final String PW = "Passw0rd!";

    long branch;
    long otherBranch;
    String managerToken;
    String reviewerToken;
    long reviewerUser;
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
        return Db.insert(jdbc,"INSERT INTO branches (code, name) VALUES (?, ?)",
                "B" + UUID.randomUUID().toString().substring(0, 8), name);
    }

    @BeforeEach
    void setUp() throws Exception {
        String s = UUID.randomUUID().toString().substring(0, 8);
        branch = branch("Chi nhánh " + s);
        otherBranch = branch("Khác " + s);
        long managerUser = createUser("mgr" + s, PW, "manager", null);
        employee("M" + s, "Quản lý " + s, branch, managerUser);
        managerToken = login("mgr" + s, PW);
        reviewerUser = createUser("rev" + s, PW, "manager", null);
        reviewerToken = login("rev" + s, PW);
        user1 = createUser("e1" + s, PW, "employee", null);
        user2 = createUser("e2" + s, PW, "employee", null);
        emp1 = employee("E1" + s, "An " + s, branch, user1);
        emp2 = employee("E2" + s, "Bình " + s, branch, user2);
        token1 = login("e1" + s, PW);
        token2 = login("e2" + s, PW);
    }

    private ResultActions send(MockHttpServletRequestBuilder b, String token, Object body) throws Exception {
        b.header("Authorization", "Bearer " + token);
        if (body != null) {
            b.contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body));
        }
        return mvc.perform(b);
    }

    private long createShift(long branchId, OffsetDateTime start, int hours, int staff) throws Exception {
        String res = send(post("/api/schedule/shifts"), managerToken, Map.of("branchId", branchId,
                "start", start.toString(), "end", start.plusHours(hours).toString(), "requiredStaff", staff))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        return json.readTree(res).get("id").asLong();
    }

    private void assign(long shift, long employee) throws Exception {
        send(post("/api/schedule/shifts/" + shift + "/assignments"), managerToken, Map.of("employeeId", employee))
                .andExpect(status().isNoContent());
    }

    private long assignmentId(long shift, long employee) {
        return jdbc.queryForObject("SELECT id FROM shift_assignments WHERE shift_id = ? AND employee_id = ?",
                Long.class, shift, employee);
    }

    @Test
    void managerAssignsAndOverviewShowsStaffing() throws Exception {
        OffsetDateTime start = OffsetDateTime.now().plusDays(2);
        long shift = createShift(branch, start, 4, 2);
        assign(shift, emp1);

        send(get("/api/schedule/shifts/overview").param("branchId", Long.toString(branch)), managerToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].assigned_count").value(1))
                .andExpect(jsonPath("$[0].assigned_staff_names").value(org.hamcrest.Matchers.containsString("An")));

        send(get("/api/schedule/shifts/" + shift + "/eligible-employees"), managerToken, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id == " + emp1 + ")].conflict_reason").value("Đã phân vào ca này"))
                .andExpect(jsonPath("$[?(@.id == " + emp2 + ")].is_available").value(true));

        // overlapping shift for the same employee is refused
        long overlap = createShift(branch, start.plusHours(1), 2, 1);
        send(post("/api/schedule/shifts/" + overlap + "/assignments"), managerToken, Map.of("employeeId", emp1))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhân viên bị trùng giờ ca."));
        // employee of another branch is refused
        long foreign = employee("F" + UUID.randomUUID().toString().substring(0, 6), "Lạ", otherBranch, null);
        send(post("/api/schedule/shifts/" + shift + "/assignments"), managerToken, Map.of("employeeId", foreign))
                .andExpect(status().isBadRequest());
        // capacity
        assign(shift, emp2);
        long emp3 = employee("G" + UUID.randomUUID().toString().substring(0, 6), "Cường", branch, null);
        send(post("/api/schedule/shifts/" + shift + "/assignments"), managerToken, Map.of("employeeId", emp3))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Ca đã đủ nhân viên."));
    }

    @Test
    void managerCanUnassignAndCancelButNotAfterAttendance() throws Exception {
        long shift = createShift(branch, OffsetDateTime.now().plusDays(3), 3, 2);
        assign(shift, emp1);
        send(delete("/api/schedule/shifts/" + shift + "/assignments/" + emp1), managerToken, null)
                .andExpect(status().isNoContent());
        assertEquals("cancelled", jdbc.queryForObject(
                "SELECT status FROM shift_assignments WHERE id = ?", String.class, assignmentId(shift, emp1)));

        assign(shift, emp1); // re-assign revives the cancelled row
        long assignment = assignmentId(shift, emp1);
        send(post("/api/schedule/shifts/" + shift + "/cancel"), managerToken, null).andExpect(status().isNoContent());
        assertEquals("cancelled", jdbc.queryForObject("SELECT status FROM shifts WHERE id = ?", String.class, shift));
        assertEquals("cancelled", jdbc.queryForObject(
                "SELECT status FROM shift_assignments WHERE id = ?", String.class, assignment));

        long shift2 = createShift(branch, OffsetDateTime.now().plusDays(4), 3, 1);
        assign(shift2, emp2);
        jdbc.update("INSERT INTO attendance_events (assignment_id, event_type, occurred_at, device_valid, gps_valid, "
                + "wifi_valid, result) VALUES (?, 'check_in', now(), TRUE, TRUE, TRUE, 'accepted')",
                assignmentId(shift2, emp2));
        send(post("/api/schedule/shifts/" + shift2 + "/cancel"), managerToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Không thể hủy ca đã có chấm công."));
        send(delete("/api/schedule/shifts/" + shift2 + "/assignments/" + emp2), managerToken, null)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Không thể bỏ phân công đã có chấm công."));
    }

    @Test
    void employeeCannotUseManagerEndpoints() throws Exception {
        send(get("/api/schedule/shifts/overview"), token1, null).andExpect(status().isForbidden());
        send(get("/api/schedule/shifts/1/eligible-employees"), token1, null).andExpect(status().isForbidden());
        send(delete("/api/schedule/shifts/1/assignments/1"), token1, null).andExpect(status().isForbidden());
        send(post("/api/schedule/shifts/1/cancel"), token1, null).andExpect(status().isForbidden());
        send(post("/api/schedule/shifts"), token1, Map.of("branchId", branch,
                "start", OffsetDateTime.now().plusDays(1).toString(),
                "end", OffsetDateTime.now().plusDays(1).plusHours(2).toString())).andExpect(status().isForbidden());
    }

    @Test
    void employeeSeesOwnScheduleAndShiftDetailOnlyForOwnShifts() throws Exception {
        long mine = createShift(branch, OffsetDateTime.now().plusDays(5), 3, 2);
        long notMine = createShift(branch, OffsetDateTime.now().plusDays(6), 3, 2);
        assign(mine, emp1);
        assign(mine, emp2);
        assign(notMine, emp2);

        send(get("/api/schedule/my-schedule"), token1, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].coworkers").value(org.hamcrest.Matchers.containsString("Bình")))
                .andExpect(jsonPath("$[0].total_assigned").value(2));
        send(get("/api/schedule/shifts"), token1, null)
                .andExpect(jsonPath("$.length()").value(1));
        send(get("/api/schedule/shifts/" + mine), token1, null)
                .andExpect(status().isOk()).andExpect(jsonPath("$.roster.length()").value(2));
        send(get("/api/schedule/shifts/" + notMine), token1, null)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Bạn không thuộc ca này."));
    }

    @Test
    void leaveRequestIsStoredAndApprovedLeaveBlocksAssignment() throws Exception {
        OffsetDateTime start = OffsetDateTime.now().plusDays(7);
        Long type = jdbc.queryForObject("SELECT id FROM leave_types WHERE code = 'ANNUAL'", Long.class);
        send(post("/api/schedule/leave-requests"), token1, Map.of("leaveTypeId", type,
                "start", start.toString(), "end", start.plusHours(8).toString(), "reason", " Việc nhà "))
                .andExpect(status().isCreated());
        send(get("/api/schedule/leave-requests"), token1, null)
                .andExpect(jsonPath("$[0].reason").value("Việc nhà"))
                .andExpect(jsonPath("$[0].requested_minutes").value(480))
                .andExpect(jsonPath("$[0].leave_type_name").value("Nghỉ phép năm"));
        send(post("/api/schedule/leave-requests"), token1, Map.of("leaveTypeId", type,
                "start", start.toString(), "end", start.minusHours(1).toString(), "reason", "x"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Thời gian kết thúc phải sau thời gian bắt đầu."));

        jdbc.update("UPDATE leave_requests SET status = 'approved', reviewed_by = ?, reviewed_at = now() "
                + "WHERE employee_id = ?", reviewerUser, emp1);
        long shift = createShift(branch, start.plusHours(1), 2, 1);
        send(post("/api/schedule/shifts/" + shift + "/assignments"), managerToken, Map.of("employeeId", emp1))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Nhân viên đang nghỉ phép."));
    }

    @Test
    void swapFlowRequiresCounterpartThenIndependentManager() throws Exception {
        long s1 = createShift(branch, OffsetDateTime.now().plusDays(8), 3, 1);
        long s2 = createShift(branch, OffsetDateTime.now().plusDays(9), 3, 1);
        assign(s1, emp1);
        assign(s2, emp2);
        long a1 = assignmentId(s1, emp1);
        long a2 = assignmentId(s2, emp2);

        send(get("/api/schedule/assignments/" + a1 + "/swap-options"), token1, null)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id == " + a2 + ")]").isNotEmpty());

        String res = send(post("/api/schedule/swaps"), token1,
                Map.of("fromAssignmentId", a1, "toAssignmentId", a2, "reason", "Bận việc"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        long swap = json.readTree(res).get("id").asLong();
        // counterpart (user2) got notified
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.related_id = ? "
                + "AND n.related_entity = 'shift_swap_requests'", Integer.class, user2, swap));

        // manager cannot approve before counterpart accepts
        send(post("/api/schedule/swaps/" + swap + "/review"), reviewerToken, Map.of("accept", true))
                .andExpect(status().isConflict());
        // requester is not the counterpart
        send(post("/api/schedule/swaps/" + swap + "/respond"), token1, Map.of("accept", true))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Chỉ người nhận được phản hồi một lần."));
        send(post("/api/schedule/swaps/" + swap + "/respond"), token2, Map.of("accept", true))
                .andExpect(status().isNoContent());
        // reviewers were notified
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM notification_recipients r JOIN notifications n "
                + "ON n.id = r.notification_id WHERE r.user_id = ? AND n.title = 'Đổi ca chờ duyệt' "
                + "AND n.related_id = ?", Integer.class, reviewerUser, swap));

        send(post("/api/schedule/swaps/" + swap + "/review"), reviewerToken, Map.of("accept", true))
                .andExpect(status().isNoContent());
        assertEquals(emp2, jdbc.queryForObject("SELECT employee_id FROM shift_assignments WHERE id = ?",
                Long.class, a1));
        assertEquals(emp1, jdbc.queryForObject("SELECT employee_id FROM shift_assignments WHERE id = ?",
                Long.class, a2));
        send(post("/api/schedule/swaps/" + swap + "/review"), reviewerToken, Map.of("accept", true))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.message").value("Yêu cầu đã được xử lý."));

        send(get("/api/schedule/swaps"), token1, null)
                .andExpect(jsonPath("$[0].status").value("approved"))
                .andExpect(jsonPath("$[0].from_name").exists());
    }

    @Test
    void counterpartRejectionClosesSwapAndRejectsPastShifts() throws Exception {
        long s1 = createShift(branch, OffsetDateTime.now().plusDays(10), 3, 1);
        long s2 = createShift(branch, OffsetDateTime.now().plusDays(11), 3, 1);
        assign(s1, emp1);
        assign(s2, emp2);
        long a1 = assignmentId(s1, emp1);
        long a2 = assignmentId(s2, emp2);
        send(post("/api/schedule/swaps"), token1, Map.of("fromAssignmentId", a1, "toAssignmentId", a1, "reason", "x"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Chọn ca khác và nhập lý do."));
        long swap = json.readTree(send(post("/api/schedule/swaps"), token1,
                Map.of("fromAssignmentId", a1, "toAssignmentId", a2, "reason", "Bận"))
                .andReturn().getResponse().getContentAsString()).get("id").asLong();
        send(post("/api/schedule/swaps/" + swap + "/respond"), token2, Map.of("accept", false))
                .andExpect(status().isNoContent());
        assertEquals("rejected", jdbc.queryForObject("SELECT status FROM shift_swap_requests WHERE id = ?",
                String.class, swap));
        assertEquals(List.of(emp1), jdbc.queryForList("SELECT employee_id FROM shift_assignments WHERE id = ?",
                Long.class, a1));
    }
}
