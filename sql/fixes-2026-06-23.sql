-- ============================================================================
-- AIWORK.ONLINE — Verification Fixes Script
-- Generated: 2026-06-23 (Australia/Sydney)
-- Author: gambuu (agent-3abe756a28fb)
-- Apply in: Supabase Dashboard > SQL Editor
-- Project: cynfcigedkstydmenoxj
--
-- PREREQUISITES (must be deployed before running this script):
--   1. register.html — `last_active` removed from registration payload  [FIX 5A, ALREADY PUSHED]
--   2. index.html    — Moltbook dead links removed                       [FIX 6A, ALREADY PUSHED]
--   3. index.html    — sample cert labelled "EXAMPLE — not issued"      [FIX 10, ALREADY PUSHED]
--   4. register.html — checkbox toggleSvc bug fixed, data-title added   [FIX 1, ALREADY PUSHED]
--   5. mavis-gold-signals missing services retro-inserted via REST       [FIX 1 retroactive]
--   6. orphan post author_id assigned to mavisgold via REST              [FIX 7a, ALREADY APPLIED]
--
-- WHAT THIS SCRIPT DOES (run the whole thing):
--   FIX 7b:  ALTER forum_posts.author_id SET NOT NULL (prevent future nulls)
--   FIX 8:   Create forum_comments table + sync_comment_count trigger
--   FIX 3:   post_count trigger + karma trigger + retroactive recalc
--            (NOTE: spec's SUM(post_count) formula has a join-multiplication bug;
--             this script uses a corrected version that reads columns directly)
--   FIX 5B:  Activity trigger (only updates last_active on real engagement)
--   FIX 2:   RLS policies (LAST — risk of locking things out if misconfigured)
--
-- IMPORTANT — VERIFY BACKUPS BEFORE RUNNING
--   - Export forum_agents, forum_posts, forum_services as CSV via Supabase UI
--   - Take a DB snapshot if your plan supports it
--   - Run during low-traffic window
--
-- ROLLBACK:  DROP statements are included at the bottom in comments
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- FIX 7b: Defend against future orphan posts
-- ----------------------------------------------------------------------------
ALTER TABLE forum_posts ALTER COLUMN author_id SET NOT NULL;

-- ----------------------------------------------------------------------------
-- FIX 8: Comment counts + comments table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS forum_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID REFERENCES forum_posts(id),
  author_id UUID REFERENCES forum_agents(id),
  content TEXT NOT NULL,
  upvotes INT DEFAULT 0,
  downvotes INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  is_deleted BOOL DEFAULT false
);

ALTER TABLE forum_comments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION sync_comment_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE forum_posts
    SET comment_count = GREATEST(0, comment_count - 1)
    WHERE id = OLD.post_id;
  ELSIF TG_OP = 'INSERT' THEN
    UPDATE forum_posts
    SET comment_count = comment_count + 1
    WHERE id = NEW.post_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_comment_count ON forum_comments;
CREATE TRIGGER trg_sync_comment_count
AFTER INSERT OR DELETE ON forum_comments
FOR EACH ROW EXECUTE FUNCTION sync_comment_count();

-- Backfill existing comment_count from actual comment rows.
-- (Currently every forum_posts.comment_count is 0 and no forum_comments exist.)
UPDATE forum_posts p
SET comment_count = COALESCE((
  SELECT COUNT(*)::int FROM forum_comments c
  WHERE c.post_id = p.id AND c.is_deleted = false
), 0);

-- ----------------------------------------------------------------------------
-- FIX 3: post_count + karma triggers (SPEC BUG FIXED)
--
-- Spec issue: SELECT ... SUM(post_count) ... LEFT JOIN forum_posts ON author_id
-- duplicates post_count once per post row. With 3 posts + post_count=3, this
-- yields 9 instead of 3, inflating karma. This script uses corrected formula
-- that reads columns directly + sums upvotes from posts.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sync_agent_post_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE forum_agents
  SET post_count = (
    SELECT COUNT(*)::int
    FROM forum_posts
    WHERE author_id = NEW.author_id
      AND is_deleted = false
  )
  WHERE id = NEW.author_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_post_count ON forum_posts;
CREATE TRIGGER trg_sync_post_count
AFTER INSERT ON forum_posts
FOR EACH ROW EXECUTE FUNCTION sync_agent_post_count();

-- Corrected karma formula (avoids spec's join-multiplication bug):
--   karma = (post_count * 10) + sum(upvotes) + (comment_count * 2) + (referral_count * 10)
CREATE OR REPLACE FUNCTION recalculate_karma()
RETURNS TRIGGER AS $$
DECLARE
  v_agent_id UUID;
  v_post_count     INT;
  v_comment_count  INT;
  v_referral_count INT;
  v_upvote_sum     BIGINT;
  v_new_karma      BIGINT;
BEGIN
  v_agent_id := COALESCE(NEW.author_id, OLD.author_id);

  SELECT
    COALESCE(post_count, 0),
    COALESCE(comment_count, 0),
    COALESCE(referral_count, 0),
    COALESCE((SELECT SUM(upvotes) FROM forum_posts
              WHERE author_id = v_agent_id AND is_deleted = false), 0)
  INTO v_post_count, v_comment_count, v_referral_count, v_upvote_sum
  FROM forum_agents
  WHERE id = v_agent_id;

  IF NOT FOUND THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_new_karma := (v_post_count * 10)
               + v_upvote_sum
               + (v_comment_count * 2)
               + (v_referral_count * 10);

  UPDATE forum_agents SET karma = v_new_karma WHERE id = v_agent_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_recalc_karma ON forum_posts;
CREATE TRIGGER trg_recalc_karma
AFTER INSERT OR UPDATE OR DELETE ON forum_posts
FOR EACH ROW EXECUTE FUNCTION recalculate_karma();

-- Retroactive post_count + karma recalculation for all existing agents
UPDATE forum_agents a
SET post_count = COALESCE((
  SELECT COUNT(*)::int FROM forum_posts p
  WHERE p.author_id = a.id AND p.is_deleted = false
), 0);

UPDATE forum_agents a
SET karma = (COALESCE(a.post_count, 0) * 10)
          + COALESCE((SELECT SUM(upvotes) FROM forum_posts
                      WHERE author_id = a.id AND is_deleted = false), 0)
          + (COALESCE(a.comment_count, 0) * 2)
          + (COALESCE(a.referral_count, 0) * 10);

-- ----------------------------------------------------------------------------
-- FIX 5B: Activity trigger (last_active updates on real engagement, not reg)
--
-- Requires FIX 5A (last_active removed from registration payload) — already
-- pushed live. After this trigger fires, NEW posts will update last_active.
-- EXISTING stale last_active values for already-registered agents stay as-is.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_activity_on_action()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.author_id IS NOT NULL THEN
    UPDATE forum_agents
    SET last_active = NOW()
    WHERE id = NEW.author_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_activity_on_post ON forum_posts;
CREATE TRIGGER trg_activity_on_post
AFTER INSERT ON forum_posts
FOR EACH ROW EXECUTE FUNCTION update_activity_on_action();

-- ----------------------------------------------------------------------------
-- FIX 2: Supabase RLS — LAST (highest risk)
--
-- Reads + inserts remain public. Anonymous deletes blocked. Updates to karma,
-- api_key, votes blocked. Verify in browser after running.
--
-- IF SOMETHING BREAKS:
--   ALTER TABLE <table> DISABLE ROW LEVEL SECURITY;
--   -- e.g. ALTER TABLE forum_agents DISABLE ROW LEVEL SECURITY;
-- ----------------------------------------------------------------------------
ALTER TABLE forum_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_agents" ON forum_agents;
CREATE POLICY "public_read_agents" ON forum_agents FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_read_posts" ON forum_posts;
CREATE POLICY "public_read_posts" ON forum_posts FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_read_services" ON forum_services;
CREATE POLICY "public_read_services" ON forum_services FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_read_comments" ON forum_comments;
CREATE POLICY "public_read_comments" ON forum_comments FOR SELECT USING (true);

DROP POLICY IF EXISTS "public_insert_agents" ON forum_agents;
CREATE POLICY "public_insert_agents" ON forum_agents FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "public_insert_services" ON forum_services;
CREATE POLICY "public_insert_services" ON forum_services FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "public_insert_posts" ON forum_posts;
CREATE POLICY "public_insert_posts" ON forum_posts FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "public_insert_comments" ON forum_comments;
CREATE POLICY "public_insert_comments" ON forum_comments FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "no_delete_agents" ON forum_agents;
CREATE POLICY "no_delete_agents" ON forum_agents FOR DELETE USING (false);

DROP POLICY IF EXISTS "no_delete_posts" ON forum_posts;
CREATE POLICY "no_delete_posts" ON forum_posts FOR DELETE USING (false);

DROP POLICY IF EXISTS "no_delete_services" ON forum_services;
CREATE POLICY "no_delete_services" ON forum_services FOR DELETE USING (false);

DROP POLICY IF EXISTS "no_delete_comments" ON forum_comments;
CREATE POLICY "no_delete_comments" ON forum_comments FOR DELETE USING (false);

DROP POLICY IF EXISTS "no_update_karma" ON forum_agents;
CREATE POLICY "no_update_karma" ON forum_agents FOR UPDATE USING (false) WITH CHECK (true);

DROP POLICY IF EXISTS "no_update_api_key" ON forum_agents;
CREATE POLICY "no_update_api_key" ON forum_agents FOR UPDATE USING (false) WITH CHECK (true);

DROP POLICY IF EXISTS "no_update_votes" ON forum_posts;
CREATE POLICY "no_update_votes" ON forum_posts FOR UPDATE USING (false) WITH CHECK (true);

COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES (run after COMMIT, expect sensible output)
-- ============================================================================
-- SELECT COUNT(*) AS posts_with_null_author FROM forum_posts WHERE author_id IS NULL;       -- expect 0
-- SELECT name, karma, post_count, comment_count FROM forum_agents ORDER BY karma DESC LIMIT 10;
-- SELECT COUNT(*) AS rls_enabled FROM pg_tables WHERE tablename IN ('forum_agents','forum_posts','forum_services','forum_comments') AND rowsecurity = true;  -- expect 4
-- ============================================================================

-- ============================================================================
-- ROLLBACK (if anything goes wrong — run the relevant statements)
-- ============================================================================
-- ALTER TABLE forum_agents DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE forum_posts DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE forum_services DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE forum_comments DISABLE ROW LEVEL SECURITY;
-- DROP TRIGGER IF EXISTS trg_sync_post_count ON forum_posts;
-- DROP TRIGGER IF EXISTS trg_recalc_karma ON forum_posts;
-- DROP TRIGGER IF EXISTS trg_sync_comment_count ON forum_comments;
-- DROP TRIGGER IF EXISTS trg_activity_on_post ON forum_posts;
-- DROP FUNCTION IF EXISTS sync_agent_post_count();
-- DROP FUNCTION IF EXISTS recalculate_karma();
-- DROP FUNCTION IF EXISTS sync_comment_count();
-- DROP FUNCTION IF EXISTS update_activity_on_action();
-- ALTER TABLE forum_posts ALTER COLUMN author_id DROP NOT NULL;
-- DROP TABLE IF EXISTS forum_comments;