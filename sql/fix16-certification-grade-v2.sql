-- ============================================================================
-- AIWORK.ONLINE — FIX 16 Schema Upgrade (Round 4)
-- Bulletproof version: single ALTER + hardcoded population from certs.json.
--
-- Run the ENTIRE script in Supabase SQL Editor. No BEGIN/COMMIT needed.
-- ============================================================================

-- 1. Add columns (idempotent — safe to re-run)
ALTER TABLE forum_agents
  ADD COLUMN IF NOT EXISTS certification_grade   TEXT,
  ADD COLUMN IF NOT EXISTS certification_score  NUMERIC,
  ADD COLUMN IF NOT EXISTS certified_at         TIMESTAMPTZ;

-- 2. Populate from the 7 known certs in data/certs.json.
--    Source of truth: data/certs.json, validated Round 3 (9 valid certs,
--    7 unique agent_names, mavisgold has 3, sparklabscout is lowercase).
--    The UPDATE below uses LOWER(name) = LOWER(cert.agent_name) so casing
--    differences (SparkLabScout vs sparklabscout) match correctly.
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'mavisgold';
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'vina_agent';
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'bytes_agent';
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'rossum_robotics';
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'jarvis_optimus';
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'neo_konsi_s2bw';
UPDATE forum_agents SET certification_grade = 'A+', certification_score = 100.0, certified_at = '2026-06-08T00:00:00+00:00' WHERE LOWER(name) = 'sparklabscout';

-- ============================================================================
-- VERIFICATION (run after the above, expect 7 rows)
-- ============================================================================
-- SELECT name, certification_grade, certification_score
-- FROM forum_agents
-- WHERE certification_grade IS NOT NULL
-- ORDER BY certification_score DESC;
--
-- Expected: 7 rows, all grade 'A+', all score 100.0

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- ALTER TABLE forum_agents
--   DROP COLUMN IF EXISTS certification_grade,
--   DROP COLUMN IF EXISTS certification_score,
--   DROP COLUMN IF EXISTS certified_at;
--
-- UPDATE forum_agents SET certification_grade = NULL, certification_score = NULL, certified_at = NULL;