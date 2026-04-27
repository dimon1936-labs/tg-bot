-- =============================================================
-- Migration 005: Fix v_due_reminders
--
-- Bugs у попередній версії:
--   1. EXTRACT(HOUR ...) = 9 — view порожня поза цією хвилиною.
--      Час має контролювати cron у Node-RED, а не view.
--   2. ambiguous "days_before" — PG резолвив r.days_before = days_before
--      як self-reference, дублі могли проходити NOT EXISTS.
-- =============================================================

BEGIN;

CREATE OR REPLACE VIEW v_due_reminders AS
SELECT
    c.id              AS contact_id,
    c.name            AS contact_name,
    c.birthday,
    c.interests,
    c.relationship,
    u.telegram_id     AS owner_id,
    u.timezone        AS tz,
    u.first_name      AS owner_name,
    rd.days_before    AS days_before,
    DATE_PART('year', AGE(c.birthday))::INT + 1 AS turning_age,
    EXTRACT(YEAR FROM (NOW() AT TIME ZONE u.timezone))::INT AS remind_year
FROM contacts c
JOIN users u ON u.telegram_id = c.owner_id
CROSS JOIN LATERAL UNNEST(u.reminder_days_before) AS rd(days_before)
WHERE u.is_active = TRUE
  AND EXTRACT(MONTH FROM c.birthday) = EXTRACT(MONTH FROM ((NOW() AT TIME ZONE u.timezone)::DATE + rd.days_before))
  AND EXTRACT(DAY   FROM c.birthday) = EXTRACT(DAY   FROM ((NOW() AT TIME ZONE u.timezone)::DATE + rd.days_before))
  AND NOT EXISTS (
      SELECT 1 FROM reminders_log r
      WHERE r.contact_id = c.id
        AND r.remind_year = EXTRACT(YEAR FROM (NOW() AT TIME ZONE u.timezone))::INT
        AND r.days_before = rd.days_before
  );

COMMIT;

SELECT * FROM v_due_reminders;
