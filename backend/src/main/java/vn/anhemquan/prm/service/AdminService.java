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

    /** Roles an Admin may create accounts for: never another Admin. */
    private static final List<String> ROLES = List.of("manager", "employee");

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

    /**
     * Creates a Manager or Employee account (never an Admin) together with its linked employee profile so
     * the person can use every function of the role from the first sign-in: profile in {@code branchId}
     * (default: first branch), Service department, role-based position, the default annual leave (12 days, like
     * the sample profile) and a contract when {@code monthlySalary} is given. Returns the employee id.
     */
    @Transactional
    public long createUser(String username, String password, String role, String fullName, Long branchId,
            String phone, Long monthlySalary) {
        access.require("users.manage");
        if (!ROLES.contains(role)) {
            throw ApiException.badRequest("Chỉ tạo được tài khoản Quản lý hoặc Nhân viên.");
        }
        String name = username == null ? "" : username.trim();
        if (name.isEmpty() || name.length() > 100) {
            throw ApiException.badRequest("Tên đăng nhập phải có từ 1 đến 100 ký tự.");
        }
        if (fullName == null || fullName.isBlank()) {
            throw ApiException.badRequest("Nhập họ tên nhân viên.");
        }
        if (monthlySalary != null && monthlySalary < 0) {
            throw ApiException.badRequest("Lương tháng không hợp lệ.");
        }
        String hash = auth.hashPassword(password);
        List<Long> roles = jdbc.queryForList("SELECT id FROM roles WHERE code = ?", Long.class, role);
        if (roles.isEmpty()) {
            throw ApiException.badRequest("Vai trò không hợp lệ.");
        }
        if (!jdbc.queryForList("SELECT 1 FROM users WHERE LOWER(username) = LOWER(?)", name).isEmpty()) {
            throw ApiException.conflict("Tên đăng nhập đã tồn tại.");
        }
        List<Long> branches = branchId == null
                ? jdbc.queryForList("SELECT id FROM branches ORDER BY id LIMIT 1", Long.class)
                : jdbc.queryForList("SELECT id FROM branches WHERE id = ?", Long.class, branchId);
        if (branches.isEmpty()) {
            throw ApiException.badRequest(branchId == null ? "Cần tạo chi nhánh trước khi tạo tài khoản."
                    : "Chi nhánh không hợp lệ.");
        }
        Long userId = Db.insert(jdbc, "INSERT INTO users (username, password_hash) VALUES (?, ?)", name, hash);
        jdbc.update("INSERT INTO user_roles (user_id, role_id) VALUES (?, ?)", userId, roles.get(0));
        String code = String.format("NV%03d", userId);
        for (int n = 1; !jdbc.queryForList("SELECT 1 FROM employees WHERE employee_code = ?", code).isEmpty(); n++) {
            code = String.format("NV%03d_%d", userId, n);
        }
        long employeeId = Db.insert(jdbc,
                "INSERT INTO employees (user_id, employee_code, full_name, phone, branch_id, department_id, "
                        + "position_id, hire_date, status) VALUES (?, ?, ?, ?, ?, "
                        + "(SELECT id FROM departments WHERE code = 'SERVICE'), "
                        + "(SELECT id FROM positions WHERE code = ?), ?, 'active')",
                userId, code, fullName.trim(), phone == null ? "" : phone.trim(), branches.get(0),
                "manager".equals(role) ? "MANAGER" : "WAITER", LocalDate.now(AppTime.ZONE));
        jdbc.update("INSERT INTO leave_balances (employee_id, leave_type_id, year, granted_minutes, used_minutes) "
                + "SELECT ?, id, ?, 5760, 0 FROM leave_types WHERE code = 'ANNUAL'", employeeId,
                LocalDate.now(AppTime.ZONE).getYear());
        if (monthlySalary != null && monthlySalary > 0) {
            jdbc.update("INSERT INTO contracts (employee_id, contract_number, contract_type, start_date, salary_basis, "
                    + "base_salary_vnd, standard_minutes_per_month, status) "
                    + "VALUES (?, ?, 'indefinite', ?, 'monthly', ?, 12480, 'active')", employeeId, "HD-" + code,
                    LocalDate.now(AppTime.ZONE), monthlySalary);
        }
        return employeeId;
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
