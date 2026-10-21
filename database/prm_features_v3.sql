-- SQLite migration v2 -> v3. Run only once on a database with user_version=2.
-- Flutter applies the same migration automatically; do not run manually on v3.
PRAGMA foreign_keys=ON;
BEGIN;
ALTER TABLE employee_devices ADD COLUMN approved_by INTEGER REFERENCES users(id);
ALTER TABLE users ADD COLUMN google_subject TEXT;
CREATE UNIQUE INDEX uq_google_subject ON users(google_subject) WHERE google_subject IS NOT NULL;
CREATE TABLE payroll_policies (
  period_id INTEGER PRIMARY KEY REFERENCES payroll_periods(id),
  overtime_multiplier REAL NOT NULL CHECK(overtime_multiplier>=1),
  created_by INTEGER NOT NULL REFERENCES users(id)
);
CREATE TABLE employee_payroll_checks (
  period_id INTEGER NOT NULL REFERENCES payroll_periods(id),
  employee_id INTEGER NOT NULL REFERENCES employees(id),
  step_number INTEGER NOT NULL CHECK(step_number BETWEEN 1 AND 6),
  name TEXT NOT NULL,
  detail TEXT NOT NULL,
  checked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(period_id,employee_id,step_number)
);
PRAGMA user_version=3;
COMMIT;
