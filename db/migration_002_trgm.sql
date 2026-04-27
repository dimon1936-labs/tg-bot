-- =============================================================
-- Migration 002: pg_trgm для fuzzy search контактів
--
-- Застосувати:
--   Get-Content db/migration_002_trgm.sql | docker exec -i birthday-bot-db psql -U postgres -d birthday_bot
-- =============================================================

BEGIN;

-- Extension для trigram similarity
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN індекс на name для швидкого fuzzy пошуку
CREATE INDEX IF NOT EXISTS idx_contacts_name_trgm
    ON contacts USING gin (LOWER(name) gin_trgm_ops);

-- Тест: similarity('петро', 'петра') ≈ 0.67, вище дефолтного порогу 0.3
-- SELECT similarity('петро', 'петра');  -- ~0.666

COMMIT;
