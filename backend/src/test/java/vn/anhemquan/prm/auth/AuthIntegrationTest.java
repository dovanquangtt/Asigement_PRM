package vn.anhemquan.prm.auth;

import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import vn.anhemquan.prm.common.ApiException;
import vn.anhemquan.prm.support.AbstractIntegrationTest;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class AuthIntegrationTest extends AbstractIntegrationTest {

    @MockBean
    GoogleTokenVerifier google;

    @BeforeEach
    void clean() {
        String names = "('authit-manager', 'authit-employee', 'authit-admin', 'authit-anna', 'authit-bob', 'authit-c1', 'authit-c2')";
        jdbc.update("DELETE FROM user_roles WHERE user_id IN (SELECT id FROM users WHERE username IN " + names + ")");
        jdbc.update("DELETE FROM users WHERE username IN " + names);
    }

    private String body(Object value) throws Exception {
        return json.writeValueAsString(value);
    }

    @Test
    void passwordLoginReturnsSessionWithRoleAndPermissions() throws Exception {
        createUser("authit-manager", "Manager@12345", "manager", "m@example.com");

        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("username", "AUTHIT-MANAGER", "password", "Manager@12345"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.session.role").value("Quản lý"))
                .andExpect(jsonPath("$.session.permissions[?(@ == 'shifts.manage')]").isNotEmpty())
                .andExpect(jsonPath("$.session.permissions[?(@ == 'users.manage')]").isEmpty());
    }

    @Test
    void wrongPasswordIsRejectedWithGenericMessage() throws Exception {
        createUser("authit-employee", "Employee@12345", "employee", null);

        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("username", "authit-employee", "password", "nope-nope"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.message").value(AuthService.INVALID_CREDENTIALS));
    }

    @Test
    void tokenAuthenticatesMeEndpoint() throws Exception {
        createUser("authit-admin", "Admin@12345", "admin", null);
        String token = login("authit-admin", "Admin@12345");

        mvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("authit-admin"))
                .andExpect(jsonPath("$.role").value("Admin"));
    }

    @Test
    void googleLoginLinksSubjectOnFirstUseAndRejectsOtherSubjectLater() throws Exception {
        long id = createUser("authit-anna", "Anna@12345", "employee", "Anna@Example.com");
        when(google.verify("good")).thenReturn(new GoogleIdentity("sub-1", "anna@example.com"));
        when(google.verify("other")).thenReturn(new GoogleIdentity("sub-2", "anna@example.com"));

        mvc.perform(post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("idToken", "good"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.session.username").value("authit-anna"))
                .andExpect(jsonPath("$.session.role").value("Nhân viên"));
        org.junit.jupiter.api.Assertions.assertEquals("sub-1",
                jdbc.queryForObject("SELECT google_subject FROM users WHERE id = ?", String.class, id));

        mvc.perform(post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("idToken", "other"))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Liên kết Google không khớp."));
    }

    @Test
    void googleLoginRejectsUnknownEmailAndInactiveAccounts() throws Exception {
        long id = createUser("authit-bob", "Bob@123456", "employee", "bob@example.com");
        jdbc.update("UPDATE users SET is_active = FALSE WHERE id = ?", id);
        when(google.verify("bob")).thenReturn(new GoogleIdentity("sub-b", "bob@example.com"));
        when(google.verify("stranger")).thenReturn(new GoogleIdentity("sub-s", "stranger@example.com"));

        for (String token : new String[] {"bob", "stranger"}) {
            mvc.perform(post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                            .content(body(Map.of("idToken", token))))
                    .andExpect(status().isForbidden());
        }
    }

    @Test
    void googleLoginRejectsSubjectAlreadyLinkedToAnotherAccount() throws Exception {
        long first = createUser("authit-c1", "Pass@12345", "employee", "c1@example.com");
        createUser("authit-c2", "Pass@12345", "employee", "c2@example.com");
        jdbc.update("UPDATE users SET google_subject = 'shared' WHERE id = ?", first);
        when(google.verify("t")).thenReturn(new GoogleIdentity("shared", "c2@example.com"));

        mvc.perform(post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("idToken", "t"))))
                .andExpect(status().isConflict());
    }

    @Test
    void invalidGoogleTokenIsUnauthorized() throws Exception {
        when(google.verify(anyString())).thenThrow(ApiException.unauthorized("Google ID token không hợp lệ."));

        mvc.perform(post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("idToken", "garbage"))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void bootstrapIsRefusedOnceAnAccountExists() throws Exception {
        createUser("authit-admin", "Admin@12345", "admin", null);

        mvc.perform(post("/api/auth/bootstrap").contentType(MediaType.APPLICATION_JSON)
                        .content(body(Map.of("username", "root2", "password", "Root@12345"))))
                .andExpect(status().isConflict());
        mvc.perform(get("/api/auth/bootstrap")).andExpect(jsonPath("$.needsFirstAdmin").value(false));
    }
}
