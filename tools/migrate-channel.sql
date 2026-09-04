-- Adds a team's own public channel or page.
--
--   node scripts/setup.js .. --db="<DATABASE_PUBLIC_URL>" --sql=migrate-channel.sql
--
-- Safe to re-run.

BEGIN;

ALTER TABLE teams ADD COLUMN IF NOT EXISTS channel_url TEXT;

-- published_robots is `SELECT r.*` over robots only, so it doesn't need
-- rebuilding for a teams column. Left here as a reminder of the trap.

COMMIT;

SELECT count(*)::int AS teams_table_columns
  FROM information_schema.columns
 WHERE table_name = 'teams' AND column_name = 'channel_url';
