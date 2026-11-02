package vn.anhemquan.prm.auth;

import java.util.List;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Component;
import vn.anhemquan.prm.common.ApiException;
import vn.anhemquan.prm.security.AppProperties;

/**
 * Validates Google ID tokens against Google's public keys: signature, expiry, issuer and audience
 * (must be one of {@code app.google.client-ids}), and requires a verified e-mail.
 */
@Component
public class NimbusGoogleTokenVerifier implements GoogleTokenVerifier {

    static final String JWKS_URI = "https://www.googleapis.com/oauth2/v3/certs";
    private static final Set<String> ISSUERS = Set.of("https://accounts.google.com", "accounts.google.com");

    private final List<String> clientIds;
    private final NimbusJwtDecoder decoder;

    public NimbusGoogleTokenVerifier(AppProperties props) {
        this.clientIds = props.google().clientIds();
        this.decoder = NimbusJwtDecoder.withJwkSetUri(JWKS_URI).build();
        OAuth2TokenValidator<Jwt> claims = jwt -> {
            if (!ISSUERS.contains(jwt.getIssuer() == null ? "" : jwt.getIssuer().toString())) {
                return OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "issuer", null));
            }
            if (jwt.getAudience().stream().noneMatch(clientIds::contains)) {
                return OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "audience", null));
            }
            return OAuth2TokenValidatorResult.success();
        };
        this.decoder.setJwtValidator(token -> {
            OAuth2TokenValidatorResult time = new JwtTimestampValidator().validate(token);
            return time.hasErrors() ? time : claims.validate(token);
        });
    }

    @Override
    public GoogleIdentity verify(String idToken) {
        if (clientIds.isEmpty()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Chưa cấu hình Google OAuth trên máy chủ (GOOGLE_CLIENT_IDS).");
        }
        Jwt jwt;
        try {
            jwt = decoder.decode(idToken);
        } catch (JwtException e) {
            throw ApiException.unauthorized("Google ID token không hợp lệ hoặc đã hết hạn.");
        }
        String email = jwt.getClaimAsString("email");
        if (email == null || email.isBlank() || !Boolean.TRUE.equals(jwt.getClaim("email_verified"))
                || jwt.getSubject() == null || jwt.getSubject().isBlank()) {
            throw ApiException.unauthorized("Gmail chưa được Google xác minh.");
        }
        return new GoogleIdentity(jwt.getSubject(), email);
    }
}
