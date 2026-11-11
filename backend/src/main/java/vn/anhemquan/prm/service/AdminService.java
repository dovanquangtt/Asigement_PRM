package vn.anhemquan.prm.service;

import vn.anhemquan.prm.repository.Db;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;

/** Accounts, employee records, own profile, dashboard counters and in-app notifications. */
@Service
public class AdminService {

    private static final List<String> ROLES = List.of("admin", "manager", "employee");

    private final JdbcTemplate jdbc;
    private final Access access;
    private final AuthService auth;

    public AdminService(JdbcTemplate jdbc, Access access, AuthService auth) {
        this.jdbc = jdbc;
        this.access = access;
        this.auth = auth;
    }

    public List<Map<String, Object>> notifications() {
        access.require("profile.self");
        return jdbc.queryForList(
                "SELECT n.*, r.read_at FROM notifications n "
                        + "JOIN notification_recipients r ON r.notification_id = n.id "
                        + "WHERE r.user_id = ? ORDER BY n.id DESC",
                access.userId());
    }

    public void markNotificationRead(long id) {
        access.require("profile.self");
        jdbc.update("UPDATE notification_recipients SET read_at = CURRENT_TIMESTAMP "
                + "WHERE notification_id = ? AND user_id = ? AND read_at IS NULL", id, access.userId());
    }

    public List<Map<String, Object>> users() {
        access.require("users.manage");
        return jdbc.queryForList(
                "SELECT u.id, u.username, u.email, u.is_active, GROUP_CONCAT(r.name ORDER BY r.id SEPARATOR ', ') AS roles "
                        + "FROM users u LEFT JOIN user_roles ur ON ur.user_id = u.id "
                        + "LEFT JOIN roles r ON r.id = ur.role_id GROUP BY u.id ORDER BY u.id");
    }

    public List<Map<String, Object>> employees() {
        access.require("employees.manage");
        return jdbc.queryForList(
                "SELECT e.*, b.name AS branch_name, d.name AS department_name FROM employees e "
                        + "JOIN branches b ON b.id = e.branch_id "
                        + "LEFT JOIN departments d ON d.id = e.department_id ORDER BY e.full_name");
    }

    public Map<String, Object> profile() {
        access.require("profile.self");
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT u.username, u.email, e.employee_code, e.full_name, e.phone, e.hire_date, e.status, "
                        + "b.name AS branch_name FROM users u LEFT JOIN employees e ON e.user_id = u.id "
                        + "LEFT JOIN branches b ON b.id = e.branch_id WHERE u.id = ? AND u.is_active",
                access.userId());
        if (rows.isEmpty()) {
            throw ApiException.unauthorized("Phiên đăng nhập không hợp lệ.");
        }
        return rows.get(0);
    }

    /** Dashboard counters; shift and payslip counts follow the same visibility as the list endpoints. */
    public Map<String, Object> overview() {
        access.require("profile.self");
        long user = access.userId();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("employees", access.can("reports.view")
                ? jdbc.queryForObject("SELECT COUNT(*) FROM employees WHERE status = 'active'", Long.class)
                : null);
        boolean managingShifts = access.can("shifts.manage");
        result.put("shifts", jdbc.queryForObject(
                "SELECT COUNT(*) FROM shift_assignments a JOIN employees e ON e.id = a.employee_id "
                        + "WHERE ? OR e.user_id = ?",
                Long.class, managingShifts, user));
        boolean managingPayroll = access.can("payroll.manage");
        result.put("payslips", jdbc.queryForObject(
                "SELECT COUNT(*) FROM payslips p JOIN employees e ON e.id = p.employee_id "
                        + "WHERE ? OR e.user_id = ?",
                Long.class, managingPayroll, user));
        return result;
    }

    @Transactional
    public void createUser(String username, String password, String role) {
        access.require("users.manage");
        String hash = auth.hashPassword(password);
        String name = username == null ? "" : username.trim();
        if (name.isEmpty() || name.length() > 100) {
            throw ApiException.badRequest("Tên đăng nhập phải có từ 1 đến 100 ký tự.");
        }
        List<Long> roles = ROLES.contains(role)
                ? jdbc.queryForList("SELECT id FROM roles WHERE code = ?", Long.class, role)
                : List.of();
        if (roles.isEmpty()) {
            throw ApiException.badRequest("Vai trò không hợp lệ.");
        }
        if (!jdbc.queryForList("SELECT 1 FROM users WHERE LOWER(username) = LOWER(?)", name).isEmpty()) {
            throw ApiException.conflict("Tên đăng nhập đã tồn tại.");
        }
        Long id = Db.insert(jdbc,
                "INSERT INTO users (username, password_hash) VALUES (?, ?)", name, hash);
        jdbc.update("INSERT INTO user_roles (user_id, role_id) VALUES (?, ?)", id, roles.get(0));
    }

    @Transactional
    public void createEmployee(String code, String name, String phone) {
        if (code == null || code.isBlank() || name == null || name.isBlank()) {
            throw ApiException.badRequest("Nhập mã và tên nhân viên.");
        }
        access.require("employees.manage");
        List<Long> branches = jdbc.queryForList("SELECT id FROM branches ORDER BY id LIMIT 1", Long.class);
        if (branches.isEmpty()) {
            throw ApiException.badRequest("Cần tạo chi nhánh trước khi thêm nhân viên.");
        }
        if (!jdbc.queryForList("SELECT 1 FROM employees WHERE employee_code = ?", code.trim()).isEmpty()) {
            throw ApiException.conflict("Mã nhân viên đã tồn tại.");
        }
        jdbc.update("INSERT INTO employees (employee_code, full_name, phone, branch_id, hire_date) "
                        + "VALUES (?, ?, ?, ?, ?)",
                code.trim(), name.trim(), phone == null ? "" : phone.trim(), branches.get(0),
                LocalDate.now(AppTime.ZONE));
    }
}
