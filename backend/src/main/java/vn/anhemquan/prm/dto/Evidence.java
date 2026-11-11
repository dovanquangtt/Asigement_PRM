package vn.anhemquan.prm.dto;

import jakarta.validation.constraints.NotNull;
import java.time.Instant;

/**
 * Sensor snapshot sent by the app (port of AttendanceEvidence). Contains no "accepted" flag:
 * the server decides by comparing against registered devices, branch GPS and Wi-Fi.
 */
public record Evidence(
        String deviceIdentifier,
        String platform,
        @NotNull Instant collectedAt,
        Double latitude,
        Double longitude,
        Double accuracy,
        String ssid,
        String bssid,
        Boolean mocked) {

    public boolean isMocked() {
        return Boolean.TRUE.equals(mocked);
    }
}
