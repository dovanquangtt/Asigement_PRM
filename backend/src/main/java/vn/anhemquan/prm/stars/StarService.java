package vn.anhemquan.prm.stars;

import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.common.Access;
import vn.anhemquan.prm.common.ApiException;

@Service
public class StarService {

    private final JdbcTemplate jdbc;
    private final Access access;

    public StarService(JdbcTemplate jdbc, Access access) {
        this.jdbc = jdbc;
        this.access = access;
    }

    public List<Map<String, Object>> stars() {
        boolean managing = access.can("stars.award");
        if (!managing) {
            access.require("stars.self");
        }
        String sql = "SELECT v.* FROM v_employee_stars v JOIN employees e ON e.id = v.employee_id "
                + (managing ? "" : "WHERE e.user_id = ? ") + "ORDER BY total_stars DESC";
        return managing ? jdbc.queryForList(sql) : jdbc.queryForList(sql, access.userId());
    }

    @Transactional
    public void awardStars(long employeeId, int delta, String reason) {
        if (delta == 0 || reason == null || reason.isBlank()) {
            throw ApiException.badRequest("Nhập số sao khác 0 và lý do.");
        }
        access.require("stars.award");
        long actor = access.userId();
        if (!jdbc.queryForList("SELECT 1 FROM employees WHERE id = ? AND user_id = ?", employeeId, actor).isEmpty()) {
            throw ApiException.forbidden("Không thể tự tặng sao.");
        }
        jdbc.update("INSERT INTO star_events (employee_id, stars_delta, reason, awarded_by) VALUES (?, ?, ?, ?)",
                employeeId, delta, reason.trim(), actor);
    }
}
