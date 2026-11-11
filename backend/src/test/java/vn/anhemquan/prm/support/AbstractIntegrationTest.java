package vn.anhemquan.prm.support;

import com.fasterxml.jackson.databind.ObjectMapper;
import vn.anhemquan.prm.repository.Db;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.http.MediaType;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Boots the whole application against the configured MySQL database (default prm_database, see
 * application.yml / DB_URL, DB_USER, DB_PASSWORD) so Flyway migrations and MySQL-specific SQL are exercised.
 * Tests insert their own uniquely named rows and leave them behind; they never drop or truncate anything.
 */
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest {

    @Autowired
    protected MockMvc mvc;
    @Autowired
    protected JdbcTemplate jdbc;
    @Autowired
    protected PasswordEncoder encoder;
    @Autowired
    protected ObjectMapper json;

    /** Inserts an active user with the given role code and returns its id. */
    protected long createUser(String username, String password, String role, String email) {
        Long id = Db.insert(jdbc,
                "INSERT INTO users (username, password_hash, email) VALUES (?, ?, ?)", username, encoder.encode(password), email);
        jdbc.update("INSERT INTO user_roles (user_id, role_id) SELECT ?, id FROM roles WHERE code = ?", id, role);
        return id;
    }

    /** Signs in with a password and returns the bearer token. */
    protected String login(String username, String password) throws Exception {
        MvcResult result = mvc.perform(MockMvcRequestBuilders.post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return json.readTree(result.getResponse().getContentAsString()).get("accessToken").asText();
    }
}
