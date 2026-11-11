package vn.anhemquan.prm.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import vn.anhemquan.prm.util.AppTime;

/**
 * SHA-256 over the data a payslip was calculated from (period, policy, contracts, valid attendance,
 * adjustment items, computed amounts). Used to block approving results that went stale.
 * Self-consistent within this app only: it does not match the Flutter hash byte for byte.
 */
@Component
public class PayrollSourceHash {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper = new ObjectMapper();

    public PayrollSourceHash(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public String compute(long periodId, long employeeId, long contractId) {
        Map<String, Object> period = jdbc.queryForMap("SELECT * FROM payroll_periods WHERE id = ?", periodId);
        List<Object> parts = new ArrayList<>();
        parts.add(canonical(period.get("starts_on")));
        parts.add(canonical(period.get("ends_on")));
        parts.add(rows("SELECT * FROM payroll_policies WHERE period_id = ?", periodId));
        parts.add(rows("SELECT * FROM contracts WHERE employee_id = ? OR id = ? ORDER BY id", employeeId, contractId));
        parts.add(rows("SELECT r.*, a.employee_id, s.starts_at, s.ends_at FROM attendance_records r "
                + "JOIN shift_assignments a ON a.id = r.assignment_id JOIN shifts s ON s.id = a.shift_id "
                + "WHERE a.employee_id = ? AND r.status IN ('present', 'adjusted') AND r.check_out_at IS NOT NULL "
                + "AND DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00')) BETWEEN ? AND ? ORDER BY r.id",
                employeeId, period.get("starts_on"), period.get("ends_on")));
        parts.add(rows("SELECT i.code, i.name, i.item_type, i.amount_vnd FROM payslip_items i "
                + "JOIN payslips ps ON ps.id = i.payslip_id WHERE ps.employee_id = ? AND ps.period_id = ? "
                + "ORDER BY i.code", employeeId, periodId));
        parts.add(rows("SELECT base_pay_vnd, overtime_pay_vnd, regular_minutes, overtime_minutes FROM payslips "
                + "WHERE period_id = ? AND employee_id = ?", periodId, employeeId));
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(mapper.writeValueAsString(parts).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException | JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private List<Object> rows(String sql, Object... args) {
        List<Object> result = new ArrayList<>();
        for (Map<String, Object> row : jdbc.queryForList(sql, args)) {
            Map<String, Object> sorted = new TreeMap<>();
            row.forEach((k, v) -> sorted.put(k, canonical(v)));
            result.add(sorted);
        }
        return result;
    }

    private static Object canonical(Object value) {
        if (value == null || value instanceof Number || value instanceof Boolean || value instanceof String) {
            return value;
        }
        if (value instanceof java.sql.Timestamp ts) {
            return ts.toInstant().toString();
        }
        return value.toString();
    }
}
