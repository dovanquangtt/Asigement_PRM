package vn.anhemquan.prm.service;

import vn.anhemquan.prm.repository.Db;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.exception.ApiException;
import vn.anhemquan.prm.util.AppTime;

/** Payroll periods, contracts, 6-step calculation, pay items and approval (ported from Flutter M02/M06). */
@Service
public class PayrollService {

    static final List<String> STEP_NAMES = List.of(
            "Kiểm tra kỳ lương và hồ sơ",
            "Kiểm tra hợp đồng và đơn giá",
            "Tổng hợp công hợp lệ",
            "Tính lương thường và tăng ca",
            "Tổng hợp khoản cộng/trừ",
            "Kiểm tra và lưu phiếu lương");
    static final Set<String> ITEM_TYPES = Set.of("allowance", "bonus", "deduction", "tax", "insurance");

    private final JdbcTemplate jdbc;
    private final Access access;
    private final Notifier notifier;
    private final PayrollSourceHash sourceHash;
    private final ObjectMapper mapper = new ObjectMapper();

    public PayrollService(JdbcTemplate jdbc, Access access, Notifier notifier, PayrollSourceHash sourceHash) {
        this.jdbc = jdbc;
        this.access = access;
        this.notifier = notifier;
        this.sourceHash = sourceHash;
    }

    private Map<String, Object> me(long userId) {
        access.require("profile.self");
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT * FROM employees WHERE user_id = ? AND status = 'active'", userId);
        if (rows.isEmpty()) {
            throw ApiException.forbidden("Tài khoản chưa được liên kết hồ sơ nhân viên đang làm việc.");
        }
        return rows.get(0);
    }

    private void audit(long actor, String action, String entity, long id, Map<String, Object> detail) {
        try {
            notifier.audit(actor, action, entity, id, null, mapper.writeValueAsString(detail));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private static long num(Object value) {
        return ((Number) value).longValue();
    }

    public List<Map<String, Object>> periods() {
        access.require("payslips.self");
        return jdbc.queryForList("SELECT p.*, pol.overtime_multiplier FROM payroll_periods p "
                + "LEFT JOIN payroll_policies pol ON pol.period_id = p.id ORDER BY p.starts_on DESC");
    }

    public List<Map<String, Object>> payslips() {
        boolean managing = access.can("payroll.manage");
        if (!managing) {
            access.require("payslips.self");
        }
        String sql = "SELECT p.*, e.full_name, pp.code AS period_code, pp.starts_on, pp.ends_on "
                + "FROM v_payslip_totals p JOIN employees e ON e.id = p.employee_id "
                + "JOIN payroll_periods pp ON pp.id = p.period_id "
                + (managing ? "" : "WHERE e.user_id = ? ") + "ORDER BY pp.starts_on DESC, e.full_name";
        return managing ? jdbc.queryForList(sql) : jdbc.queryForList(sql, access.userId());
    }

    @Transactional
    public long createPeriod(String code, LocalDate start, LocalDate end, double multiplier) {
        if (code == null || code.isBlank() || start == null || end == null || end.isBefore(start)
                || !Double.isFinite(multiplier) || multiplier < 1) {
            throw ApiException.badRequest("Kỳ lương hoặc hệ số tăng ca không hợp lệ.");
        }
        access.require("payroll.manage");
        long actor = access.userId();
        Long id = Db.insert(jdbc,
                "INSERT INTO payroll_periods (code, starts_on, ends_on) VALUES (?, ?, ?)", code.trim(), java.sql.Date.valueOf(start), java.sql.Date.valueOf(end));
        jdbc.update("INSERT INTO payroll_policies (period_id, overtime_multiplier, created_by) VALUES (?, ?, ?)",
                id, multiplier, actor);
        return id;
    }

    @Transactional
    public void saveContract(long employeeId, String number, long monthlySalary, int standardMinutes,
            LocalDate startsOn) {
        if (number == null || number.isBlank() || monthlySalary < 0 || standardMinutes <= 0 || startsOn == null) {
            throw ApiException.badRequest("Thông tin hợp đồng không hợp lệ.");
        }
        access.require("employees.manage");
        jdbc.update("INSERT INTO contracts (employee_id, contract_number, contract_type, start_date, salary_basis, "
                + "base_salary_vnd, standard_minutes_per_month, status) "
                + "VALUES (?, ?, 'indefinite', ?, 'monthly', ?, ?, 'active')",
                employeeId, number.trim(), java.sql.Date.valueOf(startsOn), monthlySalary, standardMinutes);
    }

    /**
     * Managers calculate a whole period; an employee only calculates their own draft.
     * The multiplier comes from the period policy; no tax or allowance is added automatically.
     */
    @Transactional
    public Map<String, Object> calculatePay(long periodId, Long requestedEmployee) {
        long actor = access.userId();
        boolean managing = access.can("payroll.manage");
        Long employeeId = requestedEmployee;
        if (!managing) {
            access.require("payslips.self");
            long mine = num(me(actor).get("id"));
            if (employeeId != null && employeeId != mine) {
                throw ApiException.forbidden("Chỉ tính phiếu lương của chính mình.");
            }
            employeeId = mine;
        }
        List<Map<String, Object>> found = jdbc.queryForList(
                "SELECT p.*, pol.overtime_multiplier FROM payroll_periods p "
                        + "JOIN payroll_policies pol ON pol.period_id = p.id WHERE p.id = ?", periodId);
        if (found.isEmpty() || Set.of("approved", "paid").contains(found.get(0).get("status"))) {
            throw ApiException.badRequest("Kỳ lương chưa có chính sách hoặc đã được chốt.");
        }
        Map<String, Object> p = found.get(0);
        List<Map<String, Object>> employees = employeeId == null
                ? jdbc.queryForList("SELECT * FROM employees WHERE status = 'active' ORDER BY id")
                : jdbc.queryForList("SELECT * FROM employees WHERE id = ? AND status = 'active'", employeeId);
        if (employees.isEmpty()) {
            throw ApiException.badRequest("Không có nhân viên để tính lương.");
        }
        boolean wholePeriod = managing && employeeId == null;
        if (wholePeriod) {
            Set<Long> keep = new HashSet<>();
            employees.forEach(e -> keep.add(num(e.get("id"))));
            for (Map<String, Object> old : jdbc.queryForList("SELECT * FROM payslips WHERE period_id = ?", periodId)) {
                if (keep.contains(num(old.get("employee_id")))) {
                    continue;
                }
                if (!"draft".equals(old.get("status"))) {
                    throw ApiException.badRequest("Không được xóa phiếu lương đã chốt.");
                }
                jdbc.update("DELETE FROM payslip_items WHERE payslip_id = ?", old.get("id"));
                jdbc.update("DELETE FROM employee_payroll_checks WHERE period_id = ? AND employee_id = ?",
                        periodId, old.get("employee_id"));
                jdbc.update("DELETE FROM payslips WHERE id = ?", old.get("id"));
            }
        }
        double multiplier = ((Number) p.get("overtime_multiplier")).doubleValue();
        long total = 0;
        Long employeePayslipId = null;
        for (Map<String, Object> e : employees) {
            long empId = num(e.get("id"));
            List<Map<String, Object>> contracts = jdbc.queryForList(
                    "SELECT * FROM contracts WHERE employee_id = ? AND status = 'active' AND start_date <= ? "
                            + "AND (end_date IS NULL OR end_date >= ?) ORDER BY start_date DESC, id DESC",
                    empId, p.get("starts_on"), p.get("ends_on"));
            if (contracts.isEmpty()) {
                throw ApiException.badRequest(
                        "Nhân viên " + e.get("full_name") + " chưa có hợp đồng bao phủ kỳ lương.");
            }
            Map<String, Object> c = contracts.get(0);
            List<Map<String, Object>> existingRows = jdbc.queryForList(
                    "SELECT * FROM payslips WHERE period_id = ? AND employee_id = ?", periodId, empId);
            Map<String, Object> existing = existingRows.isEmpty() ? null : existingRows.get(0);
            if (existing != null && !"draft".equals(existing.get("status"))) {
                throw ApiException.badRequest("Không được sửa phiếu lương đã chốt.");
            }
            List<Map<String, Object>> records = jdbc.queryForList(
                    "SELECT r.* FROM attendance_records r JOIN shift_assignments a ON a.id = r.assignment_id "
                            + "JOIN shifts s ON s.id = a.shift_id WHERE a.employee_id = ? "
                            + "AND r.status IN ('present', 'adjusted') AND r.check_out_at IS NOT NULL "
                            + "AND DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00')) BETWEEN ? AND ?",
                    empId, p.get("starts_on"), p.get("ends_on"));
            long regular = 0;
            long overtime = 0;
            for (Map<String, Object> r : records) {
                long otMinutes = num(r.get("overtime_minutes"));
                overtime += otMinutes;
                String status = (String) r.get("overtime_status");
                long unpaidExtra = "PENDING".equals(status) || "REJECTED".equals(status)
                        ? num(r.get("overtime_requested_minutes")) : 0;
                regular += num(r.get("worked_minutes")) - otMinutes - unpaidExtra;
            }
            double perMinute = "hourly".equals(c.get("salary_basis"))
                    ? num(c.get("hourly_rate_vnd")) / 60.0
                    : (double) num(c.get("base_salary_vnd")) / num(c.get("standard_minutes_per_month"));
            long base = Math.round(regular * perMinute);
            long ot = Math.round(overtime * perMinute * multiplier);
            long id;
            if (existing == null) {
                id = Db.insert(jdbc,
                        "INSERT INTO payslips (period_id, employee_id, contract_id, regular_minutes, overtime_minutes, "
                                + "base_pay_vnd, overtime_pay_vnd, calculated_at, status) "
                                + "VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, 'draft')", periodId, empId, c.get("id"), regular, overtime, base, ot);
            } else {
                id = num(existing.get("id"));
                jdbc.update("UPDATE payslips SET contract_id = ?, regular_minutes = ?, overtime_minutes = ?, "
                        + "base_pay_vnd = ?, overtime_pay_vnd = ?, calculated_at = CURRENT_TIMESTAMP, "
                        + "status = 'draft' WHERE id = ?", c.get("id"), regular, overtime, base, ot, id);
            }
            if (!managing) {
                employeePayslipId = id;
            }
            Map<String, Object> totals = jdbc.queryForMap("SELECT * FROM v_payslip_totals WHERE id = ?", id);
            long net = num(totals.get("net_pay_vnd"));
            if (net < 0) {
                throw ApiException.badRequest("Thực lĩnh âm, cần kiểm tra khoản khấu trừ.");
            }
            List<String> details = List.of(
                    "Kỳ " + p.get("code") + " • " + e.get("employee_code"),
                    "Hợp đồng " + c.get("contract_number") + " • "
                            + String.format(Locale.ROOT, "%.2f", perMinute) + " VND/phút",
                    regular + " phút thường, " + overtime + " phút tăng ca",
                    base + " VND + " + ot + " VND; hệ số " + multiplier,
                    "Khấu trừ " + num(totals.get("deductions_vnd")) + " VND",
                    "Phiếu #" + id + " • thực lĩnh " + net + " VND");
            for (int i = 0; i < 6; i++) {
                String hash = i == 5 ? sourceHash.compute(periodId, empId, num(c.get("id"))) : "";
                jdbc.update("INSERT INTO employee_payroll_checks (period_id, employee_id, step_number, name, detail, "
                        + "checked_at, source_hash) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?) "
                        + "ON DUPLICATE KEY UPDATE name = VALUES(name), "
                        + "detail = VALUES(detail), checked_at = VALUES(checked_at), "
                        + "source_hash = VALUES(source_hash)",
                        periodId, empId, i + 1, STEP_NAMES.get(i), details.get(i), hash);
            }
            total += net;
        }
        if (wholePeriod) {
            for (int i = 0; i < 6; i++) {
                jdbc.update("INSERT INTO payroll_calculation_steps (period_id, step_number, name, status, "
                        + "executed_by, executed_at, detail) VALUES (?, ?, ?, 'completed', ?, CURRENT_TIMESTAMP, ?) "
                        + "ON DUPLICATE KEY UPDATE name = VALUES(name), "
                        + "status = VALUES(status), executed_by = VALUES(executed_by), "
                        + "executed_at = VALUES(executed_at), detail = VALUES(detail)",
                        periodId, i + 1, STEP_NAMES.get(i), actor, "Đã kiểm tra " + employees.size() + " nhân viên");
            }
            jdbc.update("UPDATE payroll_periods SET status = 'calculating' WHERE id = ?", periodId);
        }
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("employees", employees.size());
        detail.put("net", total);
        audit(actor, "payroll.calculate", "payroll_periods", periodId, detail);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("count", employees.size());
        result.put("net", total);
        result.put("message", "Đã hoàn tất 6 bước và lưu " + employees.size() + " phiếu lương nháp.");
        if (!managing) {
            result.put("payslip_id", employeePayslipId);
        }
        return result;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> payslipDetail(long id) {
        long actor = access.userId();
        boolean managing = access.can("payroll.manage");
        if (!managing) {
            access.require("payslips.self");
        }
        String sql = "SELECT p.*, e.full_name, pp.code AS period_code, pp.starts_on, pp.ends_on "
                + "FROM v_payslip_totals p JOIN employees e ON e.id = p.employee_id "
                + "JOIN payroll_periods pp ON pp.id = p.period_id WHERE p.id = ? "
                + (managing ? "" : "AND e.user_id = ?");
        List<Map<String, Object>> rows = managing ? jdbc.queryForList(sql, id) : jdbc.queryForList(sql, id, actor);
        if (rows.isEmpty()) {
            throw ApiException.forbidden("Không có quyền xem phiếu lương này.");
        }
        Map<String, Object> payslip = rows.get(0);
        List<Map<String, Object>> checks = jdbc.queryForList(
                "SELECT * FROM employee_payroll_checks WHERE period_id = ? AND employee_id = ? ORDER BY step_number",
                payslip.get("period_id"), payslip.get("employee_id"));
        boolean complete = checks.size() == 6;
        for (int i = 0; complete && i < 6; i++) {
            complete = num(checks.get(i).get("step_number")) == i + 1;
        }
        boolean current = complete && checks.get(5).get("source_hash").equals(sourceHash.compute(
                num(payslip.get("period_id")), num(payslip.get("employee_id")), num(payslip.get("contract_id"))));
        Map<String, Object> result = new LinkedHashMap<>(payslip);
        result.put("items", jdbc.queryForList("SELECT * FROM payslip_items WHERE payslip_id = ? ORDER BY code", id));
        result.put("checks", checks);
        result.put("checks_current", current);
        return result;
    }

    @Transactional
    public void addPayItem(long payslipId, String code, String name, String type, long amount) {
        if (code == null || code.isBlank() || name == null || name.isBlank() || amount < 0
                || !ITEM_TYPES.contains(type)) {
            throw ApiException.badRequest("Khoản điều chỉnh không hợp lệ.");
        }
        access.require("payroll.manage");
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT * FROM payslips WHERE id = ?", payslipId);
        if (rows.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy phiếu lương.");
        }
        Map<String, Object> pay = rows.get(0);
        if (!"draft".equals(pay.get("status"))) {
            throw ApiException.badRequest("Phiếu đã chốt không thể thay đổi.");
        }
        jdbc.update("INSERT INTO payslip_items (payslip_id, code, name, item_type, amount_vnd) VALUES (?, ?, ?, ?, ?) "
                + "ON DUPLICATE KEY UPDATE name = VALUES(name), "
                + "item_type = VALUES(item_type), amount_vnd = VALUES(amount_vnd), note = NULL",
                payslipId, code.trim(), name.trim(), type, amount);
        jdbc.update("DELETE FROM employee_payroll_checks WHERE period_id = ? AND employee_id = ?",
                pay.get("period_id"), pay.get("employee_id"));
        jdbc.update("DELETE FROM payroll_calculation_steps WHERE period_id = ?", pay.get("period_id"));
    }

    /** Approves once all 6 steps are done and the source data still matches the last calculation. */
    @Transactional
    public void approvePayroll(long periodId) {
        long actor = access.userId();
        access.require("payroll.manage");
        List<Map<String, Object>> found = jdbc.queryForList("SELECT * FROM payroll_periods WHERE id = ?", periodId);
        if (found.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy kỳ lương.");
        }
        if (!"calculating".equals(found.get(0).get("status"))) {
            throw ApiException.badRequest("Cần tính lại lương toàn kỳ trước khi duyệt.");
        }
        Integer steps = jdbc.queryForObject(
                "SELECT COUNT(*) FROM payroll_calculation_steps WHERE period_id = ? AND status = 'completed'",
                Integer.class, periodId);
        if (steps == null || steps != 6) {
            throw ApiException.badRequest("Chưa hoàn thành đủ 6 bước.");
        }
        List<Map<String, Object>> pays = jdbc.queryForList("SELECT * FROM payslips WHERE period_id = ?", periodId);
        if (pays.isEmpty()) {
            throw ApiException.badRequest("Kỳ lương chưa có phiếu.");
        }
        Set<Long> active = new HashSet<>(
                jdbc.queryForList("SELECT id FROM employees WHERE status = 'active'", Long.class));
        Set<Long> paid = new HashSet<>();
        pays.forEach(pay -> paid.add(num(pay.get("employee_id"))));
        if (pays.size() != active.size() || !paid.containsAll(active)) {
            throw ApiException.badRequest("Danh sách nhân viên đã đổi. Cần tính lại toàn kỳ.");
        }
        for (Map<String, Object> pay : pays) {
            List<String> check = jdbc.queryForList(
                    "SELECT source_hash FROM employee_payroll_checks WHERE period_id = ? AND employee_id = ? "
                            + "AND step_number = 6", String.class, periodId, pay.get("employee_id"));
            if (check.isEmpty() || !check.get(0).equals(sourceHash.compute(
                    periodId, num(pay.get("employee_id")), num(pay.get("contract_id"))))) {
                throw ApiException.badRequest(
                        "Dữ liệu công/hợp đồng/phiếu lương đã đổi. Cần tính lại toàn kỳ trước khi duyệt.");
            }
        }
        List<Long> recipients = jdbc.queryForList(
                "SELECT e.user_id FROM payslips p JOIN employees e ON e.id = p.employee_id "
                        + "WHERE p.period_id = ? AND e.user_id IS NOT NULL", Long.class, periodId);
        notifier.notify(actor, recipients, "Bảng lương đã được duyệt",
                "Bạn có thể mở mục Thu nhập để xem phiếu lương.", "payroll_periods", periodId);
        jdbc.update("UPDATE payslips SET status = 'approved', approved_by = ?, approved_at = CURRENT_TIMESTAMP "
                + "WHERE period_id = ?", actor, periodId);
        jdbc.update("UPDATE payroll_periods SET status = 'approved', approved_by = ?, "
                + "approved_at = CURRENT_TIMESTAMP WHERE id = ?", actor, periodId);
    }
}
