package vn.anhemquan.prm.app;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/** JSON shapes of backend/docs/api-app-contract.md (camelCase). */
public final class AppDto {

    private AppDto() {
    }

    public record Employee(long id, String employeeCode, String fullName, String position, long branchId,
            String branchName, String avatarUrl) {
    }

    public record ShiftRef(long assignmentId, long shiftId, Instant startsAt, Instant endsAt, long branchId,
            String branchName) {
    }

    /** {@link ShiftRef} plus the sheet status, for GET /api/employees/me/shifts. */
    public record MyShift(long assignmentId, long shiftId, Instant startsAt, Instant endsAt, long branchId,
            String branchName, String status, String responseStatus, String responseNote) {
    }

    public record BranchRef(long id, String name) {
    }

    public record Verification(String gps, String device, String wifi, Double distanceMeters, Integer radiusMeters,
            List<String> warnings) {
    }

    public record AttendanceInfo(Instant checkInAt, Instant checkOutAt, String status, String arrivalStatus,
            long lateMinutes, long workedMinutes, long breakMinutes, long overtimeMinutes) {
    }

    public record PendingException(String eventType, String message) {
    }

    public record Today(LocalDate date, Instant serverTime, Employee employee, String state, ShiftRef shift,
            List<ShiftRef> shifts, AttendanceInfo attendance, Verification verification,
            List<PendingException> pendingExceptions, boolean canCheckIn, boolean canCheckOut) {
    }

    public record PunchRequest(Long assignmentId, @NotBlank String deviceIdentifier, String devicePlatform,
            String deviceModel, @NotNull Double latitude, @NotNull Double longitude, Double accuracyMeters,
            @NotNull Instant locationCollectedAt, Boolean mockLocation, String wifiSsid, String wifiBssid) {
    }

    public record ActionResponse(long attendanceId, long eventId, String type, String result, Instant serverTime,
            Employee employee, BranchRef branch, ShiftRef shift, Verification verification,
            AttendanceInfo attendance, String status, String message) {
    }

    public record HistoryItem(long attendanceId, LocalDate date, ShiftRef shift, Instant checkInAt,
            Instant checkOutAt, String status, boolean late, long lateMinutes, long workedMinutes) {
    }

    public record EventInfo(long eventId, String type, Instant occurredAt, String result, Double latitude,
            Double longitude, Double accuracyMeters, Double distanceMeters, Verification verification,
            String rejectionReason) {
    }

    public record Detail(HistoryItem item, Employee employee, Verification verification, List<EventInfo> events,
            List<String> exceptions) {
    }

    public record AuditEntry(String action, String actorName, Instant at, String detail) {
    }

    public record ReviewDetail(HistoryItem item, Employee employee, ShiftRef shift, AttendanceInfo attendance,
            Verification verification, List<EventInfo> events, List<String> exceptions,
            List<AuditEntry> auditLog) {
    }

    public record BriefVerification(String gps, String device) {
    }

    public record ListItem(long attendanceId, Employee employee, ShiftRef shift, Instant checkInAt,
            Instant checkOutAt, String status, boolean late, long lateMinutes, long workedMinutes,
            BriefVerification verification) {
    }

    public record ExceptionItem(long attendanceId, Employee employee, ShiftRef shift, Instant checkInAt,
            Instant checkOutAt, String status, boolean late, long lateMinutes, long workedMinutes,
            BriefVerification verification, String reason) {
    }

    public record ManagerSummary(LocalDate date, Long branchId, long totalEmployees, long checkedIn, long working,
            long completed, long late, long notCheckedIn, long exceptions) {
    }

    public record AdminSummary(LocalDate date, Long branchId, long totalEmployees, long checkedIn, long working,
            long completed, long late, long notCheckedIn, long exceptions, long totalBranches, long totalShifts) {
    }

    public record DeviceItem(long id, long employeeId, String employeeName, String employeeCode,
            String deviceIdentifierMasked, String platform, Instant registeredAt, String status,
            String approvedByName, Instant revokedAt) {
    }

    public record RevokeRequest(String reason) {
    }

    public record ReportRow(String key, String label, long totalShifts, long success, long late, long missing,
            long exceptions, long voided, long workedMinutes) {
    }

    public record Report(String groupBy, LocalDate from, LocalDate to, List<ReportRow> rows) {
    }

    public record Page<T>(List<T> items, int page, int size, long totalItems, int totalPages) {

        public static <T> Page<T> of(List<T> all, int page, int size) {
            int s = size <= 0 ? 20 : Math.min(size, 100);
            int p = Math.max(page, 0);
            int from = (int) Math.min((long) p * s, all.size());
            int to = Math.min(from + s, all.size());
            return new Page<>(List.copyOf(all.subList(from, to)), p, s, all.size(),
                    (int) Math.ceil(all.size() / (double) s));
        }
    }
}
