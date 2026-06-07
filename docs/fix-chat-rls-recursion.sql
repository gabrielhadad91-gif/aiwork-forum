-- =============================================================
-- Fix: infinite recursion in chat RLS policies
-- PostgreSQL error 42P17: "infinite recursion detected in policy
--   for relation 'forum_chat_participants'"
--
-- Root cause: the SELECT policy on forum_chat_participants
-- self-references (queries the same table inside its USING clause).
-- That breaks every query against forum_chat_participants, which
-- then breaks forum_chats and forum_messages (their policies depend
-- on the participants table).
--
-- Two options below. Pick ONE.
-- =============================================================


-- -------------------------------------------------------------
-- OPTION A — minimal fix, beta-mode permissive policies
--   (recommended for now since there's no real auth yet)
-- -------------------------------------------------------------

DROP POLICY IF EXISTS "Participants visible to members" ON forum_chat_participants;
DROP POLICY IF EXISTS "Chats visible to participants" ON forum_chats;
DROP POLICY IF EXISTS "Messages visible to chat participants" ON forum_messages;

CREATE POLICY "Chat participants visible" ON forum_chat_participants FOR SELECT
USING (true);

CREATE POLICY "Chats visible" ON forum_chats FOR SELECT
USING (true);

CREATE POLICY "Messages visible" ON forum_messages FOR SELECT
USING (true);


-- -------------------------------------------------------------
-- OPTION B — future-proof: SECURITY DEFINER helper function
--   (use this when real auth is added; can also flip to this now)
-- -------------------------------------------------------------
-- CREATE OR REPLACE FUNCTION public.user_is_chat_member(_chat_id UUID)
-- RETURNS BOOLEAN
-- LANGUAGE sql
-- SECURITY DEFINER
-- SET search_path = public
-- STABLE
-- AS $$
--     -- TODO: replace with real check once auth is wired up
--     -- (this version returns true for everyone, same as Option A)
--     SELECT true;
-- $$;
--
-- DROP POLICY IF EXISTS "Participants visible to members" ON forum_chat_participants;
-- DROP POLICY IF EXISTS "Chats visible to participants" ON forum_chats;
-- DROP POLICY IF EXISTS "Messages visible to chat participants" ON forum_messages;
--
-- CREATE POLICY "Participants visible to members" ON forum_chat_participants FOR SELECT
-- USING (public.user_is_chat_member(chat_id));
--
-- CREATE POLICY "Chats visible to participants" ON forum_chats FOR SELECT
-- USING (public.user_is_chat_member(id));
--
-- CREATE POLICY "Messages visible to chat participants" ON forum_messages FOR SELECT
-- USING (public.user_is_chat_member(chat_id));


-- =============================================================
-- After running this:
-- 1. Verify with:  GET https://cynfcigedkstydmenoxj.supabase.co/rest/v1/forum_chats?select=id
--    (should now return 200, not 500)
-- 2. Try the "Send Message" flow on aiwork.online/agent.html?vina_agent
--    The full flow should work end-to-end.
-- =============================================================
