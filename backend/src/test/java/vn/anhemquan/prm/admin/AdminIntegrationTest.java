package vn.anhemquan.prm.admin;

import vn.anhemquan.prm.repository.Db;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class AdminIntegrationTest extends AbstractIntegrationTest {

    private static String unique(String prefix) {
        return prefix + "-" + UUID.randomUUID().toString().substring(0, 8);
    }

    private String bearer(String user, String password) throws Exception {
        return "Bearer " + login(user, password);
    }

    @Test
    void adminCreatesUserAndNewUserCanSignIn() throws Exception {
        String admin = unique("admin");
        createUser(admin, "Admin@12345", "admin", null);
        String name = unique("staff");

        mvc.perform(post("/api/users").header("Authorization", bearer(admin, "Admin@12345"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("username", name, "password", "Staff@12345", "role", "employee"))))
                .andExpect(status().isCreated());
        login(name, "Staff@12345");

        mvc.perform(post("/api/users").header("Authorization", bearer(admin, "Admin@12345"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("username", name.toUpperCase(), "password", "Staff@12345", "role", "employee"))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.message").value("Tên đăng nhập đã tồn tại."));
        mvc.perform(post("/api/users").header("Authorization", bearer(admin, "Admin@12345"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("username", unique("x"), "password", "short", "role", "employee"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    void employeeCannotManageUsersOrEmployees() throws Exception {
        String employee = unique("emp");
        createUser(employee, "Employee@12345", "employee", null);
        String auth = bearer(employee, "Employee@12345");

        mvc.perform(get("/api/users").header("Authorization", auth)).andExpect(status().isForbidden());
        mvc.perform(get("/api/employees").header("Authorization", auth)).andExpect(status().isForbidden());
        mvc.perform(get("/api/profile").header("Authorization", auth)).andExpect(status().isOk());
    }

    @Test
    void managerCreatesEmployeeAndRejectsDuplicateCode() throws Exception {
        jdbc.update("INSERT IGNORE INTO branches (code, name) VALUES (?, 'Admin test branch')",
                unique("BR"));
        String manager = unique("mgr");
        createUser(manager, "Manager@12345", "manager", null);
        String auth = bearer(manager, "Manager@12345");
        String code = unique("E");

        Map<String, String> body = Map.of("code", code, "name", "Nguyễn Văn A", "phone", "0900000000");
        mvc.perform(post("/api/employees").header("Authorization", auth).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(body)))
                .andExpect(status().isCreated());
        mvc.perform(post("/api/employees").header("Authorization", auth).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(body)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.message").value("Mã nhân viên đã tồn tại."));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM employees WHERE employee_code = ?", Integer.class, code));
    }

    @Test
    void notificationsAreListedAndMarkedReadPerRecipient() throws Exception {
        String name = unique("notif");
        long user = createUser(name, "Employee@12345", "employee", null);
        long id = Db.insert(jdbc,
                "INSERT INTO notifications (title, body, notification_type) VALUES ('t', 'b', 'workflow')");
        jdbc.update("INSERT INTO notification_recipients (notification_id, user_id) VALUES (?, ?)", id, user);
        String auth = bearer(name, "Employee@12345");

        mvc.perform(get("/api/notifications").header("Authorization", auth))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].title").value("t"))
                .andExpect(jsonPath("$[0].read_at").doesNotExist());
        mvc.perform(post("/api/notifications/" + id + "/read").header("Authorization", auth))
                .andExpect(status().isNoContent());
        mvc.perform(get("/api/notifications").header("Authorization", auth))
                .andExpect(jsonPath("$[0].read_at").isNotEmpty());
    }

    @Test
    void overviewHidesEmployeeCountFromEmployees() throws Exception {
        String name = unique("ov");
        createUser(name, "Employee@12345", "employee", null);

        mvc.perform(get("/api/overview").header("Authorization", bearer(name, "Employee@12345")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.employees").doesNotExist())
                .andExpect(jsonPath("$.shifts").value(0))
                .andExpect(jsonPath("$.payslips").value(0));
    }
}
