package vn.anhemquan.prm.config;

import vn.anhemquan.prm.repository.Db;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Local development only ({@code --spring.profiles.active=dev}): creates the README sample accounts
 * and one branch when the database has no users. Never enabled by default.
 */
@Component
@Profile("dev")
class DevDataSeeder implements CommandLineRunner {

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;

    DevDataSeeder(JdbcTemplate jdbc, PasswordEncoder encoder) {
        this.jdbc = jdbc;
        this.encoder = encoder;
    }

    @Override
    public void run(String... args) {
        if (!jdbc.queryForList("SELECT 1 FROM users LIMIT 1").isEmpty()) {
            return;
        }
        jdbc.update("INSERT INTO branches (code, name, address) VALUES ('MAIN', 'ANH EM QUÁN - Chi nhánh chính', '')");
        Long branch = jdbc.queryForObject("SELECT id FROM branches WHERE code = 'MAIN'", Long.class);
        account("admin", "Admin@12345", "admin", "Quản trị viên", "EMP-ADMIN", branch);
        account("manager", "Manager@12345", "manager", "Quản lý mẫu", "EMP-MANAGER", branch);
        account("employee", "Employee@12345", "employee", "Nhân viên mẫu", "EMP-EMPLOYEE", branch);
    }

    private void account(String username, String password, String role, String fullName, String code, Long branch) {
        Long user = Db.insert(jdbc,
                "INSERT INTO users (username, password_hash) VALUES (?, ?)", username, encoder.encode(password));
        jdbc.update("INSERT INTO user_roles (user_id, role_id) SELECT ?, id FROM roles WHERE code = ?", user, role);
        jdbc.update("INSERT INTO employees (user_id, employee_code, full_name, branch_id, hire_date) "
                + "VALUES (?, ?, ?, ?, CURRENT_DATE)", user, code, fullName, branch);
    }
}
