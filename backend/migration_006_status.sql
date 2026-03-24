-- ══════════════════════════════════════════════════════════════
-- RiseUp Migration 006 — User Status / Stories
-- Run in Supabase SQL Editor
-- ══════════════════════════════════════════════════════════════

-- Status updates (stories) table
CREATE TABLE IF NOT EXISTS user_status (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content          TEXT,
  media_url        TEXT,
  media_type       TEXT DEFAULT 'text',   -- text | image | video | link
  link_url         TEXT,
  link_title       TEXT,
  background_color TEXT DEFAULT '#6C5CE7',
  expires_at       TIMESTAMPTZ NOT NULL,
  is_active        BOOLEAN DEFAULT TRUE,
  views_count      INTEGER DEFAULT 0,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Status views tracking
CREATE TABLE IF NOT EXISTS status_views (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  status_id  UUID NOT NULL REFERENCES user_status(id) ON DELETE CASCADE,
  viewer_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(status_id, viewer_id)
);

-- Enable RLS
ALTER TABLE user_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE status_views ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='status_own' AND tablename='user_status') THEN
    CREATE POLICY status_own   ON user_status FOR ALL USING (auth.uid() = user_id);
    CREATE POLICY status_read  ON user_status FOR SELECT USING (is_active = true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='views_own' AND tablename='status_views') THEN
    CREATE POLICY views_own ON status_views FOR ALL USING (auth.uid() = viewer_id);
  END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_status_user    ON user_status(user_id);
CREATE INDEX IF NOT EXISTS idx_status_active  ON user_status(is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_views_status   ON status_views(status_id);
CREATE INDEX IF NOT EXISTS idx_views_viewer   ON status_views(viewer_id);

-- Auto-deactivate expired statuses (call this via a cron or on read)
CREATE OR REPLACE FUNCTION expire_old_statuses()
RETURNS void AS $$
  UPDATE user_status SET is_active = FALSE
  WHERE is_active = TRUE AND expires_at < NOW();
$$ LANGUAGE SQL;

-- Storage bucket policy note:
-- Create bucket "status-media" as PUBLIC in Supabase Storage dashboard

SELECT '✅ Migration 006 complete — User Status / Stories ready!' AS result;
