-- ══════════════════════════════════════════════════════════════════
-- RiseUp Migration 008 — Performance Indexes
-- Run in Supabase SQL Editor
-- Fixes full-table-scan slowness on social feed, likes, follows
-- ══════════════════════════════════════════════════════════════════

-- ── Posts feed ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_posts_visible_created   ON posts(is_visible, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_visible_likes     ON posts(is_visible, likes_count DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_id           ON posts(user_id);

-- ── Likes — checked per-post per-user on every feed load ──────────
CREATE INDEX IF NOT EXISTS idx_post_likes_post_user    ON post_likes(post_id, user_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_user         ON post_likes(user_id);

-- ── Saves ─────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_post_saves_post_user    ON post_saves(post_id, user_id);

-- ── Comments count lookup ─────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_post_comments_post      ON post_comments(post_id);

-- ── Follows — used for "following" tab feed ───────────────────────
CREATE INDEX IF NOT EXISTS idx_follows_follower        ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following       ON follows(following_id);

-- ── Profiles — joined on every feed row ──────────────────────────
CREATE INDEX IF NOT EXISTS idx_profiles_id             ON profiles(id);

-- ── Agent quota ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_agent_quota_user        ON agent_quota(user_id);

-- ── Notifications — unread lookup ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_notifs_user_unread      ON notifications(user_id, is_read, sent_at DESC);

-- ── Leaderboard ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_profiles_total_earned   ON profiles(total_earned DESC) WHERE total_earned > 0;

SELECT '✅ Migration 008 complete — Performance indexes applied!' AS result;
