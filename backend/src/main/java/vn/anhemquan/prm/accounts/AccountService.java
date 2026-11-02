package vn.anhemquan.prm.accounts;

import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.common.Access;
import vn.anhemquan.prm.common.ApiException;

/** Admin tools linking user accounts to e-mails (for Google sign-in) and to employee profiles. */
@Service
public class AccountService {

    private static final Pattern EMAIL = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

    private final JdbcTemplate jdbc;
    private final Access access;

    public AccountService(JdbcTemplate jdbc, Access access) {
        this.jdbc = jdbc;
        this.access = access;
    }

    /** Changing the e-mail also clears the Google link so the new Gmail must be verified again. */
    @Transactional
    public void setUserEmail(long userId, String email) {
        if (email == null || !EMAIL.matcher(email.trim()).matches()) {
            throw ApiException.badRequest("Email không hợp lệ.");
        }
        access.require("users.manage");
        jdbc.update("UPDATE users SET email = ?, google_subject = NULL WHERE id = ?",
                email.trim().toLowerCase(), userId);
    }

    public List<Map<String, Object>> unlinkedAccounts() {
        access.require("employees.manage");
        return jdbc.queryForList("SELECT u.id, u.username FROM users u LEFT JOIN employees e ON e.user_id = u.id "
                + "WHERE e.id IS NULL AND u.is_active ORDER BY u.username");
    }

    @Transactional
    public void linkEmployee(long employeeId, long userId) {
        access.require("employees.manage");
        if (jdbc.queryForList("SELECT 1 FROM employees WHERE id = ? AND user_id IS NULL", employeeId).isEmpty()) {
            throw ApiException.badRequest("Hồ sơ đã có tài khoản hoặc không tồn tại.");
        }
        if (jdbc.queryForList("SELECT 1 FROM users WHERE id = ? AND is_active", userId).isEmpty()) {
            throw ApiException.badRequest("Tài khoản không hợp lệ.");
        }
        jdbc.update("UPDATE employees SET user_id = ? WHERE id = ?", userId, employeeId);
    }
}
