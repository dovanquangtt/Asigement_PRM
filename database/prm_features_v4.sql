-- SQLite v3 -> v4; automatically applied by Flutter.
PRAGMA foreign_keys=ON;
BEGIN;
ALTER TABLE shift_swap_requests ADD COLUMN from_employee_id INTEGER REFERENCES employees(id);
ALTER TABLE shift_swap_requests ADD COLUMN to_employee_id INTEGER REFERENCES employees(id);
UPDATE shift_swap_requests SET from_employee_id=(SELECT employee_id FROM shift_assignments WHERE id=from_assignment_id),to_employee_id=(SELECT employee_id FROM shift_assignments WHERE id=to_assignment_id);
ALTER TABLE employee_payroll_checks ADD COLUMN source_hash TEXT NOT NULL DEFAULT '';
PRAGMA user_version=4;
COMMIT;
