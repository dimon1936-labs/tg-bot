-- =============================================================
-- Migration 001: Gift AI + Smart Reminders
--
-- Застосувати вручну після першого запуску:
--   docker exec -i birthday-bot-db psql -U postgres -d birthday_bot \
--     < db/migration_001_gifts.sql
-- =============================================================

BEGIN;

-- 1. Contacts: додаємо interests та relationship для AI context
ALTER TABLE contacts
    ADD COLUMN IF NOT EXISTS interests TEXT,
    ADD COLUMN IF NOT EXISTS relationship VARCHAR(30);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contacts_relationship_valid') THEN
        ALTER TABLE contacts
            ADD CONSTRAINT contacts_relationship_valid
            CHECK (relationship IS NULL OR relationship IN (
                'family', 'friend', 'colleague', 'partner', 'other'
            ));
    END IF;
END $$;

-- 2. Users: додаємо персональні налаштування lead-time нагадувань
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS reminder_days_before INT[] NOT NULL DEFAULT ARRAY[7, 3, 1, 0];

-- 3. Gift ideas — AI генеровані та збережені користувачем
CREATE TABLE IF NOT EXISTS gift_ideas (
    id           BIGSERIAL PRIMARY KEY,
    contact_id   BIGINT NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    owner_id     BIGINT NOT NULL REFERENCES users(telegram_id) ON DELETE CASCADE,
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    price_range  VARCHAR(50),
    status       VARCHAR(20) NOT NULL DEFAULT 'suggested',
    source       VARCHAR(20) NOT NULL DEFAULT 'ai',
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT gift_ideas_status_valid CHECK (status IN ('suggested','saved','bought','rejected')),
    CONSTRAINT gift_ideas_source_valid CHECK (source IN ('ai','manual'))
);

CREATE INDEX IF NOT EXISTS idx_gift_ideas_contact ON gift_ideas (contact_id, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_gift_ideas_owner_status ON gift_ideas (owner_id, status);

-- 4. Reminders log: додаємо days_before щоб підтримати multi-stage нагадування
ALTER TABLE reminders_log
    ADD COLUMN IF NOT EXISTS days_before INT NOT NULL DEFAULT 0;

-- Змінюємо unique constraint: тепер (contact_id, remind_year, days_before)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reminders_unique') THEN
        ALTER TABLE reminders_log DROP CONSTRAINT reminders_unique;
    END IF;
END $$;

ALTER TABLE reminders_log
    ADD CONSTRAINT reminders_unique UNIQUE (contact_id, remind_year, days_before);

-- 5. Зручна view для cron: контакти у яких ДН через N днів (N з reminder_days_before)
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
    days_before,
    DATE_PART('year', AGE(c.birthday))::INT + 1 AS turning_age,
    EXTRACT(YEAR FROM (NOW() AT TIME ZONE u.timezone))::INT AS remind_year
FROM contacts c
JOIN users u ON u.telegram_id = c.owner_id
CROSS JOIN LATERAL UNNEST(u.reminder_days_before) AS days_before
WHERE u.is_active = TRUE
  -- Перевіряємо: сьогодні + days_before = ДН (month/day match)
  AND EXTRACT(MONTH FROM c.birthday) = EXTRACT(MONTH FROM ((NOW() AT TIME ZONE u.timezone)::DATE + days_before))
  AND EXTRACT(DAY FROM c.birthday)   = EXTRACT(DAY FROM ((NOW() AT TIME ZONE u.timezone)::DATE + days_before))
  AND EXTRACT(HOUR FROM (NOW() AT TIME ZONE u.timezone)) = 9
  AND NOT EXISTS (
      SELECT 1 FROM reminders_log r
      WHERE r.contact_id = c.id
        AND r.remind_year = EXTRACT(YEAR FROM (NOW() AT TIME ZONE u.timezone))::INT
        AND r.days_before = days_before
  );

COMMIT;
