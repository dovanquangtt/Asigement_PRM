-- Employees accept or reject the shifts a manager assigns to them.
-- Existing assignments stay 'accepted' so nothing already scheduled becomes pending.
ALTER TABLE shift_assignments
    ADD COLUMN response_status VARCHAR(20) NOT NULL DEFAULT 'accepted'
        CHECK (response_status IN ('pending', 'accepted', 'rejected')),
    ADD COLUMN responded_at DATETIME(6) NULL,
    ADD COLUMN response_note TEXT NULL;
