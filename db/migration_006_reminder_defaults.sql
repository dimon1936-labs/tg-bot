-- =============================================================
-- Migration 006: Align default reminder stages with product copy
-- =============================================================

BEGIN;

ALTER TABLE users
    ALTER COLUMN reminder_days_before SET DEFAULT ARRAY[7,3,1,0];

UPDATE users
SET reminder_days_before = ARRAY[7,3,1,0]
WHERE reminder_days_before = ARRAY[7,1,0];

COMMIT;

SELECT telegram_id, reminder_days_before
FROM users
ORDER BY telegram_id;
