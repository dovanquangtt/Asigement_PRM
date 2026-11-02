package vn.anhemquan.prm.common;

import java.time.ZoneId;

/**
 * Business time zone (UTC+7, no DST). DATETIME columns hold UTC; in SQL convert to the local calendar day
 * with {@code DATE(CONVERT_TZ(col, '+00:00', '+07:00'))}.
 */
public final class AppTime {

    public static final ZoneId ZONE = ZoneId.of("Asia/Ho_Chi_Minh");

    private AppTime() {
    }
}
