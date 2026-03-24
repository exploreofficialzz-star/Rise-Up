-- ══════════════════════════════════════════════════════
-- RiseUp Social Platform — Migration
-- Run this in Supabase SQL Editor
-- ══════════════════════════════════════════════════════

-- ── Posts ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS posts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content       TEXT NOT NULL,
    tag           TEXT DEFAULT '💰 Wealth',
    media_url     TEXT,
    media_type    TEXT, -- photo | video
    likes_count   INT DEFAULT 0,
    shares_count  INT DEFAULT 0,
    is_visible    BOOL DEFAULT TRUE,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS post_likes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS post_saves (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS post_comments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id    UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    parent_id  UUID REFERENCES post_comments(id) ON DELETE CASCADE,
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS comment_likes (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id UUID REFERENCES post_comments(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    UNIQUE(comment_id, user_id)
);

-- ── Follows ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS follows (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id  UUID REFERENCES profiles(id) ON DELETE CASCADE,
    following_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(follower_id, following_id)
);

-- ── Profiles extra fields ──────────────────────────────
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_verified BOOL DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS website TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_online BOOL DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS coins_balance INT DEFAULT 0;

-- ── Messages ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS conversations (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type       TEXT DEFAULT 'direct', -- direct | group
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    media_url       TEXT,
    is_read         BOOL DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── Groups ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS groups (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           TEXT NOT NULL,
    description    TEXT,
    emoji          TEXT DEFAULT '💰',
    category       TEXT DEFAULT 'Wealth',
    is_premium     BOOL DEFAULT FALSE,
    is_active      BOOL DEFAULT TRUE,
    members_count  INT DEFAULT 0,
    created_by     UUID REFERENCES profiles(id),
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS group_members (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id   UUID REFERENCES groups(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    role       TEXT DEFAULT 'member', -- member | admin | moderator
    joined_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(group_id, user_id)
);

CREATE TABLE IF NOT EXISTS group_posts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id   UUID REFERENCES groups(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    content    TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── Live Sessions ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS live_sessions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    host_id        UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title          TEXT NOT NULL,
    topic          TEXT DEFAULT '💰 Wealth',
    is_premium     BOOL DEFAULT FALSE,
    is_active      BOOL DEFAULT TRUE,
    viewers_count  INT DEFAULT 0,
    coins_earned   INT DEFAULT 0,
    started_at     TIMESTAMPTZ DEFAULT NOW(),
    ended_at       TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS live_viewers (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(session_id, user_id)
);

CREATE TABLE IF NOT EXISTS coin_gifts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES live_sessions(id) ON DELETE CASCADE,
    sender_id  UUID REFERENCES profiles(id),
    host_id    UUID REFERENCES profiles(id),
    amount     INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════
-- RPC Functions
-- ══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION increment_post_likes(pid UUID)
RETURNS void AS $$
  UPDATE posts SET likes_count = likes_count + 1 WHERE id = pid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION decrement_post_likes(pid UUID)
RETURNS void AS $$
  UPDATE posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = pid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION increment_post_shares(pid UUID)
RETURNS void AS $$
  UPDATE posts SET shares_count = shares_count + 1 WHERE id = pid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION increment_group_members(gid UUID)
RETURNS void AS $$
  UPDATE groups SET members_count = members_count + 1 WHERE id = gid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION decrement_group_members(gid UUID)
RETURNS void AS $$
  UPDATE groups SET members_count = GREATEST(members_count - 1, 0) WHERE id = gid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION increment_live_viewers(sid UUID)
RETURNS void AS $$
  UPDATE live_sessions SET viewers_count = viewers_count + 1 WHERE id = sid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION decrement_live_viewers(sid UUID)
RETURNS void AS $$
  UPDATE live_sessions SET viewers_count = GREATEST(viewers_count - 1, 0) WHERE id = sid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION add_live_coins(sid UUID, amount INT)
RETURNS void AS $$
  UPDATE live_sessions SET coins_earned = coins_earned + amount WHERE id = sid;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION get_conversation_between(user1 UUID, user2 UUID)
RETURNS TABLE(id UUID) AS $$
  SELECT c.id FROM conversations c
  JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = user1
  JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = user2
  WHERE c.type = 'direct'
  LIMIT 1;
$$ LANGUAGE SQL;

-- ══════════════════════════════════════════════════════
-- Seed default groups
-- ══════════════════════════════════════════════════════
INSERT INTO groups (name, description, emoji, category, members_count) VALUES
('Wealth Builders Global', 'The #1 community for building generational wealth worldwide', '💰', 'Wealth', 24500),
('Stock Market Mastery', 'Learn investing, stocks, ETFs and portfolio building', '📈', 'Investing', 18200),
('Freelancers Hub', 'Connect with freelancers, share clients and opportunities', '💼', 'Business', 31700),
('Millionaire Mindset', 'Daily mindset shifts for financial freedom', '🧠', 'Mindset', 15900),
('Budget Masters', 'Master budgeting, saving and debt elimination', '📊', 'Budgeting', 28400),
('Side Hustle Academy', 'From idea to income — build your side hustle', '⚡', 'Hustle', 35800),
('Goal Getters', 'Set, track and crush your personal & financial goals', '🎯', 'Personal Growth', 19600),
('Tech & Income', 'Turn your tech skills into income streams', '💻', 'Tech', 22100),
('Global Entrepreneurs', 'Entrepreneurs from every corner of the world', '🌍', 'Business', 41200),
('Self Development Hub', 'Books, habits, routines for success', '📚', 'Personal Growth', 26900),
('Real Estate Circle', 'Property investment strategies for all budgets', '🏠', 'Real Estate', 9300),
('Creative Monetizers', 'Turn your creativity into cash', '🎨', 'Skills', 14300),
('Productive Warriors', 'Productivity systems for high performers', '🏋️', 'Personal Growth', 17200),
('Financial Fitness', 'Your financial health matters. Fix it here.', '💪', 'Finance', 12400),
('Startup Founders', 'Build, launch and scale your startup', '🚀', 'Business', 8700)
ON CONFLICT DO NOTHING;

-- ══════════════════════════════════════════════════════
-- RLS Policies
-- ══════════════════════════════════════════════════════
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_saves ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_sessions ENABLE ROW LEVEL SECURITY;

-- Posts: anyone can read, owner can write
CREATE POLICY "posts_read" ON posts FOR SELECT USING (is_visible = true);
CREATE POLICY "posts_insert" ON posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "posts_delete" ON posts FOR DELETE USING (auth.uid() = user_id);

-- Groups: anyone can read
CREATE POLICY "groups_read" ON groups FOR SELECT USING (is_active = true);

-- Live: anyone can read active sessions
CREATE POLICY "live_read" ON live_sessions FOR SELECT USING (is_active = true);

-- ══════════════════════════════════════════════════════════════════
-- Performance indexes for social tables (missing from initial schema)
-- Run this block if you already ran migration_social.sql without indexes
-- ══════════════════════════════════════════════════════════════════

-- Posts feed — the two most common filters
CREATE INDEX IF NOT EXISTS idx_posts_visible_created   ON posts(is_visible, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_visible_likes     ON posts(is_visible, likes_count DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_id           ON posts(user_id);

-- Likes — checked per-post per-user on every feed load
CREATE INDEX IF NOT EXISTS idx_post_likes_post_user    ON post_likes(post_id, user_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_user         ON post_likes(user_id);

-- Saves
CREATE INDEX IF NOT EXISTS idx_post_saves_post_user    ON post_saves(post_id, user_id);

-- Comments count lookup
CREATE INDEX IF NOT EXISTS idx_post_comments_post      ON post_comments(post_id);

-- Follows — used for "following" tab feed
CREATE INDEX IF NOT EXISTS idx_follows_follower        ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following       ON follows(following_id);

-- Profiles — joined on every feed row
CREATE INDEX IF NOT EXISTS idx_profiles_id             ON profiles(id);

SELECT '✅ Social performance indexes applied!' AS result;
