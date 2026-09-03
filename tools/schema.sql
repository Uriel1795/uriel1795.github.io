-- Robot Archive — complete schema (PostgreSQL)
--
-- This is the authoritative version. The tables in database-design.md were
-- written in pieces across three sections, and the moderation and embargo
-- sections added columns that were never folded back in. Everything is here.
--
-- Run against Railway Postgres:
--   psql "$DATABASE_PUBLIC_URL" -f schema.sql

-- ---------------------------------------------------------------- teams
-- A team number persists across years; the students on it change.
CREATE TABLE teams (
    id          SERIAL PRIMARY KEY,
    number      TEXT NOT NULL UNIQUE,          -- '34Q', '4610A'
    name        TEXT,                          -- 'Gear Grinders'
    program     TEXT NOT NULL,                 -- 'VEX IQ' | 'VEX V5'
    logo_url    TEXT,                          -- one per team, not per season
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT teams_program_valid CHECK (program IN ('VEX IQ', 'VEX V5', 'VEX U'))
);

-- ---------------------------------------------------------------- seasons
-- Replaces the hardcoded game table in the submission page. A new season is a
-- row, not a code change.
CREATE TABLE seasons (
    id          SERIAL PRIMARY KEY,
    program     TEXT NOT NULL,
    start_year  INTEGER NOT NULL,              -- 2024 for 2024-25
    game        TEXT NOT NULL,                 -- 'Rapid Relay'
    worlds_end  DATE,                          -- when embargoes lift by default

    CONSTRAINT seasons_program_valid CHECK (program IN ('VEX IQ', 'VEX V5', 'VEX U')),
    CONSTRAINT seasons_unique UNIQUE (program, start_year)
);

-- ---------------------------------------------------------------- students
-- Separate table so 'Nia W. in 2023' and 'Nia W. in 2024' are the same person.
-- Admin-only: the public submission form never creates these.
CREATE TABLE students (
    id            SERIAL PRIMARY KEY,
    display_name  TEXT NOT NULL,               -- whatever the site shows
    photo_url     TEXT,
    grad_year     INTEGER,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------- robots
CREATE TABLE robots (
    id            SERIAL PRIMARY KEY,
    team_id       INTEGER NOT NULL REFERENCES teams(id)   ON DELETE CASCADE,
    season_id     INTEGER NOT NULL REFERENCES seasons(id) ON DELETE RESTRICT,

    -- VEX U teams field two robots in a season and run them as an alliance,
    -- so team + season is not unique for them. NULL for IQ and V5.
    slot          TEXT,

    -- the model
    model_url     TEXT,                        -- full R2 URL once compressed
    rotation      JSONB,                       -- [x,y,z] degrees, for exports
                                               -- that come in on their side
    model_bytes   BIGINT,                      -- lets the roster filter without a HEAD
    raw_model_key TEXT,                        -- quarantine object, until compressed

    -- the notebook. Three columns rather than a table; there is only ever one.
    notebook_url    TEXT,
    notebook_pages  INTEGER,
    notebook_note   TEXT,

    -- results
    record        TEXT,
    award         TEXT,
    note          TEXT,
    specs         JSONB NOT NULL DEFAULT '{}'::jsonb,   -- displayed, never queried

    -- moderation
    status            TEXT NOT NULL DEFAULT 'pending',
    submitted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at       TIMESTAMPTZ,
    rejection_code    TEXT,                    -- enum, matches the public reasons page
    rejection_reason  TEXT,                    -- free text for cases the enum misses
    submitter_name    TEXT,                    -- optional, for your context only
    status_token      TEXT NOT NULL UNIQUE,    -- CSPRNG, 16 bytes base32
    warnings          JSONB NOT NULL DEFAULT '[]'::jsonb,  -- notes the form raised

    -- embargo
    publish_after  TIMESTAMPTZ,                -- NULL = publish on approval
    reveal_url     TEXT,                       -- team's own public reveal

    -- agreement, for the record
    agreed_version  TEXT,
    agreed_at       TIMESTAMPTZ,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT robots_status_valid CHECK (status IN ('pending','approved','rejected')),
    CONSTRAINT robots_slot_valid CHECK (slot IS NULL OR slot IN ('large','small'))
);

-- One robot per team per season, except VEX U which gets one per slot.
-- COALESCE is needed because Postgres treats NULLs as distinct in a plain
-- UNIQUE constraint, which would let duplicates through for IQ and V5.
CREATE UNIQUE INDEX robots_one_per_season
    ON robots (team_id, season_id, COALESCE(slot, ''));

-- NOTE: submitter_email is deliberately absent. Submitters are minors;
-- collecting an address puts under-13 submissions into COPPA scope for a
-- benefit status_token already provides. Do not add it back without reading
-- the "Telling the submitter" section first.

-- ---------------------------------------------------------------- crew
-- The join that makes "everything this student built" a query.
CREATE TABLE robot_students (
    robot_id    INTEGER NOT NULL REFERENCES robots(id)   ON DELETE CASCADE,
    student_id  INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    PRIMARY KEY (robot_id, student_id)
);

-- ---------------------------------------------------------------- mementos
-- Group shots are not allowed; see the "no identifiable people" rule.
CREATE TABLE mementos (
    id          SERIAL PRIMARY KEY,
    robot_id    INTEGER NOT NULL REFERENCES robots(id) ON DELETE CASCADE,
    url         TEXT NOT NULL,
    caption     TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------- jobs
-- Approval enqueues compression; the HTTP request never waits on it.
CREATE TABLE jobs (
    id          SERIAL PRIMARY KEY,
    robot_id    INTEGER NOT NULL REFERENCES robots(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL DEFAULT 'compress',
    state       TEXT NOT NULL DEFAULT 'queued',
    attempts    INTEGER NOT NULL DEFAULT 0,
    error       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT jobs_state_valid CHECK (state IN ('queued','running','done','failed'))
);

-- ---------------------------------------------------------------- indexes
CREATE INDEX robots_status_idx       ON robots (status);
CREATE INDEX robots_publish_idx      ON robots (publish_after);
CREATE INDEX robots_team_idx         ON robots (team_id);
CREATE INDEX robots_season_idx       ON robots (season_id);
CREATE INDEX robot_students_student  ON robot_students (student_id);
CREATE INDEX mementos_robot_idx      ON mementos (robot_id);
CREATE INDEX jobs_pending_idx        ON jobs (state, created_at);

-- ---------------------------------------------------------------- the filter
-- Structural equivalent of the EF Core global query filter: the public API
-- reads this view and never the robots table directly, so forgetting a WHERE
-- clause can't leak the queue or an embargoed robot.
-- NOTE: `SELECT r.*` is expanded once, when the view is created. If you add a
-- column to robots later, this view will NOT pick it up — drop and recreate it.
CREATE VIEW published_robots AS
SELECT r.*
FROM robots r
WHERE r.status = 'approved'
  AND (r.publish_after IS NULL OR r.publish_after <= now());

-- ---------------------------------------------------------------- touch
CREATE FUNCTION touch_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER robots_touch BEFORE UPDATE ON robots
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER jobs_touch BEFORE UPDATE ON jobs
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ---------------------------------------------------------------- seasons seed
-- Verified against the official V5RC and VIQRC competition histories.
-- VIQRC entries before 2019-20 are from memory; check them if you backfill.
INSERT INTO seasons (program, start_year, game) VALUES
    ('VEX V5', 2011, 'Gateway'),
    ('VEX V5', 2012, 'Sack Attack'),
    ('VEX V5', 2013, 'Toss Up'),
    ('VEX V5', 2014, 'Skyrise'),
    ('VEX V5', 2015, 'Nothing But Net'),
    ('VEX V5', 2016, 'Starstruck'),
    ('VEX V5', 2017, 'In the Zone'),
    ('VEX V5', 2018, 'Turning Point'),
    ('VEX V5', 2019, 'Tower Takeover'),
    ('VEX V5', 2020, 'Change Up'),
    ('VEX V5', 2021, 'Tipping Point'),
    ('VEX V5', 2022, 'Spin Up'),
    ('VEX V5', 2023, 'Over Under'),
    ('VEX V5', 2024, 'High Stakes'),
    ('VEX V5', 2025, 'Push Back'),
    ('VEX V5', 2026, 'Override'),
    ('VEX IQ', 2013, 'Add It Up'),
    ('VEX IQ', 2014, 'Highrise'),
    ('VEX IQ', 2015, 'Bank Shot'),
    ('VEX IQ', 2016, 'Crossover'),
    ('VEX IQ', 2017, 'Ringmaster'),
    ('VEX IQ', 2018, 'Next Level'),
    ('VEX IQ', 2019, 'Squared Away'),
    ('VEX IQ', 2020, 'Rise Above'),
    ('VEX IQ', 2021, 'Pitching In'),
    ('VEX IQ', 2022, 'Slapshot'),
    ('VEX IQ', 2023, 'Full Volume'),
    ('VEX IQ', 2024, 'Rapid Relay'),
    ('VEX IQ', 2025, 'Mix & Match'),
    ('VEX IQ', 2026, 'Level Up');

-- VEX U plays the V5 game each season, so the same names apply.
INSERT INTO seasons (program, start_year, game)
SELECT 'VEX U', start_year, game FROM seasons WHERE program = 'VEX V5';
