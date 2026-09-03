-- Migration: VEX U support, the two-robot slot, and model rotation.
-- Run once, before deploying the matching API code:
--
--   node scripts/setup.js .. --db="<DATABASE_PUBLIC_URL>" --sql=migrate-vexu.sql
--
-- Safe to re-run: every step checks whether it has already been applied.

BEGIN;

-- ---------------------------------------------------------------- programs
ALTER TABLE teams   DROP CONSTRAINT IF EXISTS teams_program_valid;
ALTER TABLE teams   ADD  CONSTRAINT teams_program_valid
    CHECK (program IN ('VEX IQ', 'VEX V5', 'VEX U'));

ALTER TABLE seasons DROP CONSTRAINT IF EXISTS seasons_program_valid;
ALTER TABLE seasons ADD  CONSTRAINT seasons_program_valid
    CHECK (program IN ('VEX IQ', 'VEX V5', 'VEX U'));

-- ------------------------------------------------------------------ robots
-- VEX U teams field two robots per season and run them as an alliance, so
-- team + season is no longer unique for them.
ALTER TABLE robots ADD COLUMN IF NOT EXISTS slot TEXT;
ALTER TABLE robots DROP CONSTRAINT IF EXISTS robots_slot_valid;
ALTER TABLE robots ADD  CONSTRAINT robots_slot_valid
    CHECK (slot IS NULL OR slot IN ('large', 'small'));

-- [x,y,z] degrees, for CAD exports that arrive lying on their side.
ALTER TABLE robots ADD COLUMN IF NOT EXISTS rotation JSONB;

-- Replace the old constraint with an index that includes the slot.
-- COALESCE is required: Postgres treats NULLs as distinct in a plain UNIQUE,
-- which would quietly remove duplicate protection for IQ and V5.
ALTER TABLE robots DROP CONSTRAINT IF EXISTS robots_one_per_season;
DROP INDEX IF EXISTS robots_one_per_season;
CREATE UNIQUE INDEX robots_one_per_season
    ON robots (team_id, season_id, COALESCE(slot, ''));

-- ----------------------------------------------------------------- seasons
-- VEX U plays the V5 game each season, so the same names apply.
INSERT INTO seasons (program, start_year, game)
SELECT 'VEX U', s.start_year, s.game
  FROM seasons s
 WHERE s.program = 'VEX V5'
   AND NOT EXISTS (
       SELECT 1 FROM seasons u
        WHERE u.program = 'VEX U' AND u.start_year = s.start_year
   );

-- ---------------------------------------------------------------- the view
-- published_robots was created as `SELECT r.*`, and Postgres expands `*` once,
-- at creation time. Adding columns above does NOT add them to the view, so it
-- has to be rebuilt or queries selecting slot/rotation from it will fail.
DROP VIEW IF EXISTS published_robots;
CREATE VIEW published_robots AS
SELECT r.*
FROM robots r
WHERE r.status = 'approved'
  AND (r.publish_after IS NULL OR r.publish_after <= now());

COMMIT;

-- What changed
SELECT
  (SELECT count(*) FROM seasons WHERE program = 'VEX U')::int AS vexu_seasons,
  (SELECT count(*) FROM information_schema.columns
    WHERE table_name = 'robots' AND column_name IN ('slot','rotation'))::int AS new_columns;
