package vn.anhemquan.prm.repository;

import static vn.anhemquan.prm.service.AttendanceSupport.flag;
import static vn.anhemquan.prm.service.AttendanceSupport.instant;

import com.fasterxml.jackson.core.type.TypeReference;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import vn.anhemquan.prm.dto.AppDto.AttendanceInfo;
import vn.anhemquan.prm.dto.AppDto.BriefVerification;
import vn.anhemquan.prm.dto.AppDto.Employee;
import vn.anhemquan.prm.dto.AppDto.EventInfo;
import vn.anhemquan.prm.dto.AppDto.HistoryItem;
import vn.anhemquan.prm.dto.AppDto.ShiftRef;
import vn.anhemquan.prm.dto.AppDto.Verification;
import vn.anhemquan.prm.service.AttendanceSheetService;
import vn.anhemquan.prm.util.AppTime;

/** One-row-per-assignment query plus the mapping of rows/events to the contract DTOs. */
@Component
public class AppRows {

    /** Attendance row of one shift assignment (record, pending counters, branch geofence). */
    public static final String ROW_SQL = "SELECT a.id AS assignment_id, a.response_status, a.response_note, e.id AS employee_id, e.user_id, e.full_name, "
            + "e.employee_code, p.name AS position_name, s.id AS shift_id, s.branch_id, b.name AS branch_name, "
            + "b.latitude AS branch_lat, b.longitude AS branch_lon, b.geofence_radius_m AS branch_radius, "
            + "s.starts_at, s.ends_at, COALESCE(t.break_minutes, 0) AS break_minutes, r.id AS record_id, "
            + "r.check_in_at, r.check_out_at, COALESCE(r.worked_minutes, 0) AS worked_minutes, "
            + "COALESCE(r.late_minutes, 0) AS late_minutes, COALESCE(r.overtime_minutes, 0) AS overtime_minutes, "
            + "r.arrival_status, r.attendance_state, r.overtime_status, r.locked_at, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
            + "AND ev.result = 'pending_review') AS pending_events, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
            + "AND ev.result = 'pending_review' AND ev.event_type = 'check_in') AS pending_in, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
            + "AND ev.result = 'pending_review' AND ev.event_type = 'check_out') AS pending_out, "
            + "(SELECT COUNT(*) FROM attendance_events ev WHERE ev.assignment_id = a.id "
            + "AND ev.result = 'rejected') AS rejected_events, "
            + "(SELECT COUNT(*) FROM attendance_adjustment_requests q WHERE q.attendance_id = r.id "
            + "AND q.status = 'pending') AS pending_adjustments, "
            + "(SELECT ev.id FROM attendance_events ev WHERE ev.assignment_id = a.id ORDER BY ev.id DESC LIMIT 1) "
            + "AS last_event_id "
            + "FROM shift_assignments a JOIN shifts s ON s.id = a.shift_id JOIN employees e ON e.id = a.employee_id "
            + "LEFT JOIN positions p ON p.id = e.position_id JOIN branches b ON b.id = s.branch_id "
            + "LEFT JOIN shift_templates t ON t.id = s.template_id "
            + "LEFT JOIN attendance_records r ON r.assignment_id = a.id ";

    /** Local (UTC+7) calendar day of a shift start, for filters. */
    public static final String SHIFT_DAY = "DATE(CONVERT_TZ(s.starts_at, '+00:00', '+07:00'))";

    private final JdbcTemplate jdbc;
    private final com.fasterxml.jackson.databind.ObjectMapper json;

    public AppRows(JdbcTemplate jdbc, com.fasterxml.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    /** {@code where} and optional order/limit are appended after the base query. */
    public List<Map<String, Object>> rows(String whereAndOrder, Object... args) {
        return jdbc.queryForList(ROW_SQL + "WHERE " + whereAndOrder, args);
    }

    // ---- value helpers -------------------------------------------------------------------------

    public static long num(Object value) {
        return value == null ? 0 : ((Number) value).longValue();
    }

    public static String str(Object value) {
        return value == null ? null : value.toString();
    }

    public static LocalDate localDate(Object instantValue) {
        return instant(instantValue).atZone(AppTime.ZONE).toLocalDate();
    }

    // ---- row -> dto ----------------------------------------------------------------------------

    public Employee employee(Map<String, Object> r) {
        return new Employee(num(r.get("employee_id")), str(r.get("employee_code")), str(r.get("full_name")),
                str(r.get("position_name")), num(r.get("branch_id")), str(r.get("branch_name")), null);
    }

    public ShiftRef shift(Map<String, Object> r) {
        return new ShiftRef(num(r.get("assignment_id")), num(r.get("shift_id")), instant(r.get("starts_at")),
                instant(r.get("ends_at")), num(r.get("branch_id")), str(r.get("branch_name")));
    }

    public String status(Map<String, Object> r, Instant now) {
        return AttendanceSheetService.sheetStatus(r, now);
    }

    /** NO_SHIFT is decided by the caller; this is the state of an existing assignment. */
    public String state(Map<String, Object> r) {
        boolean in = r.get("check_in_at") != null;
        boolean out = r.get("check_out_at") != null;
        if (isVoided(r)) {
            return "NOT_CHECKED_IN";
        }
        if ((num(r.get("pending_in")) > 0 && !in) || (num(r.get("pending_out")) > 0 && !out)) {
            return "ATTENDANCE_EXCEPTION";
        }
        return in && out ? "COMPLETED" : in ? "WORKING" : "NOT_CHECKED_IN";
    }

    public static boolean isVoided(Map<String, Object> r) {
        return "VOIDED".equals(r.get("attendance_state"));
    }

    public AttendanceInfo attendance(Map<String, Object> r, Instant now) {
        return new AttendanceInfo(instant(r.get("check_in_at")), instant(r.get("check_out_at")), status(r, now),
                str(r.get("arrival_status")), num(r.get("late_minutes")), num(r.get("worked_minutes")),
                num(r.get("break_minutes")), num(r.get("overtime_minutes")));
    }

    public HistoryItem historyItem(Map<String, Object> r, Instant now) {
        return new HistoryItem(num(r.get("assignment_id")), localDate(r.get("starts_at")), shift(r),
                instant(r.get("check_in_at")), instant(r.get("check_out_at")), status(r, now),
                num(r.get("late_minutes")) > 0, num(r.get("late_minutes")), num(r.get("worked_minutes")));
    }

    public BriefVerification brief(Verification v) {
        return new BriefVerification(v.gps(), v.device());
    }

    // ---- events / verification -----------------------------------------------------------------

    public Map<Long, Map<String, Object>> events(Collection<Long> ids) {
        Map<Long, Map<String, Object>> byId = new HashMap<>();
        if (ids.isEmpty()) {
            return byId;
        }
        String marks = String.join(",", Collections.nCopies(ids.size(), "?"));
        for (Map<String, Object> e : jdbc.queryForList(
                "SELECT * FROM attendance_events WHERE id IN (" + marks + ")", ids.toArray())) {
            byId.put(num(e.get("id")), e);
        }
        return byId;
    }

    public List<Map<String, Object>> eventsOf(long assignmentId) {
        return jdbc.queryForList("SELECT * FROM attendance_events WHERE assignment_id = ? ORDER BY id",
                assignmentId);
    }

    /** Verification of one stored event; {@code row} supplies the branch geofence. No event -> all UNKNOWN. */
    public Verification verification(Map<String, Object> event, Map<String, Object> row) {
        if (event == null) {
            return new Verification("UNKNOWN", "UNKNOWN", "UNKNOWN", null, null, List.of());
        }
        String gps = flag(event.get("gps_valid")) ? "VERIFIED" : event.get("latitude") == null ? "UNKNOWN" : "FAILED";
        String device = flag(event.get("device_valid")) ? "VERIFIED" : "FAILED";
        String wifi = flag(event.get("wifi_valid")) ? "VERIFIED" : event.get("wifi_bssid") == null ? "UNKNOWN"
                : "FAILED";
        Map<String, Object> snapshot = snapshot(event);
        Double distance = snapshot.get("distance_m") instanceof Number n ? n.doubleValue() : null;
        if (distance == null) {
            distance = distanceOf(event, row);
        }
        Integer radius = snapshot.get("radius_m") instanceof Number n ? Integer.valueOf(n.intValue())
                : row.get("branch_radius") == null ? null : Integer.valueOf((int) num(row.get("branch_radius")));
        return new Verification(gps, device, wifi, distance == null ? null : Math.round(distance * 10) / 10.0,
                radius, warnings(event, snapshot));
    }

    private Double distanceOf(Map<String, Object> event, Map<String, Object> row) {
        if (event.get("latitude") == null || event.get("longitude") == null || row.get("branch_lat") == null
                || row.get("branch_lon") == null) {
            return null;
        }
        return haversine(((Number) row.get("branch_lat")).doubleValue(), ((Number) row.get("branch_lon")).doubleValue(),
                ((Number) event.get("latitude")).doubleValue(), ((Number) event.get("longitude")).doubleValue());
    }

    /** Great-circle distance in metres. */
    public static double haversine(double lat1, double lon1, double lat2, double lon2) {
        double p1 = Math.toRadians(lat1);
        double p2 = Math.toRadians(lat2);
        double dp = p2 - p1;
        double dl = Math.toRadians(lon2 - lon1);
        double a = Math.pow(Math.sin(dp / 2), 2) + Math.cos(p1) * Math.cos(p2) * Math.pow(Math.sin(dl / 2), 2);
        return 6371000 * 2 * Math.atan2(Math.sqrt(Math.min(1, Math.max(0, a))),
                Math.sqrt(Math.min(1, Math.max(0, 1 - a))));
    }

    private Map<String, Object> snapshot(Map<String, Object> event) {
        Object raw = event.get("checks_snapshot");
        if (raw == null) {
            return Map.of();
        }
        try {
            return json.readValue(raw.toString(), new TypeReference<Map<String, Object>>() { });
        } catch (Exception e) {
            return Map.of();
        }
    }

    @SuppressWarnings("unchecked")
    public List<String> warnings(Map<String, Object> event, Map<String, Object> snapshot) {
        if (snapshot.get("warnings") instanceof List<?> list) {
            return new ArrayList<>((List<String>) list);
        }
        Object reason = event.get("rejection_reason");
        return reason == null || reason.toString().isBlank() ? List.of() : List.of(reason.toString().split("; "));
    }

    public List<String> warnings(Map<String, Object> event) {
        return warnings(event, snapshot(event));
    }

    public static String resultOf(Object dbResult) {
        return switch (String.valueOf(dbResult)) {
            case "accepted" -> "ACCEPTED";
            case "pending_review" -> "PENDING_REVIEW";
            default -> "REJECTED";
        };
    }

    public EventInfo eventInfo(Map<String, Object> event, Map<String, Object> row) {
        Verification v = verification(event, row);
        return new EventInfo(num(event.get("id")), "check_in".equals(event.get("event_type")) ? "CHECK_IN"
                : "CHECK_OUT", instant(event.get("occurred_at")), resultOf(event.get("result")),
                event.get("latitude") == null ? null : ((Number) event.get("latitude")).doubleValue(),
                event.get("longitude") == null ? null : ((Number) event.get("longitude")).doubleValue(),
                event.get("gps_accuracy_m") == null ? null : ((Number) event.get("gps_accuracy_m")).doubleValue(),
                v.distanceMeters(), v, str(event.get("rejection_reason")));
    }

    /** Human readable reasons: warnings of pending events, rejection reasons, pending adjustment/overtime. */
    public List<String> exceptionsOf(Map<String, Object> row, List<Map<String, Object>> events) {
        List<String> result = new ArrayList<>();
        for (Map<String, Object> e : events) {
            if ("pending_review".equals(e.get("result"))) {
                List<String> w = warnings(e);
                result.add((("check_in".equals(e.get("event_type")) ? "Vào ca: " : "Ra ca: ")
                        + (w.isEmpty() ? "chờ quản lý xác minh" : String.join("; ", w))));
            } else if ("rejected".equals(e.get("result")) && e.get("rejection_reason") != null) {
                result.add("Bị từ chối: " + e.get("rejection_reason"));
            }
        }
        if (num(row.get("pending_adjustments")) > 0) {
            result.add("Có yêu cầu điều chỉnh công đang chờ duyệt");
        }
        if ("PENDING".equals(row.get("overtime_status"))) {
            result.add("Tăng ca chờ xác nhận");
        }
        return result;
    }
}
