package vn.anhemquan.prm.service;

import vn.anhemquan.prm.repository.Db;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.anhemquan.prm.security.Access;
import vn.anhemquan.prm.exception.ApiException;

/** Shift closure reports (note + photo) and their review (ported from Flutter M07). */
@Service
public class ClosureService {

    private final JdbcTemplate jdbc;
    private final Access access;
    private final Notifier notifier;

    public ClosureService(JdbcTemplate jdbc, Access access, Notifier notifier) {
        this.jdbc = jdbc;
        this.access = access;
        this.notifier = notifier;
    }

    public List<Map<String, Object>> closures() {
        boolean managing = access.can("closures.review");
        if (!managing) {
            access.require("closures.self");
        }
        String sql = "SELECT c.*, e.full_name FROM shift_closures c JOIN shift_assignments a ON a.id = c.assignment_id "
                + "JOIN employees e ON e.id = a.employee_id " + (managing ? "" : "WHERE e.user_id = ? ")
                + "ORDER BY c.id DESC";
        List<Map<String, Object>> rows = managing ? jdbc.queryForList(sql) : jdbc.queryForList(sql, access.userId());
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> copy = new LinkedHashMap<>(row);
            copy.put("photos", jdbc.queryForList("SELECT * FROM shift_closure_photos WHERE closure_id = ?",
                    row.get("id")));
            result.add(copy);
        }
        return result;
    }

    /**
     * Only the assignee who already checked out may submit; a rejected report can be resubmitted.
     * {@code photoUrl} is a URL/path string (the server does not read local files).
     */
    @Transactional
    public long closeAssignment(long assignmentId, String note, String photoUrl) {
        if (note == null || note.isBlank() || photoUrl == null || photoUrl.isBlank()) {
            throw ApiException.badRequest("Cần ghi chú và ảnh chụp đóng ca.");
        }
        access.require("closures.self");
        long actor = access.userId();
        access.require("profile.self");
        List<Map<String, Object>> me = jdbc.queryForList(
                "SELECT id FROM employees WHERE user_id = ? AND status = 'active'", actor);
        if (me.isEmpty()) {
            throw ApiException.forbidden("Tài khoản chưa được liên kết hồ sơ nhân viên đang làm việc.");
        }
        List<Map<String, Object>> own = jdbc.queryForList(
                "SELECT a.* FROM shift_assignments a WHERE a.id = ? AND a.employee_id = ?",
                assignmentId, me.get(0).get("id"));
        if (own.isEmpty()) {
            throw ApiException.forbidden("Phân ca không thuộc bạn.");
        }
        if (!"assigned".equals(own.get(0).get("status"))) {
            throw ApiException.badRequest("Phân ca không còn hiệu lực.");
        }
        if (jdbc.queryForList("SELECT 1 FROM attendance_records WHERE assignment_id = ? AND check_out_at IS NOT NULL",
                assignmentId).isEmpty()) {
            throw ApiException.badRequest(closureBlocker(assignmentId));
        }
        List<Map<String, Object>> previous = jdbc.queryForList(
                "SELECT * FROM shift_closures WHERE assignment_id = ?", assignmentId);
        if (!previous.isEmpty() && !"rejected".equals(previous.get(0).get("status"))) {
            throw ApiException.conflict("Đã gửi báo cáo đóng ca.");
        }
        long id;
        if (previous.isEmpty()) {
            id = Db.insert(jdbc,"INSERT INTO shift_closures (assignment_id, submitted_by, note, status, "
                    + "submitted_at) VALUES (?, ?, ?, 'submitted', CURRENT_TIMESTAMP)", assignmentId, actor, note.trim());
        } else {
            id = ((Number) previous.get(0).get("id")).longValue();
            jdbc.update("UPDATE shift_closures SET submitted_by = ?, note = ?, status = 'submitted', "
                    + "submitted_at = CURRENT_TIMESTAMP, reviewed_by = NULL, reviewed_at = NULL, review_note = NULL "
                    + "WHERE id = ?", actor, note.trim(), id);
        }
        jdbc.update("INSERT INTO shift_closure_photos (closure_id, file_url, captured_at) "
                + "VALUES (?, ?, CURRENT_TIMESTAMP)", id, photoUrl.trim());
        return id;
    }

    /** Why the assignment cannot be closed yet, phrased for the employee. */
    private String closureBlocker(long assignmentId) {
        boolean hasIn = !jdbc.queryForList(
                "SELECT 1 FROM attendance_records WHERE assignment_id = ? AND check_in_at IS NOT NULL",
                assignmentId).isEmpty();
        if (!hasIn && eventExists(assignmentId, "check_in", "pending_review")) {
            return "Lượt vào ca đang chờ quản lý duyệt. Hãy chờ được duyệt, sau đó điểm danh ra ca.";
        }
        if (eventExists(assignmentId, "check_out", "pending_review")) {
            return "Lượt ra ca đang chờ quản lý duyệt. Hãy chờ được duyệt rồi gửi báo cáo đóng ca.";
        }
        if (hasIn && eventExists(assignmentId, "check_out", "rejected")) {
            return "Lượt ra ca đã bị từ chối. Hãy điểm danh ra ca lại trước khi đóng ca.";
        }
        return "Cần điểm danh ra ca trước khi đóng ca.";
    }

    private boolean eventExists(long assignmentId, String type, String result) {
        return !jdbc.queryForList("SELECT 1 FROM attendance_events WHERE assignment_id = ? AND event_type = ? "
                + "AND result = ? LIMIT 1", assignmentId, type, result).isEmpty();
    }

    /** Reviews one report; a shared shift closes only once no assignment is left unfinished. */
    @Transactional
    public void reviewClosure(long id, boolean approve) {
        access.require("closures.review");
        long actor = access.userId();
        List<Map<String, Object>> found = jdbc.queryForList("SELECT * FROM shift_closures WHERE id = ?", id);
        if (found.isEmpty()) {
            throw ApiException.notFound("Không tìm thấy báo cáo đóng ca.");
        }
        Map<String, Object> c = found.get(0);
        long submittedBy = ((Number) c.get("submitted_by")).longValue();
        if (submittedBy == actor || !"submitted".equals(c.get("status"))) {
            throw ApiException.badRequest("Không thể tự duyệt hoặc duyệt lại.");
        }
        if (approve && jdbc.queryForList("SELECT 1 FROM shift_closure_photos WHERE closure_id = ?", id).isEmpty()) {
            throw ApiException.badRequest("Báo cáo chưa có ảnh.");
        }
        jdbc.update("UPDATE shift_closures SET status = ?, reviewed_by = ?, reviewed_at = CURRENT_TIMESTAMP "
                + "WHERE id = ?", approve ? "approved" : "rejected", actor, id);
        if (approve) {
            jdbc.update("UPDATE shift_assignments SET status = 'completed' WHERE id = ?", c.get("assignment_id"));
            Object shiftId = jdbc.queryForMap("SELECT shift_id FROM shift_assignments WHERE id = ?",
                    c.get("assignment_id")).get("shift_id");
            if (jdbc.queryForList("SELECT 1 FROM shift_assignments WHERE shift_id = ? AND status = 'assigned'",
                    shiftId).isEmpty()) {
                jdbc.update("UPDATE shifts SET status = 'closed' WHERE id = ?", shiftId);
            }
        }
        notifier.notify(actor, List.of(submittedBy), "Kết quả báo cáo đóng ca",
                approve ? "Báo cáo đóng ca đã được duyệt."
                        : "Báo cáo bị từ chối. Bạn có thể bổ sung và gửi lại.",
                "shift_closures", id);
    }
}
