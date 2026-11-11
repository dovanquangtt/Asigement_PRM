package vn.anhemquan.prm.util;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;

/**
 * Business time zone (UTC+7, no DST). DATETIME columns hold UTC; in SQL convert to the local calendar day
 * with {@code DATE(CONVERT_TZ(col, '+00:00', '+07:00'))}.
 */
public final class AppTime {

    public static final ZoneId ZONE = ZoneId.of("Asia/Ho_Chi_Minh");

    private AppTime() {
    }

    /**
     * Converts a value read from a DATETIME column to an instant. Depending on the driver the JDBC layer returns
     * {@link Timestamp}, {@link LocalDateTime} (stored as UTC) or {@link OffsetDateTime}.
     */
    public static Instant toInstant(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Instant i) {
            return i;
        }
        if (value instanceof Timestamp t) {
            return t.toInstant();
        }
        if (value instanceof LocalDateTime l) {
            return l.toInstant(ZoneOffset.UTC);
        }
        if (value instanceof OffsetDateTime o) {
            return o.toInstant();
        }
        String text = value.toString();
        try {
            return Instant.parse(text);
        } catch (DateTimeParseException e) {
            return LocalDateTime.parse(text.replace(' ', 'T')).toInstant(ZoneOffset.UTC);
        }
    }
}
