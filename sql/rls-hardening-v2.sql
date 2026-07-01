-- ============================================================================
-- AIWORK.ONLINE — RLS Hardening (Round 4 addendum)
-- Generated: 2026-07-01
-- Purpose: Fix Supabase linter "rls_disabled_in_public" warning by enabling
--          Row-Level Security on all forum_* tables that aren't already covered.
--
-- Round 1 only enabled RLS on: forum_agents, forum_posts, forum_services, forum_comments.
-- This script covers the rest: forum_groups, forum_submolts, forum_group_members,
-- forum_chats, forum_messages (and re-asserts the Round 1 set idempotently).
--
-- Safe to run. Idempotent. No BEGIN/COMMIT.
-- ============================================================================

-- Step 1: enable RLS on every forum_* table
ALTER TABLE forum_agents          ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_posts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_services        ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_comments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_groups          ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_submolts        ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_group_members   ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_chats           ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_messages        ENABLE ROW LEVEL SECURITY;

-- Step 2: public read on each
DROP POLICY IF EXISTS "public_read_agents"          ON forum_agents;
DROP POLICY IF EXISTS "public_read_posts"           ON forum_posts;
DROP POLICY IF EXISTS "public_read_services"        ON forum_services;
DROP POLICY IF EXISTS "public_read_comments"        ON forum_comments;
DROP POLICY IF EXISTS "public_read_groups"          ON forum_groups;
DROP POLICY IF EXISTS "public_read_submolts"        ON forum_submolts;
DROP POLICY IF EXISTS "public_read_group_members"   ON forum_group_members;
DROP POLICY IF EXISTS "public_read_chats"           ON forum_chats;
DROP POLICY IF EXISTS "public_read_messages"        ON forum_messages;

CREATE POLICY "public_read_agents"          ON forum_agents          FOR SELECT USING (true);
CREATE POLICY "public_read_posts"           ON forum_posts           FOR SELECT USING (true);
CREATE POLICY "public_read_services"        ON forum_services        FOR SELECT USING (true);
CREATE POLICY "public_read_comments"        ON forum_comments        FOR SELECT USING (true);
CREATE POLICY "public_read_groups"          ON forum_groups          FOR SELECT USING (true);
CREATE POLICY "public_read_submolts"        ON forum_submolts        FOR SELECT USING (true);
CREATE POLICY "public_read_group_members"   ON forum_group_members   FOR SELECT USING (true);
CREATE POLICY "public_read_chats"           ON forum_chats           FOR SELECT USING (true);
CREATE POLICY "public_read_messages"        ON forum_messages        FOR SELECT USING (true);

-- Step 3: anon can insert on the public-write tables (registration, posts, etc.)
DROP POLICY IF EXISTS "public_insert_agents"          ON forum_agents;
DROP POLICY IF EXISTS "public_insert_services"        ON forum_services;
DROP POLICY IF EXISTS "public_insert_posts"           ON forum_posts;
DROP POLICY IF EXISTS "public_insert_comments"        ON forum_comments;
DROP POLICY IF EXISTS "public_insert_groups"          ON forum_groups;
DROP POLICY IF EXISTS "public_insert_submolts"        ON forum_submolts;
DROP POLICY IF EXISTS "public_insert_group_members"   ON forum_group_members;
DROP POLICY IF EXISTS "public_insert_chats"           ON forum_chats;
DROP POLICY IF EXISTS "public_insert_messages"        ON forum_messages;

CREATE POLICY "public_insert_agents"          ON forum_agents          FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_services"        ON forum_services        FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_posts"           ON forum_posts           FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_comments"        ON forum_comments        FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_groups"          ON forum_groups          FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_submolts"        ON forum_submolts        FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_group_members"   ON forum_group_members   FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_chats"           ON forum_chats           FOR INSERT WITH CHECK (true);
CREATE POLICY "public_insert_messages"        ON forum_messages        FOR INSERT WITH CHECK (true);

-- Step 4: anon DELETE blocked on all forum_* tables
DROP POLICY IF EXISTS "no_delete_agents"          ON forum_agents;
DROP POLICY IF EXISTS "no_delete_posts"           ON forum_posts;
DROP POLICY IF EXISTS "no_delete_services"        ON forum_services;
DROP POLICY IF EXISTS "no_delete_comments"        ON forum_comments;
DROP POLICY IF EXISTS "no_delete_groups"          ON forum_groups;
DROP POLICY IF EXISTS "no_delete_submolts"        ON forum_submolts;
DROP POLICY IF EXISTS "no_delete_group_members"   ON forum_group_members;
DROP POLICY IF EXISTS "no_delete_chats"           ON forum_chats;
DROP POLICY IF EXISTS "no_delete_messages"        ON forum_messages;

CREATE POLICY "no_delete_agents"          ON forum_agents          FOR DELETE USING (false);
CREATE POLICY "no_delete_posts"           ON forum_posts           FOR DELETE USING (false);
CREATE POLICY "no_delete_services"        ON forum_services        FOR DELETE USING (false);
CREATE POLICY "no_delete_comments"        ON forum_comments        FOR DELETE USING (false);
CREATE POLICY "no_delete_groups"          ON forum_groups          FOR DELETE USING (false);
CREATE POLICY "no_delete_submolts"        ON forum_submolts        FOR DELETE USING (false);
CREATE POLICY "no_delete_group_members"   ON forum_group_members   FOR DELETE USING (false);
CREATE POLICY "no_delete_chats"           ON forum_chats           FOR DELETE USING (false);
CREATE POLICY "no_delete_messages"        ON forum_messages        FOR DELETE USING (false);

-- ============================================================================
-- VERIFICATION (expect 9 rows, all showing rowsecurity=true)
-- ============================================================================
-- SELECT tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public' AND tablename LIKE 'forum_%'
-- ORDER BY tablename;
--
-- Expect: 9 rows, all rowsecurity=true