package vn.anhemquan.prm.service;

import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import vn.anhemquan.prm.security.Access;

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
}
