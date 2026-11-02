-- Operational tables ported from the Flutter SQLite schema (prm_schema.sql, v3, v4).
-- Timestamps use DATETIME(6), calendar dates use DATE, flags use BOOLEAN.

CREATE TABLE branch_wifi (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    branch_id BIGINT NOT NULL,
    FOREIGN KEY (branch_id) REFERENCES branches(id),
    ssid VARCHAR(200) NOT NULL,
    bssid VARCHAR(64) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (branch_id, bssid)
);

CREATE TABLE employee_devices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    device_identifier VARCHAR(255) NOT NULL UNIQUE,
    platform VARCHAR(50),
    registered_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    revoked_at DATETIME(6),
    approved_by BIGINT,
    FOREIGN KEY (approved_by) REFERENCES users(id)
);

CREATE TABLE contracts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    contract_number VARCHAR(100) NOT NULL UNIQUE,
    contract_type VARCHAR(20) NOT NULL CHECK (contract_type IN ('probation', 'fixed_term', 'indefinite', 'part_time')),
    start_date DATE NOT NULL,
    end_date DATE,
    salary_basis VARCHAR(20) NOT NULL CHECK (salary_basis IN ('monthly', 'hourly')),
    base_salary_vnd BIGINT NOT NULL CHECK (base_salary_vnd >= 0),
    hourly_rate_vnd BIGINT NOT NULL DEFAULT 0 CHECK (hourly_rate_vnd >= 0),
    standard_minutes_per_month INTEGER NOT NULL DEFAULT 12480 CHECK (standard_minutes_per_month > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'expired', 'terminated')),
    document_url TEXT,
    CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE leave_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(160) NOT NULL,
    is_paid BOOLEAN NOT NULL
);

CREATE TABLE shift_templates (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    name VARCHAR(160) NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    ends_next_day BOOLEAN NOT NULL DEFAULT FALSE,
    break_minutes INTEGER NOT NULL DEFAULT 0 CHECK (break_minutes >= 0),
    late_grace_minutes INTEGER NOT NULL DEFAULT 0 CHECK (late_grace_minutes >= 0)
);

CREATE TABLE shifts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    branch_id BIGINT NOT NULL,
    FOREIGN KEY (branch_id) REFERENCES branches(id),
    template_id BIGINT,
    FOREIGN KEY (template_id) REFERENCES shift_templates(id),
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    required_staff INTEGER NOT NULL DEFAULT 1 CHECK (required_staff > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'in_progress', 'closed', 'cancelled')),
    created_by BIGINT NOT NULL,
    FOREIGN KEY (created_by) REFERENCES users(id),
    note TEXT,
    CHECK (ends_at > starts_at)
);

CREATE TABLE shift_assignments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    shift_id BIGINT NOT NULL,
    FOREIGN KEY (shift_id) REFERENCES shifts(id),
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    assigned_by BIGINT NOT NULL,
    FOREIGN KEY (assigned_by) REFERENCES users(id),
    assigned_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    status VARCHAR(20) NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'completed', 'cancelled')),
    UNIQUE (shift_id, employee_id)
);

CREATE TABLE attendance_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    assignment_id BIGINT NOT NULL,
    FOREIGN KEY (assignment_id) REFERENCES shift_assignments(id),
    event_type VARCHAR(20) NOT NULL CHECK (event_type IN ('check_in', 'check_out')),
    occurred_at DATETIME(6) NOT NULL,
    device_id BIGINT,
    FOREIGN KEY (device_id) REFERENCES employee_devices(id),
    latitude DOUBLE PRECISION CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180),
    gps_accuracy_m DOUBLE PRECISION CHECK (gps_accuracy_m >= 0),
    wifi_ssid VARCHAR(200),
    wifi_bssid VARCHAR(64),
    device_valid BOOLEAN NOT NULL,
    gps_valid BOOLEAN NOT NULL,
    wifi_valid BOOLEAN NOT NULL,
    result VARCHAR(20) NOT NULL CHECK (result IN ('accepted', 'rejected', 'pending_review')),
    rejection_reason TEXT,
    confirmed_at DATETIME(6),
    CHECK ((latitude IS NULL) = (longitude IS NULL))
);
-- MySQL has no partial indexes: a generated column is NULL unless the row is accepted, and
-- NULLs never collide in a unique index.
ALTER TABLE attendance_events
    ADD COLUMN accepted_assignment_id BIGINT AS (CASE WHEN result = 'accepted' THEN assignment_id END) VIRTUAL;
CREATE UNIQUE INDEX ux_attendance_accepted ON attendance_events (accepted_assignment_id, event_type);

CREATE TABLE attendance_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    assignment_id BIGINT NOT NULL UNIQUE,
    FOREIGN KEY (assignment_id) REFERENCES shift_assignments(id),
    check_in_at DATETIME(6),
    check_out_at DATETIME(6),
    worked_minutes INTEGER NOT NULL DEFAULT 0 CHECK (worked_minutes >= 0),
    overtime_minutes INTEGER NOT NULL DEFAULT 0 CHECK (overtime_minutes >= 0),
    late_minutes INTEGER NOT NULL DEFAULT 0 CHECK (late_minutes >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'present', 'absent', 'leave', 'adjusted')),
    approved_by BIGINT,
    FOREIGN KEY (approved_by) REFERENCES users(id),
    approved_at DATETIME(6),
    CHECK (check_out_at IS NULL OR (check_in_at IS NOT NULL AND check_out_at >= check_in_at)),
    CHECK (overtime_minutes <= worked_minutes)
);

CREATE TABLE attendance_adjustment_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    attendance_id BIGINT NOT NULL,
    FOREIGN KEY (attendance_id) REFERENCES attendance_records(id),
    requested_by BIGINT NOT NULL,
    FOREIGN KEY (requested_by) REFERENCES users(id),
    requested_check_in DATETIME(6),
    requested_check_out DATETIME(6),
    reason TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    reviewed_by BIGINT,
    FOREIGN KEY (reviewed_by) REFERENCES users(id),
    reviewed_at DATETIME(6),
    review_note TEXT,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CHECK (status NOT IN ('approved', 'rejected') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
    CHECK (requested_check_out IS NULL OR requested_check_in IS NULL OR requested_check_out >= requested_check_in)
);

CREATE TABLE leave_balances (
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    leave_type_id BIGINT NOT NULL,
    FOREIGN KEY (leave_type_id) REFERENCES leave_types(id),
    year INTEGER NOT NULL CHECK (year BETWEEN 2000 AND 2200),
    granted_minutes INTEGER NOT NULL DEFAULT 0 CHECK (granted_minutes >= 0),
    used_minutes INTEGER NOT NULL DEFAULT 0 CHECK (used_minutes >= 0),
    PRIMARY KEY (employee_id, leave_type_id, year)
);

CREATE TABLE leave_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    leave_type_id BIGINT NOT NULL,
    FOREIGN KEY (leave_type_id) REFERENCES leave_types(id),
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    requested_minutes INTEGER NOT NULL CHECK (requested_minutes > 0),
    reason TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    reviewed_by BIGINT,
    FOREIGN KEY (reviewed_by) REFERENCES users(id),
    reviewed_at DATETIME(6),
    review_note TEXT,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CHECK (ends_at > starts_at),
    CHECK (status NOT IN ('approved', 'rejected') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE shift_swap_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    from_assignment_id BIGINT NOT NULL,
    FOREIGN KEY (from_assignment_id) REFERENCES shift_assignments(id),
    to_assignment_id BIGINT NOT NULL,
    FOREIGN KEY (to_assignment_id) REFERENCES shift_assignments(id),
    from_employee_id BIGINT,
    FOREIGN KEY (from_employee_id) REFERENCES employees(id),
    to_employee_id BIGINT,
    FOREIGN KEY (to_employee_id) REFERENCES employees(id),
    requested_by BIGINT NOT NULL,
    FOREIGN KEY (requested_by) REFERENCES users(id),
    reason TEXT NOT NULL,
    counterpart_status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (counterpart_status IN ('pending', 'accepted', 'rejected')),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    reviewed_by BIGINT,
    FOREIGN KEY (reviewed_by) REFERENCES users(id),
    reviewed_at DATETIME(6),
    review_note TEXT,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CHECK (from_assignment_id <> to_assignment_id),
    CHECK (status <> 'approved' OR (counterpart_status = 'accepted' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE payroll_periods (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(80) NOT NULL UNIQUE,
    starts_on DATE NOT NULL,
    ends_on DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'calculating', 'approved', 'paid')),
    approved_by BIGINT,
    FOREIGN KEY (approved_by) REFERENCES users(id),
    approved_at DATETIME(6),
    CHECK (ends_on >= starts_on)
);

CREATE TABLE payroll_policies (
    period_id BIGINT PRIMARY KEY,
    FOREIGN KEY (period_id) REFERENCES payroll_periods(id),
    overtime_multiplier DOUBLE PRECISION NOT NULL CHECK (overtime_multiplier >= 1),
    created_by BIGINT NOT NULL,
    FOREIGN KEY (created_by) REFERENCES users(id)
);

CREATE TABLE payroll_calculation_steps (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    period_id BIGINT NOT NULL,
    FOREIGN KEY (period_id) REFERENCES payroll_periods(id),
    step_number INTEGER NOT NULL CHECK (step_number BETWEEN 1 AND 6),
    name VARCHAR(200) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed')),
    executed_by BIGINT,
    FOREIGN KEY (executed_by) REFERENCES users(id),
    executed_at DATETIME(6),
    detail TEXT,
    UNIQUE (period_id, step_number)
);

CREATE TABLE employee_payroll_checks (
    period_id BIGINT NOT NULL,
    FOREIGN KEY (period_id) REFERENCES payroll_periods(id),
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    step_number INTEGER NOT NULL CHECK (step_number BETWEEN 1 AND 6),
    name VARCHAR(200) NOT NULL,
    detail TEXT NOT NULL,
    checked_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    source_hash VARCHAR(128) NOT NULL DEFAULT '',
    PRIMARY KEY (period_id, employee_id, step_number)
);

CREATE TABLE payslips (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    period_id BIGINT NOT NULL,
    FOREIGN KEY (period_id) REFERENCES payroll_periods(id),
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    contract_id BIGINT NOT NULL,
    FOREIGN KEY (contract_id) REFERENCES contracts(id),
    regular_minutes INTEGER NOT NULL DEFAULT 0 CHECK (regular_minutes >= 0),
    overtime_minutes INTEGER NOT NULL DEFAULT 0 CHECK (overtime_minutes >= 0),
    base_pay_vnd BIGINT NOT NULL DEFAULT 0 CHECK (base_pay_vnd >= 0),
    overtime_pay_vnd BIGINT NOT NULL DEFAULT 0 CHECK (overtime_pay_vnd >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'paid')),
    calculated_at DATETIME(6),
    approved_by BIGINT,
    FOREIGN KEY (approved_by) REFERENCES users(id),
    approved_at DATETIME(6),
    paid_at DATETIME(6),
    UNIQUE (period_id, employee_id),
    CHECK (status = 'draft' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CHECK (status <> 'paid' OR paid_at IS NOT NULL)
);

CREATE TABLE payslip_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    payslip_id BIGINT NOT NULL,
    FOREIGN KEY (payslip_id) REFERENCES payslips(id),
    code VARCHAR(80) NOT NULL,
    name VARCHAR(200) NOT NULL,
    item_type VARCHAR(20) NOT NULL CHECK (item_type IN ('allowance', 'bonus', 'deduction', 'tax', 'insurance')),
    amount_vnd BIGINT NOT NULL CHECK (amount_vnd >= 0),
    note TEXT,
    UNIQUE (payslip_id, code)
);

CREATE TABLE star_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    FOREIGN KEY (employee_id) REFERENCES employees(id),
    assignment_id BIGINT,
    FOREIGN KEY (assignment_id) REFERENCES shift_assignments(id),
    stars_delta INTEGER NOT NULL CHECK (stars_delta <> 0),
    reason TEXT NOT NULL,
    awarded_by BIGINT NOT NULL,
    FOREIGN KEY (awarded_by) REFERENCES users(id),
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);

CREATE TABLE shift_closures (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    assignment_id BIGINT NOT NULL UNIQUE,
    FOREIGN KEY (assignment_id) REFERENCES shift_assignments(id),
    submitted_by BIGINT NOT NULL,
    FOREIGN KEY (submitted_by) REFERENCES users(id),
    note TEXT,
    submitted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    status VARCHAR(20) NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'approved', 'rejected')),
    reviewed_by BIGINT,
    FOREIGN KEY (reviewed_by) REFERENCES users(id),
    reviewed_at DATETIME(6),
    review_note TEXT,
    CHECK (status = 'submitted' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE shift_closure_photos (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    closure_id BIGINT NOT NULL,
    FOREIGN KEY (closure_id) REFERENCES shift_closures(id),
    file_url TEXT NOT NULL,
    captured_at DATETIME(6) NOT NULL,
    caption TEXT
);

CREATE TABLE notifications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    notification_type VARCHAR(40) NOT NULL,
    created_by BIGINT,
    FOREIGN KEY (created_by) REFERENCES users(id),
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    related_entity VARCHAR(80),
    related_id BIGINT
);

CREATE TABLE notification_recipients (
    notification_id BIGINT NOT NULL,
    FOREIGN KEY (notification_id) REFERENCES notifications(id),
    user_id BIGINT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    read_at DATETIME(6),
    PRIMARY KEY (notification_id, user_id)
);

CREATE TABLE audit_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    actor_user_id BIGINT,
    FOREIGN KEY (actor_user_id) REFERENCES users(id),
    action VARCHAR(120) NOT NULL,
    entity_type VARCHAR(80) NOT NULL,
    entity_id BIGINT,
    before_json TEXT,
    after_json TEXT,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);

CREATE INDEX ix_shift_schedule ON shifts (branch_id, starts_at, status);
CREATE INDEX ix_assignment_employee ON shift_assignments (employee_id, status);
CREATE INDEX ix_attendance_events ON attendance_events (assignment_id, occurred_at);
CREATE INDEX ix_leave_employee ON leave_requests (employee_id, starts_at, status);
CREATE INDEX ix_payslip_employee ON payslips (employee_id, period_id);
CREATE INDEX ix_notification_user ON notification_recipients (user_id, read_at);
CREATE INDEX ix_star_employee ON star_events (employee_id, created_at);
CREATE INDEX ix_audit_entity ON audit_logs (entity_type, entity_id, created_at);

CREATE VIEW v_payslip_totals AS
SELECT p.*,
       p.base_pay_vnd + p.overtime_pay_vnd + COALESCE(i.earnings, 0) AS gross_pay_vnd,
       COALESCE(i.deductions, 0) AS deductions_vnd,
       p.base_pay_vnd + p.overtime_pay_vnd + COALESCE(i.earnings, 0) - COALESCE(i.deductions, 0) AS net_pay_vnd
FROM payslips p
LEFT JOIN (
    SELECT payslip_id,
           SUM(CASE WHEN item_type IN ('allowance', 'bonus') THEN amount_vnd ELSE 0 END) AS earnings,
           SUM(CASE WHEN item_type IN ('deduction', 'tax', 'insurance') THEN amount_vnd ELSE 0 END) AS deductions
    FROM payslip_items GROUP BY payslip_id
) i ON i.payslip_id = p.id;

CREATE VIEW v_employee_stars AS
SELECT e.id AS employee_id, e.employee_code, e.full_name, COALESCE(SUM(s.stars_delta), 0) AS total_stars
FROM employees e LEFT JOIN star_events s ON s.employee_id = e.id
GROUP BY e.id, e.employee_code, e.full_name;

CREATE VIEW v_shift_roster AS
SELECT a.id AS assignment_id, s.id AS shift_id, s.branch_id, s.starts_at, s.ends_at,
       e.id AS employee_id, e.employee_code, e.full_name, a.status
FROM shift_assignments a
JOIN shifts s ON s.id = a.shift_id
JOIN employees e ON e.id = a.employee_id;

CREATE VIEW v_attendance_report AS
SELECT r.*, a.employee_id, s.branch_id, s.starts_at AS scheduled_start, s.ends_at AS scheduled_end
FROM attendance_records r
JOIN shift_assignments a ON a.id = r.assignment_id
JOIN shifts s ON s.id = a.shift_id;

CREATE VIEW v_payroll_summary AS
SELECT period_id, COUNT(*) AS employee_count, SUM(gross_pay_vnd) AS gross_pay_vnd,
       SUM(deductions_vnd) AS deductions_vnd, SUM(net_pay_vnd) AS net_pay_vnd
FROM v_payslip_totals GROUP BY period_id;
