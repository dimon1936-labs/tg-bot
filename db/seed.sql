-- =============================================================
-- Seed data для демо / тестування
-- Застосовується АЛЕ тільки вручну (не в docker-entrypoint),
-- щоб production база стартувала чистою.
--
-- Запустити:
--   docker exec -i birthday-bot-db psql -U postgres -d birthday_bot < db/seed.sql
-- =============================================================

-- Demo user (замість реального Telegram ID)
INSERT INTO users (telegram_id, first_name, last_name, username, language_code, timezone)
VALUES
    (1000000001, 'Demo', 'User', 'demouser', 'uk', 'Europe/Kyiv')
ON CONFLICT (telegram_id) DO NOTHING;

-- Demo сесія
INSERT INTO user_sessions (telegram_id, state)
VALUES
    (1000000001, 'idle')
ON CONFLICT (telegram_id) DO NOTHING;

-- Demo контакти з різними датами
INSERT INTO contacts (owner_id, name, birthday, notes)
VALUES
    (1000000001, 'Оля',   '1995-03-15', 'Подруга з університету'),
    (1000000001, 'Петро', '1990-07-22', 'Колега з роботи'),
    (1000000001, 'Марія', '1988-12-24', 'Сестра'),
    (1000000001, 'Сьогодні', CURRENT_DATE - INTERVAL '30 years', 'Для тесту reminder-а (ДН сьогодні)')
ON CONFLICT (owner_id, LOWER(name)) DO NOTHING;

-- Audit log запис
INSERT INTO audit_log (telegram_id, action, entity_type, payload)
VALUES
    (1000000001, 'user_registered', 'user', '{"source": "seed"}'::jsonb)
ON CONFLICT DO NOTHING;

-- Показати що заінсертилось
SELECT 'users' AS tbl, COUNT(*) FROM users
UNION ALL SELECT 'contacts', COUNT(*) FROM contacts
UNION ALL SELECT 'user_sessions', COUNT(*) FROM user_sessions
UNION ALL SELECT 'audit_log', COUNT(*) FROM audit_log;
