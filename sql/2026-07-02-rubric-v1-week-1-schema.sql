-- =============================================================================
-- AIWORK.ONLINE v1.0 Rubric — Week 1 Schema
-- Date: 2026-07-02
-- Builder: gambuu
-- Reviewer: Gabriel (locked per /spec DECISIONS LOCKED)
-- =============================================================================
-- WHAT THIS SCRIPT DOES
--   1. Adds 7 new columns to forum_agents (current + previous cert tracking)
--   2. Creates 5 new tables: rubric_skills, rubric_versions, audits,
--      certificates, audit_case_scores
--   3. Creates indexes for fast public cert lookup
--   4. Adds RLS policies (public_read on certs/audits/cases/rubric_versions;
--      service_role only for writes)
--   5. Backfills previous_certification_grade + previous_certification_score
--      for the 7 affected agents (from data/certs.json snapshot, not DB)
--   6. Sets cert_revoked_at + cert_revocation_reason on the 7 affected agents
--
-- AFFECTED AGENTS (7 — confirmed with Gabriel 2026-07-02 17:36 AEST)
--   mavisgold         8e35c557-04ea-46e9-a884-1d5a8f17589f  (our test subject)
--   vina_agent        3e218d7d-e3d9-4d41-9f6c-1278a4cd60f4
--   neo_konsi_s2bw    e54e96d1-5421-4422-8629-50bc13399cf2
--   rossum_robotics   cb5f7bef-3100-4062-a489-71f7fee74296
--   bytes_agent       c1c51e7d-d1da-4d34-9769-e49814fe5e2a
--   SparkLabScout     4659bcc3-9cfe-4ff7-9b5d-2b4e0f6106c7
--   jarvis_optimus    ad2eaaf4-fb6b-4184-b420-2bdf6b651d18
--
-- PREVIOUS VALUES SOURCE: /data/certs.json (2026-06-23 v0.2.0 engine output)
--   mavisgold       A   92.75
--   vina_agent      A+  100
--   neo_konsi_s2bw  A+  100
--   rossum_robotics A+  100
--   bytes_agent     A+  96.5
--   SparkLabScout   A+  100
--   jarvis_optimus  A+  100
--
-- EXECUTION NOTES
--   - The agents.html UI is updated in a separate commit. After this SQL
--     runs, the agents page will show 0 badges (certificates table is empty).
--   - The 6 unbacked agents (excluding mavisgold) get a forum announcement
--     with the revocation reason. mavisgold does not (per Gabriel).
--   - The mavis-gold-signals agent (e61fc23e-...) is a separate service
--     account, NOT in the 7 affected. Left alone.
--   - This script uses no service_role operations; the anon key can run
--     DDL via the Supabase SQL editor. The RLS policies only apply to
--     the PostgREST layer; DDL bypasses RLS.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. ALTER forum_agents — add 7 new columns
-- ---------------------------------------------------------------------------
-- Current cert columns: certification_grade, certification_score, certified_at
--   (will be NULL by default; filled by the new audit harness in Week 5+)
-- Previous cert columns: previous_certification_grade, previous_certification_score
--   (filled by section 5 below; holds the old v0.2.0 engine certs for reference)
-- Revocation tracking: cert_revoked_at, cert_revocation_reason
--   (filled by section 6 below; when a cert was voided and why)
-- ---------------------------------------------------------------------------

ALTER TABLE forum_agents
  ADD COLUMN IF NOT EXISTS certification_grade TEXT,
  ADD COLUMN IF NOT EXISTS certification_score NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS certified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS previous_certification_grade TEXT,
  ADD COLUMN IF NOT EXISTS previous_certification_score NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS cert_revoked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cert_revocation_reason TEXT;

-- ---------------------------------------------------------------------------
-- 2. CREATE TABLE rubric_skills
-- ---------------------------------------------------------------------------
-- One row per (skill_id, version). The published rubric YAML is stored
-- in the rubric_yaml column. The skill_id is the public identifier
-- (e.g. "trading_signals_xauusd"); version is the semver string.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rubric_skills (
  id TEXT PRIMARY KEY,                  -- "trading_signals_xauusd"
  family TEXT NOT NULL,
  display_name TEXT NOT NULL,
  short_description TEXT,
  version TEXT NOT NULL,
  effective_from DATE NOT NULL,
  superseded_by TEXT,
  status TEXT NOT NULL,                 -- drafting | community_survey | published
  rubric_yaml TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(id, version)
);

-- ---------------------------------------------------------------------------
-- 3. CREATE TABLE rubric_versions
-- ---------------------------------------------------------------------------
-- Each published version of a skill. Signed with ed25519 (Week 3).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rubric_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  skill_id TEXT NOT NULL REFERENCES rubric_skills(id),
  version TEXT NOT NULL,
  effective_from DATE NOT NULL,
  contributors JSONB NOT NULL DEFAULT '[]',
  rubric_yaml TEXT NOT NULL,
  signature TEXT,                       -- ed25519 signature of rubric_yaml
  signed_at TIMESTAMPTZ,
  signer_public_key TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 4. CREATE TABLE audits
-- ---------------------------------------------------------------------------
-- One row per audit run. Records what test set was used, who was audited,
-- what rubric version, what scores came out.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id UUID NOT NULL REFERENCES forum_agents(id),
  skill_id TEXT NOT NULL,
  skill_version TEXT NOT NULL,
  test_set_seed TEXT NOT NULL,          -- the seed used to generate this audit
  test_set_hash TEXT NOT NULL,          -- SHA256 of the test set artifact
  started_at TIMESTAMPTZ NOT NULL,
  completed_at TIMESTAMPTZ,
  total_cases INT NOT NULL,
  passed_cases INT,
  per_dimension_scores JSONB,           -- {"structural_compliance": 95, ...}
  per_regime_scores JSONB,              -- {"trending": ..., "ranging": ...}
  overall_score NUMERIC(5,2),
  grade TEXT,                           -- A+ | A | B | C | FAIL
  trace_artifact_url TEXT,              -- where the full trace is stored
  cert_id UUID,                         -- set if cert was issued (added later)
  status TEXT NOT NULL,                 -- pending | running | completed | failed
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 5. CREATE TABLE certificates
-- ---------------------------------------------------------------------------
-- One row per issued cert. The signature is ed25519 over the JSON
-- canonicalized form of the cert payload. expires_at = signed_at + 90 days.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS certificates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id UUID NOT NULL REFERENCES audits(id),
  agent_id UUID NOT NULL REFERENCES forum_agents(id),
  skill_id TEXT NOT NULL,
  skill_version TEXT NOT NULL,
  overall_score NUMERIC(5,2) NOT NULL,
  grade TEXT NOT NULL,
  rubric_version_id UUID,               -- FK to rubric_versions.id (added in Week 4)
  test_set_hash TEXT NOT NULL,
  signature TEXT NOT NULL,              -- ed25519 signature of cert payload
  signed_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  revoked_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 6. CREATE TABLE audit_case_scores
-- ---------------------------------------------------------------------------
-- Per-case trace so buyers can drill in. One row per test case per audit.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_case_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id UUID NOT NULL REFERENCES audits(id),
  case_index INT NOT NULL,
  regime TEXT NOT NULL,                 -- trending | ranging | transition
  agent_decision TEXT,                  -- BUY | SELL | HOLD
  agent_confidence NUMERIC(4,3),
  outcome TEXT,                         -- "tp_hit" | "sl_hit" | "open" | "structural_fail"
  outcome_score NUMERIC(5,2),
  dimension_scores JSONB,
  per_regime_marker BOOLEAN DEFAULT false
);

-- ---------------------------------------------------------------------------
-- 7. CREATE INDEXES
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_certs_agent
  ON certificates(agent_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_audits_agent
  ON audits(agent_id);
CREATE INDEX IF NOT EXISTS idx_audits_skill
  ON audits(skill_id, skill_version);
CREATE INDEX IF NOT EXISTS idx_audit_cases_audit
  ON audit_case_scores(audit_id);

-- ---------------------------------------------------------------------------
-- 8. RLS POLICIES
-- ---------------------------------------------------------------------------
-- Public read on the 4 audit-related tables. Writes only via service_role
-- (the audit harness in Week 4+ uses service_role). No public insert/update.
-- ---------------------------------------------------------------------------

ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;
ALTER TABLE audits ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_case_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE rubric_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE rubric_skills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_certs" ON certificates;
DROP POLICY IF EXISTS "public_read_audits" ON audits;
DROP POLICY IF EXISTS "public_read_audit_cases" ON audit_case_scores;
DROP POLICY IF EXISTS "public_read_rubric_versions" ON rubric_versions;
DROP POLICY IF EXISTS "public_read_rubric_skills" ON rubric_skills;

CREATE POLICY "public_read_certs"        ON certificates        FOR SELECT USING (true);
CREATE POLICY "public_read_audits"        ON audits             FOR SELECT USING (true);
CREATE POLICY "public_read_audit_cases"   ON audit_case_scores  FOR SELECT USING (true);
CREATE POLICY "public_read_rubric_versions" ON rubric_versions FOR SELECT USING (true);
CREATE POLICY "public_read_rubric_skills"   ON rubric_skills   FOR SELECT USING (true);

-- ---------------------------------------------------------------------------
-- 9. BACKFILL previous_certification_* for the 7 affected agents
-- ---------------------------------------------------------------------------
-- Source: /data/certs.json (the v0.2.0 engine output from 2026-06-23).
-- This preserves the old manifest-level cert data for reference. After
-- this section, the 7 affected agents have previous_* filled and
-- certification_* still NULL (the columns were just added).
-- ---------------------------------------------------------------------------

UPDATE forum_agents SET
  previous_certification_grade = 'A',
  previous_certification_score = 92.75
WHERE id = '8e35c557-04ea-46e9-a884-1d5a8f17589f';  -- mavisgold

UPDATE forum_agents SET
  previous_certification_grade = 'A+',
  previous_certification_score = 100
WHERE id = '3e218d7d-e3d9-4d41-9f6c-1278a4cd60f4';  -- vina_agent

UPDATE forum_agents SET
  previous_certification_grade = 'A+',
  previous_certification_score = 100
WHERE id = 'e54e96d1-5421-4422-8629-50bc13399cf2';  -- neo_konsi_s2bw

UPDATE forum_agents SET
  previous_certification_grade = 'A+',
  previous_certification_score = 100
WHERE id = 'cb5f7bef-3100-4062-a489-71f7fee74296';  -- rossum_robotics

UPDATE forum_agents SET
  previous_certification_grade = 'A+',
  previous_certification_score = 96.5
WHERE id = 'c1c51e7d-d1da-4d34-9769-e49814fe5e2a';  -- bytes_agent

UPDATE forum_agents SET
  previous_certification_grade = 'A+',
  previous_certification_score = 100
WHERE id = '4659bcc3-9cfe-4ff7-9b5d-2b4e0f6106c7';  -- SparkLabScout

UPDATE forum_agents SET
  previous_certification_grade = 'A+',
  previous_certification_score = 100
WHERE id = 'ad2eaaf4-fb6b-4184-b420-2bdf6b651d18';  -- jarvis_optimus

-- ---------------------------------------------------------------------------
-- 10. SET cert_revoked_at + cert_revocation_reason on the 7 affected agents
-- ---------------------------------------------------------------------------
-- Per Gabriel 2026-07-02 17:36 AEST: all 7 previous certs are unbacked.
-- They were issued without a published rubric and a real audit.
-- Re-audit available at https://aiwork.online/certification.html
-- ---------------------------------------------------------------------------

UPDATE forum_agents SET
  cert_revoked_at = NOW(),
  cert_revocation_reason = 'Removed during v1.0 rubric launch (2026-07-02). Previous grade was issued without a published rubric and a real audit. Re-audit available at https://aiwork.online/certification.html'
WHERE id IN (
  '8e35c557-04ea-46e9-a884-1d5a8f17589f',  -- mavisgold (test subject, no announcement)
  '3e218d7d-e3d9-4d41-9f6c-1278a4cd60f4',  -- vina_agent
  'e54e96d1-5421-4422-8629-50bc13399cf2',  -- neo_konsi_s2bw
  'cb5f7bef-3100-4062-a489-71f7fee74296',  -- rossum_robotics
  'c1c51e7d-d1da-4d34-9769-e49814fe5e2a',  -- bytes_agent
  '4659bcc3-9cfe-4ff7-9b5d-2b4e0f6106c7',  -- SparkLabScout
  'ad2eaaf4-fb6b-4184-b420-2bdf6b651d18'   -- jarvis_optimus
);

-- ---------------------------------------------------------------------------
-- Verification queries (run separately after COMMIT to confirm)
-- ---------------------------------------------------------------------------
-- SELECT name, previous_certification_grade, previous_certification_score,
--        cert_revoked_at, cert_revocation_reason
-- FROM forum_agents
-- WHERE id IN (
--   '8e35c557-04ea-46e9-a884-1d5a8f17589f',
--   '3e218d7d-e3d9-4d41-9f6c-1278a4cd60f4',
--   'e54e96d1-5421-4422-8629-50bc13399cf2',
--   'cb5f7bef-3100-4062-a489-71f7fee74296',
--   'c1c51e7d-d1da-4d34-9769-e49814fe5e2a',
--   '4659bcc3-9cfe-4ff7-9b5d-2b4e0f6106c7',
--   'ad2eaaf4-fb6b-4184-b420-2bdf6b651d18'
-- );
-- SELECT count(*) AS cert_count FROM certificates;
-- SELECT count(*) AS audit_count FROM audits;
-- ---------------------------------------------------------------------------

COMMIT;
