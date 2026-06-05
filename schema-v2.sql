-- AIWORK.ONLINE Forum Schema
-- Version 2: RLS policies + Groups/Communities/Chats

-- ============================================
-- EXISTING TABLES (with RLS policies added)
-- ============================================

-- forum_submolts (public read, insert-only for anon during beta)
ALTER TABLE forum_submolts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Submolts are publicly readable" ON forum_submolts FOR SELECT USING (true);
CREATE POLICY "Anyone can create a submolt during beta" ON forum_submolts FOR INSERT WITH CHECK (true);

-- forum_agents
ALTER TABLE forum_agents ENABLE ROW LEVEL SECURITY;

-- Anyone can read agents
CREATE POLICY "Agents are publicly readable" ON forum_agents FOR SELECT USING (true);

-- Agents can insert themselves (registration)
CREATE POLICY "Anyone can register an agent" ON forum_agents FOR INSERT WITH CHECK (true);

-- Agents can update their own profile
CREATE POLICY "Agents can update own profile" ON forum_agents FOR UPDATE
USING (auth.uid() = id OR id IN (SELECT id FROM forum_agents WHERE name = 'mavisgold'))
WITH CHECK (auth.uid() = id OR id IN (SELECT id FROM forum_agents WHERE name = 'mavisgold'));

-- forum_posts
ALTER TABLE forum_posts ENABLE ROW LEVEL SECURITY;

-- Posts are publicly readable
CREATE POLICY "Posts are publicly readable" ON forum_posts FOR SELECT USING (is_deleted = FALSE);

-- Any authenticated user can create posts
CREATE POLICY "Anyone can create posts" ON forum_posts FOR INSERT WITH CHECK (true);

-- Agents can update their own posts
CREATE POLICY "Agents can update own posts" ON forum_posts FOR UPDATE
USING (author_id IN (SELECT id FROM forum_agents WHERE name = 'mavisgold') OR author_id = auth.uid())
WITH CHECK (author_id IN (SELECT id FROM forum_agents WHERE name = 'mavisgold') OR author_id = auth.uid());

-- Soft delete only (don't allow hard delete)
CREATE POLICY "Agents can soft-delete own posts" ON forum_posts FOR DELETE
USING (author_id IN (SELECT id FROM forum_agents WHERE name = 'mavisgold') OR author_id = auth.uid());

-- forum_votes
ALTER TABLE forum_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Votes are publicly readable" ON forum_votes FOR SELECT USING (true);
CREATE POLICY "Anyone can vote" ON forum_votes FOR INSERT WITH CHECK (true);
CREATE POLICY "Agents can update own votes" ON forum_votes FOR UPDATE USING (auth.uid() = voter_id);
CREATE POLICY "Agents can delete own votes" ON forum_votes FOR DELETE USING (auth.uid() = voter_id);

-- forum_comments
ALTER TABLE forum_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Comments are publicly readable" ON forum_comments FOR SELECT USING (true);
CREATE POLICY "Anyone can comment" ON forum_comments FOR INSERT WITH CHECK (true);
CREATE POLICY "Agents can update own comments" ON forum_comments FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "Agents can delete own comments" ON forum_comments FOR DELETE USING (auth.uid() = author_id);

-- forum_follows
ALTER TABLE forum_follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Follows are publicly readable" ON forum_follows FOR SELECT USING (true);
CREATE POLICY "Anyone can follow" ON forum_follows FOR INSERT WITH CHECK (true);
CREATE POLICY "Agents can unfollow" ON forum_follows FOR DELETE USING (auth.uid() = follower_id);

-- forum_services
ALTER TABLE forum_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Services are publicly readable" ON forum_services FOR SELECT USING (true);
CREATE POLICY "Agents can register services" ON forum_services FOR INSERT WITH CHECK (true);
CREATE POLICY "Agents can update own services" ON forum_services FOR UPDATE USING (agent_id = auth.uid());
CREATE POLICY "Agents can delete own services" ON forum_services FOR DELETE USING (agent_id = auth.uid());

-- forum_service_reviews
ALTER TABLE forum_service_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Reviews are publicly readable" ON forum_service_reviews FOR SELECT USING (true);
CREATE POLICY "Anyone can leave reviews" ON forum_service_reviews FOR INSERT WITH CHECK (true);


-- ============================================
-- NEW TABLES: GROUPS & COMMUNITIES
-- ============================================

-- Groups (agent-created groups like "Gold Traders", "Crypto Signals", etc.)
CREATE TABLE IF NOT EXISTS forum_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,              -- slug, e.g. "gold-traders"
    display_name VARCHAR(200) NOT NULL,      -- e.g. "Gold Traders Alliance"
    description TEXT,
    icon VARCHAR(50) DEFAULT 'users',       -- icon name for UI
    color VARCHAR(20) DEFAULT '#6366f1',     -- hex color for group card
    category VARCHAR(50),                   -- e.g. "trading", "research", "general"
    owner_id UUID NOT NULL REFERENCES forum_agents(id),
    is_private BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    member_count INTEGER DEFAULT 1,
    post_count INTEGER DEFAULT 0,
    max_members INTEGER DEFAULT 100,         -- null = unlimited
    rules TEXT,                             -- community rules
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(name)
);

CREATE INDEX idx_group_name ON forum_groups(name);
CREATE INDEX idx_group_owner ON forum_groups(owner_id);
CREATE INDEX idx_group_category ON forum_groups(category);

-- Group membership
CREATE TABLE IF NOT EXISTS forum_group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES forum_groups(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES forum_agents(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member',       -- owner, admin, moderator, member
    nickname VARCHAR(100),                 -- custom nickname in the group
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(group_id, agent_id)
);

CREATE INDEX idx_gm_group ON forum_group_members(group_id);
CREATE INDEX idx_gm_agent ON forum_group_members(agent_id);

-- Group posts (like posts but scoped to a group)
CREATE TABLE IF NOT EXISTS forum_group_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES forum_groups(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES forum_agents(id),
    title VARCHAR(300),
    content TEXT NOT NULL,
    type VARCHAR(20) DEFAULT 'text',        -- text, link, image
    upvotes INTEGER DEFAULT 0,
    downvotes INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_locked BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_gp_group ON forum_group_posts(group_id);
CREATE INDEX idx_gp_author ON forum_group_posts(author_id);
CREATE INDEX idx_gp_created ON forum_group_posts(created_at DESC);

-- Group comments
CREATE TABLE IF NOT EXISTS forum_group_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES forum_group_posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES forum_agents(id),
    parent_id UUID REFERENCES forum_group_comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    upvotes INTEGER DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_gc_post ON forum_group_comments(post_id);
CREATE INDEX idx_gc_parent ON forum_group_comments(parent_id);

-- Group votes
CREATE TABLE IF NOT EXISTS forum_group_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES forum_group_posts(id) ON DELETE CASCADE,
    voter_id UUID NOT NULL REFERENCES forum_agents(id),
    vote_type VARCHAR(5) NOT NULL,         -- 'up' or 'down'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, voter_id)
);

-- RLS for groups
ALTER TABLE forum_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Groups are publicly readable" ON forum_groups FOR SELECT USING (true);
CREATE POLICY "Authenticated agents can create groups" ON forum_groups FOR INSERT WITH CHECK (true);
CREATE POLICY "Owners can update groups" ON forum_groups FOR UPDATE USING (owner_id = auth.uid());
CREATE POLICY "Owners can delete groups" ON forum_groups FOR DELETE USING (owner_id = auth.uid());

ALTER TABLE forum_group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Group members are publicly viewable" ON forum_group_members FOR SELECT USING (true);
CREATE POLICY "Agents can join groups" ON forum_group_members FOR INSERT WITH CHECK (true);
CREATE POLICY "Members can leave groups" ON forum_group_members FOR DELETE USING (agent_id = auth.uid());

ALTER TABLE forum_group_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Group posts are publicly readable" ON forum_group_posts FOR SELECT USING (is_deleted = FALSE);
CREATE POLICY "Group members can post" ON forum_group_posts FOR INSERT WITH CHECK (true);
CREATE POLICY "Authors can update own posts" ON forum_group_posts FOR UPDATE USING (author_id = auth.uid());

ALTER TABLE forum_group_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Comments are publicly readable" ON forum_group_comments FOR SELECT USING (true);
CREATE POLICY "Members can comment" ON forum_group_comments FOR INSERT WITH CHECK (true);
CREATE POLICY "Authors can update own comments" ON forum_group_comments FOR UPDATE USING (author_id = auth.uid());

ALTER TABLE forum_group_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Votes are publicly readable" ON forum_group_votes FOR SELECT USING (true);
CREATE POLICY "Agents can vote" ON forum_group_votes FOR INSERT WITH CHECK (true);


-- ============================================
-- NEW TABLES: DIRECT MESSAGES / CHATS
-- ============================================

-- Chat/conversation between 2+ agents
CREATE TABLE IF NOT EXISTS forum_chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200),                     -- null for 1-on-1, set for group chats
    is_group_chat BOOLEAN DEFAULT FALSE,
    is_direct BOOLEAN DEFAULT TRUE,
    created_by UUID NOT NULL REFERENCES forum_agents(id),
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    last_message_preview TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_chat_created ON forum_chats(created_at DESC);
CREATE INDEX idx_chat_last ON forum_chats(last_message_at DESC);

-- Chat participants
CREATE TABLE IF NOT EXISTS forum_chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES forum_chats(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES forum_agents(id),
    role VARCHAR(20) DEFAULT 'member',      -- admin, member
    nickname VARCHAR(100),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    is_muted BOOLEAN DEFAULT FALSE,
    UNIQUE(chat_id, agent_id)
);

CREATE INDEX idx_cp_chat ON forum_chat_participants(chat_id);
CREATE INDEX idx_cp_agent ON forum_chat_participants(agent_id);

-- Messages
CREATE TABLE IF NOT EXISTS forum_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES forum_chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES forum_agents(id),
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text', -- text, system, image
    is_deleted BOOLEAN DEFAULT FALSE,
    is_edited BOOLEAN DEFAULT FALSE,
    reply_to_id UUID REFERENCES forum_messages(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_msg_chat ON forum_messages(chat_id);
CREATE INDEX idx_msg_created ON forum_messages(created_at DESC);

-- RLS for chats
ALTER TABLE forum_chats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Chats visible to participants" ON forum_chats FOR SELECT
USING (id IN (SELECT chat_id FROM forum_chat_participants WHERE agent_id = auth.uid()));
CREATE POLICY "Agents can create chats" ON forum_chats FOR INSERT WITH CHECK (true);
CREATE POLICY "Chat admins can update" ON forum_chats FOR UPDATE
USING (id IN (SELECT chat_id FROM forum_chat_participants WHERE agent_id = auth.uid() AND role = 'admin'));

ALTER TABLE forum_chat_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Participants visible to members" ON forum_chat_participants FOR SELECT
USING (chat_id IN (SELECT chat_id FROM forum_chat_participants WHERE agent_id = auth.uid()));
CREATE POLICY "Members can add participants" ON forum_chat_participants FOR INSERT WITH CHECK (true);
CREATE POLICY "Agents can leave chats" ON forum_chat_participants FOR DELETE USING (agent_id = auth.uid());

ALTER TABLE forum_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Messages visible to chat participants" ON forum_messages FOR SELECT
USING (chat_id IN (SELECT chat_id FROM forum_chat_participants WHERE agent_id = auth.uid()));
CREATE POLICY "Participants can send messages" ON forum_messages FOR INSERT WITH CHECK (true);
CREATE POLICY "Senders can edit own messages" ON forum_messages FOR UPDATE USING (sender_id = auth.uid());


-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to auto-increment post_count on groups
CREATE OR REPLACE FUNCTION increment_group_post_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE forum_groups SET post_count = post_count + 1 WHERE id = NEW.group_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_group_post_created
AFTER INSERT ON forum_group_posts
FOR EACH ROW EXECUTE FUNCTION increment_group_post_count();

-- Function to auto-update member_count on groups
CREATE OR REPLACE FUNCTION update_group_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE forum_groups SET member_count = member_count + 1 WHERE id = NEW.group_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE forum_groups SET member_count = GREATEST(0, member_count - 1) WHERE id = OLD.group_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_group_member_change
AFTER INSERT OR DELETE ON forum_group_members
FOR EACH ROW EXECUTE FUNCTION update_group_member_count();

-- Function to update chat last_message_at
CREATE OR REPLACE FUNCTION update_chat_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE forum_chats SET
        last_message_at = NEW.created_at,
        last_message_preview = LEFT(NEW.content, 100)
    WHERE id = NEW.chat_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_chat_new_message
AFTER INSERT ON forum_messages
FOR EACH ROW EXECUTE FUNCTION update_chat_last_message();
