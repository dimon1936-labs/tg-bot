-- =============================================================
-- Birthday Reminder Bot — PostgreSQL schema
-- Auto-applied on first container start via /docker-entrypoint-initdb.d
-- =============================================================

SET client_encoding = 'UTF8';

-- =============================================================
-- users: зареєстровані користувачі бота
-- =============================================================
CREATE TABLE IF NOT EXISTS users (
    telegram_id    BIGINT PRIMARY KEY,
    phone_number   VARCHAR(20),
    username       VARCHAR(100),
    -- first_name nullable: у Telegram user може не мати first_name.
    -- В application коді робимо fallback: first_name || username || 'User'
    first_name     VARCHAR(100),
    last_name      VARCHAR(100),
    -- language_code без дефолту: беремо з Telegram (msg.from.language_code),
    -- у коді fallback на 'uk' якщо відсутнє
    language_code  VARCHAR(10),
    timezone       VARCHAR(50) NOT NULL DEFAULT 'Europe/Kyiv',
    registered_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone
    ON users (phone_number) WHERE phone_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_active
    ON users (telegram_id) WHERE is_active = TRUE;

-- =============================================================
-- contacts: контакти користувачів з ДН
-- =============================================================
CREATE TABLE IF NOT EXISTS contacts (
    id          BIGSERIAL PRIMARY KEY,
    owner_id    BIGINT NOT NULL REFERENCES users(telegram_id) ON DELETE CASCADE,
    name        VARCHAR(100) NOT NULL,
    birthday    DATE NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT contacts_name_len      CHECK (char_length(name) BETWEEN 1 AND 100),
    CONSTRAINT contacts_birthday_past CHECK (birthday <= CURRENT_DATE),
    CONSTRAINT contacts_birthday_sane CHECK (birthday >= '1900-01-01')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_contacts_owner_name
    ON contacts (owner_id, LOWER(name));

CREATE INDEX IF NOT EXISTS idx_contacts_birthday_mmdd
    ON contacts (EXTRACT(MONTH FROM birthday), EXTRACT(DAY FROM birthday));

CREATE INDEX IF NOT EXISTS idx_contacts_owner
    ON contacts (owner_id);

-- =============================================================
-- user_sessions: FSM state per user
-- =============================================================
CREATE TABLE IF NOT EXISTS user_sessions (
    telegram_id  BIGINT PRIMARY KEY REFERENCES users(telegram_id) ON DELETE CASCADE,
    state        VARCHAR(50) NOT NULL DEFAULT 'idle',
    context      JSONB,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT user_sessions_state_valid CHECK (
        state IN ('idle',
                  'awaiting_name',
                  'awaiting_birthday',
                  'confirming_add',
                  'confirming_delete',
                  'awaiting_phone')
    )
);

CREATE INDEX IF NOT EXISTS idx_sessions_updated
    ON user_sessions (updated_at);

-- TTL cleanup: reset stuck sessions older than 1 hour (виконується cron-ом)
-- UPDATE user_sessions SET state='idle', context=NULL
-- WHERE state != 'idle' AND updated_at < NOW() - INTERVAL '1 hour';

-- =============================================================
-- processed_updates: idempotency guard для long polling
-- =============================================================
CREATE TABLE IF NOT EXISTS processed_updates (
    update_id     BIGINT PRIMARY KEY,
    processed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_processed_updates_time
    ON processed_updates (processed_at);

-- TTL cleanup (виконується cron-ом у Node-RED щоночі):
-- DELETE FROM processed_updates WHERE processed_at < NOW() - INTERVAL '7 days';

-- =============================================================
-- bot_offset: singleton row для long polling offset
-- =============================================================
CREATE TABLE IF NOT EXISTS bot_offset (
    id              INT PRIMARY KEY DEFAULT 1,
    last_update_id  BIGINT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT bot_offset_singleton CHECK (id = 1)
);

INSERT INTO bot_offset (id, last_update_id) VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;

-- =============================================================
-- reminders_log: історія надісланих нагадувань (idempotency)
-- =============================================================
CREATE TABLE IF NOT EXISTS reminders_log (
    id            BIGSERIAL PRIMARY KEY,
    contact_id    BIGINT NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    owner_id      BIGINT NOT NULL REFERENCES users(telegram_id) ON DELETE CASCADE,
    sent_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    remind_year   INT NOT NULL,

    CONSTRAINT reminders_unique UNIQUE (contact_id, remind_year)
);

CREATE INDEX IF NOT EXISTS idx_reminders_owner_sent
    ON reminders_log (owner_id, sent_at);

-- =============================================================
-- audit_log: immutable append-only (banking compliance)
-- =============================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id            BIGSERIAL PRIMARY KEY,
    telegram_id   BIGINT REFERENCES users(telegram_id) ON DELETE SET NULL,
    action        VARCHAR(50) NOT NULL,
    entity_type   VARCHAR(50),
    entity_id     BIGINT,
    payload       JSONB,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_user_time
    ON audit_log (telegram_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_action_time
    ON audit_log (action, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_time
    ON audit_log (created_at DESC);

-- =============================================================
-- rate_limits: sliding window per user per action
-- =============================================================
CREATE TABLE IF NOT EXISTS rate_limits (
    telegram_id   BIGINT NOT NULL,
    action        VARCHAR(50) NOT NULL,
    count         INT NOT NULL DEFAULT 1,
    window_start  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (telegram_id, action)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_window
    ON rate_limits (window_start);

-- =============================================================
-- Auto-update updated_at trigger для contacts / user_sessions
-- =============================================================
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_contacts_touch ON contacts;
CREATE TRIGGER trg_contacts_touch
    BEFORE UPDATE ON contacts
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_sessions_touch ON user_sessions;
CREATE TRIGGER trg_sessions_touch
    BEFORE UPDATE ON user_sessions
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- =============================================================
-- Helper view: upcoming birthdays (наступні 30 днів)
-- =============================================================
CREATE OR REPLACE VIEW v_upcoming_birthdays AS
SELECT
    c.id,
    c.owner_id,
    c.name,
    c.birthday,
    (DATE_PART('year', AGE(c.birthday))::INT + 1) AS turning_age,
    (
        DATE(
            DATE_PART('year', NOW()) ||
            '-' ||
            LPAD(DATE_PART('month', c.birthday)::TEXT, 2, '0') ||
            '-' ||
            LPAD(DATE_PART('day', c.birthday)::TEXT, 2, '0')
        ) - CURRENT_DATE
    ) AS days_until
FROM contacts c
WHERE
    DATE(
        DATE_PART('year', NOW()) ||
        '-' ||
        LPAD(DATE_PART('month', c.birthday)::TEXT, 2, '0') ||
        '-' ||
        LPAD(DATE_PART('day', c.birthday)::TEXT, 2, '0')
    ) BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days';

-- =============================================================
-- Done
-- =============================================================
