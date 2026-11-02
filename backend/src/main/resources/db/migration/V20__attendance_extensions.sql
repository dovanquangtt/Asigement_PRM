-- Attendance columns added by Flutter SQLite migrations v5 (employee submissions) and v6
-- (exceptions, adjustments, overtime approval, day closing). Needed by the attendance module.

ALTER TABLE branches ADD COLUMN require_overtime_approval BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE attendance_events
    ADD COLUMN submitted_by BIGINT,
    ADD FOREIGN KEY (submitted_by) REFERENCES users(id),
    ADD COLUMN actual_device_identifier VARCHAR(255),
    ADD COLUMN selected_device_identifier VARCHAR(255),
    ADD COLUMN device_platform VARCHAR(50),
    ADD COLUMN evidence_collected_at DATETIME(6),
    ADD COLUMN evidence_mocked BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN checks_snapshot TEXT,
    ADD COLUMN reviewed_by BIGINT,
    ADD FOREIGN KEY (reviewed_by) REFERENCES users(id),
    ADD COLUMN reviewed_at DATETIME(6),
    ADD COLUMN review_note TEXT;
ALTER TABLE attendance_events
    ADD COLUMN pending_assignment_id BIGINT AS (CASE WHEN result = 'pending_review' THEN assignment_id END) VIRTUAL;
CREATE UNIQUE INDEX ux_attendance_pending ON attendance_events (pending_assignment_id, event_type);

ALTER TABLE attendance_records
    ADD COLUMN arrival_status VARCHAR(20) CHECK (arrival_status IN ('ON_TIME', 'LATE')),
    ADD COLUMN attendance_state VARCHAR(30) NOT NULL DEFAULT 'IN_PROGRESS',
    ADD COLUMN overtime_requested_minutes INTEGER NOT NULL DEFAULT 0 CHECK (overtime_requested_minutes >= 0),
    ADD COLUMN overtime_status VARCHAR(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    ADD COLUMN overtime_reviewed_by BIGINT,
    ADD FOREIGN KEY (overtime_reviewed_by) REFERENCES users(id),
    ADD COLUMN overtime_reviewed_at DATETIME(6),
    ADD COLUMN overtime_review_note TEXT,
    ADD COLUMN locked_by BIGINT,
    ADD FOREIGN KEY (locked_by) REFERENCES users(id),
    ADD COLUMN locked_at DATETIME(6);

ALTER TABLE attendance_adjustment_requests
    ADD COLUMN before_json TEXT,
    ADD COLUMN evidence_path TEXT;
ALTER TABLE attendance_adjustment_requests
    ADD COLUMN pending_attendance_id BIGINT AS (CASE WHEN status = 'pending' THEN attendance_id END) VIRTUAL;
CREATE UNIQUE INDEX ux_pending_attendance_adjustment ON attendance_adjustment_requests (pending_attendance_id);
