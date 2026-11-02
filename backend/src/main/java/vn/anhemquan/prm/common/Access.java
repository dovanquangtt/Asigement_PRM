package vn.anhemquan.prm.common;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

/**
 * Authenticated-user helper. Permissions are always re-read from the database
 * (never trusted from the token), exactly like the Flutter repository did.
 */
@Component
public class Access {

    static final String NO_PERMISSION = "Tài khoản không có quyền thực hiện thao tác này.";

    private final JdbcTemplate jdbc;

    public Access(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Id of the signed-in user taken from the access token subject. */
    public long userId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof Jwt jwt)) {
            throw ApiException.unauthorized("Phiên đăng nhập không hợp lệ.");
        }
        return Long.parseLong(jwt.getSubject());
    }

    public boolean can(String permission) {
        return can(userId(), permission);
    }

    public boolean can(long userId, String permission) {
        return !jdbc.queryForList(
                "SELECT 1 FROM users u JOIN user_roles ur ON ur.user_id = u.id "
                        + "JOIN role_permissions rp ON rp.role_id = ur.role_id "
                        + "JOIN permissions p ON p.id = rp.permission_id "
                        + "WHERE u.id = ? AND u.is_active AND p.code = ? LIMIT 1",
                userId, permission).isEmpty();
    }

    public void require(String permission) {
        if (!can(permission)) {
            throw ApiException.forbidden(NO_PERMISSION);
        }
    }
}
