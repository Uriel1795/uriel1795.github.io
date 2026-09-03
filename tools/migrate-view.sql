-- Rebuilds the published_robots view.
--
--   node scripts/setup.js .. --db="<DATABASE_PUBLIC_URL>" --sql=migrate-view.sql
--
-- Why this is needed: the view was created as `SELECT r.*`, and Postgres
-- expands `*` once, at creation time. Adding `slot` and `rotation` to the
-- robots table therefore did NOT add them to the view, so any query selecting
-- those columns from it fails — which is a 500 on /api/robots.
--
-- Safe to re-run.

BEGIN;

DROP VIEW IF EXISTS published_robots;

CREATE VIEW published_robots AS
SELECT r.*
FROM robots r
WHERE r.status = 'approved'
  AND (r.publish_after IS NULL OR r.publish_after <= now());

COMMIT;

-- Confirm the view now exposes the new columns.
SELECT string_agg(column_name, ', ' ORDER BY ordinal_position) AS view_columns
  FROM information_schema.columns
 WHERE table_name = 'published_robots'
   AND column_name IN ('slot', 'rotation', 'model_url', 'status');
