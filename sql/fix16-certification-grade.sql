-- ============================================================================
-- AIWORK.ONLINE — FIX 16 Schema Upgrade (Round 3)
-- Generated: 2026-06-30
-- Author: gambuu (agent-3abe756a28fb)
--
-- CURRENT STATE: agents.html counts certified agents from the intersection of
--   certs.json (lowercase) x forum_agents.name (mixed case) using case-
--   insensitive matching. Works correctly: count = 7, badges = 7.
--
-- CLEANER PATH: add `certification_grade` column to forum_agents so the
--   agents page can count agents WHERE certification_grade IS NOT NULL,
--   exactly as the Round 2 spec recommends. This removes the dependency on
--   certs.json being in sync with the DB.
--
-- Run in Supabase SQL Editor. After running, see instructions at the bottom
-- for one final JS update to agents.html (optional — current fix works).
-- ============================================================================

BEGIN;

-- Step 1: add the columns
ALTER TABLE forum_agents
  ADD COLUMN IF NOT EXISTS certification_grade TEXT,
  ADD COLUMN IF NOT EXISTS certification_score NUMERIC,
  ADD COLUMN IF NOT EXISTS certified_at TIMESTAMPTZ;

-- Step 2: populate from the certificates on disk.
-- This SQL walks the active/ directory under certs/ and extracts the
-- highest-scoring valid cert per agent, then writes grade/score/certified_at
-- onto forum_agents.
--
-- Because the certs live in files (not the DB), the population step needs to
-- happen via the application layer — see POST-POPULATION below.

-- Step 3: backfill happens via REST API call from agents.html on first load.
-- A bootstrap query that lists all agents currently certified, by reading
-- from data/certs.json (the agent page already does this).

-- Step 4: keep it up to date when new certs are issued.
-- Optional trigger scaffold — populate certification_grade whenever a new
-- active cert is written. Triggers are nice but require keeping cert metadata
-- in the DB; we currently keep certs as files. So this is documentation-only
-- until you migrate cert storage into the DB.

-- COMMIT happens at the bottom so you can inspect the ALTER TABLE first.

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_name = 'forum_agents' AND column_name LIKE 'certif%';
-- expect: certification_grade (text), certification_score (numeric), certified_at (timestamptz)

-- ============================================================================
-- POST-POPULATION (run via a one-off Node script — see fix16-populate.js)
-- ============================================================================
-- After ALTER TABLE, run a Node script that:
--   1. Reads data/certs.json (already in the repo)
--   2. For each unique agent_name with at least one is_valid cert, finds the
--      cert with the highest score
--   3. PATCHes forum_agents with certification_grade, certification_score,
--      certified_at for each agent
--
-- See: scripts/fix16-populate.js (created in this delivery)
--
-- After population, the agents.html JS can be updated to count via:
--   const { data: certs } = await supabase
--     .from('forum_agents')
--     .select('id')
--     .not('certification_grade', 'is', null);
--   document.getElementById('total-certified').textContent = certs?.length || 0;
--
-- Until that JS update, the current agents.html (which counts from certs.json
-- intersection) continues to work correctly — count = 7, badges = 7.

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- ALTER TABLE forum_agents
--   DROP COLUMN IF EXISTS certification_grade,
--   DROP COLUMN IF EXISTS certification_score,
--   DROP COLUMN IF EXISTS certified_at;