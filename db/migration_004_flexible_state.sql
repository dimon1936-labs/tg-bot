-- Migration 004: flexible session state (для clarification FSM)

BEGIN;

-- Drop strict CHECK — дозволяємо довільні state-значення для розширення
ALTER TABLE user_sessions DROP CONSTRAINT IF EXISTS user_sessions_state_valid;

COMMIT;
