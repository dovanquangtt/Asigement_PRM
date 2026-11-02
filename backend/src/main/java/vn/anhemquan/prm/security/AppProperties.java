package vn.anhemquan.prm.security;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Application settings bound from {@code app.*}.
 *
 * @param jwt    signing settings for the access tokens issued by this API
 * @param google accepted Google OAuth client ids (the Web client id the Flutter app passes as serverClientId)
 */
@ConfigurationProperties(prefix = "app")
public record AppProperties(Jwt jwt, Google google) {

    public AppProperties {
        if (jwt == null) {
            jwt = new Jwt(null, 720);
        }
        if (google == null) {
            google = new Google(List.of());
        }
    }

    public record Jwt(String secret, long ttlMinutes) {
    }

    public record Google(List<String> clientIds) {

        public Google {
            clientIds = clientIds == null ? List.of() : clientIds.stream().filter(id -> !id.isBlank()).toList();
        }
    }
}
