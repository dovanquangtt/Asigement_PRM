package vn.anhemquan.prm.service;

import vn.anhemquan.prm.repository.Db;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Workflow notifications and audit trail. Call inside the caller's
 * {@code @Transactional} method so they commit or roll back with the business change.
 */
@Component
public class Notifier {

    private final JdbcTemplate jdbc;

    public Notifier(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Sends a workflow notification to {@code users}, never to {@code actor}. */
    public void notify(long actor, Collection<Long> users, String title, String body, String entity, long entityId) {
        Set<Long> recipients = new LinkedHashSet<>(users);
        recipients.remove(actor);
        if (recipients.isEmpty()) {
            return;
        }
        Long id = Db.insert(jdbc,
                "INSERT INTO notifications (title, body, notification_type, created_by, related_entity, related_id) "
                        + "VALUES (?, ?, 'workflow', ?, ?, ?)", title, body, actor, entity, entityId);
        for (Long user : recipients) {
            jdbc.update("INSERT INTO notification_recipients (notification_id, user_id) VALUES (?, ?)", id, user);
        }
    }

    /** User ids linked to the given employees (employees without an account are skipped). */
    public List<Long> employeeUsers(Collection<Long> employeeIds) {
        List<Long> result = new ArrayList<>();
        for (Long id : new LinkedHashSet<>(employeeIds)) {
            result.addAll(jdbc.queryForList(
                    "SELECT user_id FROM employees WHERE id = ? AND user_id IS NOT NULL", Long.class, id));
        }
        return result;
    }

    /** Active users holding {@code permission}, minus {@code excluding}. */
    public List<Long> reviewers(String permission, Collection<Long> excluding) {
        return jdbc.queryForList(
                "SELECT DISTINCT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id "
                        + "JOIN role_permissions rp ON rp.role_id = ur.role_id "
                        + "JOIN permissions p ON p.id = rp.permission_id WHERE u.is_active AND p.code = ?",
                Long.class, permission).stream().filter(id -> !excluding.contains(id)).toList();
    }

    public void audit(long actor, String action, String entityType, Long entityId, String beforeJson, String afterJson) {
        jdbc.update(
                "INSERT INTO audit_logs (actor_user_id, action, entity_type, entity_id, before_json, after_json) "
                        + "VALUES (?, ?, ?, ?, ?, ?)",
                actor, action, entityType, entityId, beforeJson, afterJson);
    }
}
