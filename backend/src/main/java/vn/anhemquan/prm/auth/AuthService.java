package vn.anhemquan.prm.auth;

import vn.anhemquan.prm.common.Db;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.common.ApiException;
import vn.anhemquan.prm.security.AppProperties;

/** Sign-in by password or Google. Roles and permissions always come from the database. */
@Service
public class AuthService {

    public static final String INVALID_CREDENTIALS = "Tên đăng nhập hoặc mật khẩu không đúng.";
    static final String PASSWORD_RULE = "Mật khẩu cần ít nhất 8 ký tự và tối đa 72 byte UTF-8.";

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;
    private final JwtEncoder jwtEncoder;
    private final GoogleTokenVerifier google;
    private final Duration ttl;

    public AuthService(JdbcTemplate jdbc, PasswordEncoder encoder, JwtEncoder jwtEncoder,
            GoogleTokenVerifier google, AppProperties props) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.jwtEncoder = jwtEncoder;
        this.google = google;
        this.ttl = Duration.ofMinutes(props.jwt().ttlMinutes());
    }

    public boolean hasUsers() {
        return !jdbc.queryForList("SELECT id FROM users LIMIT 1").isEmpty();
    }

    public LoginResponse signIn(String username, String password) {
        List<Map<String, Object>> users = jdbc.queryForList(
                "SELECT id, password_hash FROM users WHERE LOWER(username) = LOWER(?) AND is_active",
                username == null ? "" : username.trim());
        if (users.isEmpty() || password == null || password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw ApiException.unauthorized(INVALID_CREDENTIALS);
        }
        Map<String, Object> user = users.get(0);
        if (!encoder.matches(password, (String) user.get("password_hash"))) {
            throw ApiException.unauthorized(INVALID_CREDENTIALS);
        }
        return issue(((Number) user.get("id")).longValue());
    }

    /**
     * Google proves identity only: the e-mail must already be assigned to exactly one active account,
     * and that account is pinned to the Google subject on first use.
     */
    @Transactional
    public LoginResponse signInGoogle(String idToken) {
        if (idToken == null || idToken.isBlank()) {
            throw ApiException.badRequest("Thiếu Google ID token.");
        }
        GoogleIdentity identity = google.verify(idToken);
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, google_subject FROM users WHERE LOWER(TRIM(email)) = ? AND is_active FOR UPDATE",
                identity.email().trim().toLowerCase());
        if (rows.size() != 1) {
            throw ApiException.forbidden(
                    "Gmail chưa được cấp tài khoản duy nhất đang hoạt động. Hãy liên hệ Admin.");
        }
        long userId = ((Number) rows.get(0).get("id")).longValue();
        Object linkedSubject = rows.get(0).get("google_subject");
        if (linkedSubject != null && !linkedSubject.equals(identity.subject())) {
            throw ApiException.forbidden("Liên kết Google không khớp.");
        }
        Integer other = jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE google_subject = ? AND id <> ?",
                Integer.class, identity.subject(), userId);
        if (other != null && other > 0) {
            throw ApiException.conflict("Google đã liên kết với tài khoản khác.");
        }
        LoginResponse response = issue(userId);
        jdbc.update("UPDATE users SET google_subject = ? WHERE id = ?", identity.subject(), userId);
        return response;
    }

    /** Creates the first admin; refused once any account exists. */
    @Transactional
    public void createFirstAdmin(String username, String password) {
        String name = username == null ? "" : username.trim();
        if (name.isEmpty() || name.length() > 100) {
            throw ApiException.badRequest("Tên đăng nhập phải có từ 1 đến 100 ký tự.");
        }
        String hash = hashPassword(password);
        // Row lock on the admin role serialises concurrent bootstrap requests (LOCK TABLES would commit).
        jdbc.queryForList("SELECT id FROM roles WHERE code = 'admin' FOR UPDATE");
        if (hasUsers()) {
            throw ApiException.conflict("Database đã có tài khoản. Hãy đăng nhập bằng tài khoản được cấp.");
        }
        List<Long> roles = jdbc.queryForList("SELECT id FROM roles WHERE code = 'admin'", Long.class);
        if (roles.isEmpty()) {
            throw ApiException.conflict("Database thiếu vai trò admin.");
        }
        Long id = Db.insert(jdbc,
                "INSERT INTO users (username, password_hash) VALUES (?, ?)", name, hash);
        jdbc.update("INSERT INTO user_roles (user_id, role_id) VALUES (?, ?)", id, roles.get(0));
    }

    /** Same password policy as the Flutter app: 8+ characters, at most 72 UTF-8 bytes (bcrypt limit). */
    public String hashPassword(String password) {
        if (password == null || password.length() < 8 || password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw ApiException.badRequest(PASSWORD_RULE);
        }
        return encoder.encode(password);
    }

    public SessionInfo session(long userId) {
        List<Map<String, Object>> users = jdbc.queryForList(
                "SELECT id, username, email FROM users WHERE id = ? AND is_active", userId);
        if (users.isEmpty()) {
            throw ApiException.unauthorized("Phiên đăng nhập không hợp lệ.");
        }
        Map<String, Object> user = users.get(0);
        Set<String> roles = Set.copyOf(jdbc.queryForList(
                "SELECT r.code FROM roles r JOIN user_roles ur ON ur.role_id = r.id WHERE ur.user_id = ?",
                String.class, userId));
        String role = roles.contains("admin") ? "Admin"
                : roles.contains("manager") ? "Quản lý"
                : roles.contains("employee") ? "Nhân viên" : null;
        if (role == null) {
            throw ApiException.forbidden("Tài khoản chưa được cấp vai trò hợp lệ.");
        }
        List<String> permissions = jdbc.queryForList(
                "SELECT DISTINCT p.code FROM permissions p JOIN role_permissions rp ON rp.permission_id = p.id "
                        + "JOIN user_roles ur ON ur.role_id = rp.role_id WHERE ur.user_id = ? ORDER BY p.code",
                String.class, userId);
        List<Map<String, Object>> profiles = jdbc.queryForList(
                "SELECT e.*, d.name AS department_name, b.name AS branch_name, u.email "
                        + "FROM employees e JOIN users u ON u.id = e.user_id "
                        + "JOIN branches b ON b.id = e.branch_id "
                        + "LEFT JOIN departments d ON d.id = e.department_id WHERE e.user_id = ?",
                userId);
        Map<String, Object> profile = profiles.isEmpty()
                ? java.util.Collections.singletonMap("email", user.get("email"))
                : profiles.get(0);
        return new SessionInfo(userId, (String) user.get("username"), role, permissions, profile);
    }

    private LoginResponse issue(long userId) {
        SessionInfo session = session(userId);
        Instant now = Instant.now();
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer("quanlinhansunhahang")
                .subject(Long.toString(userId))
                .issuedAt(now)
                .expiresAt(now.plus(ttl))
                .build();
        String token = jwtEncoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();
        return new LoginResponse(token, "Bearer", ttl.toSeconds(), session);
    }

    public record SessionInfo(long userId, String username, String role, List<String> permissions,
            Map<String, Object> profile) {
    }

    public record LoginResponse(String accessToken, String tokenType, long expiresIn, SessionInfo session) {
    }
}
