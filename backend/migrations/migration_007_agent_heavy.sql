-- Migration 007: Agent Documents + Scheduled Posts + Quota Table
-- Run in Supabase SQL Editor

-- ── Agent Run Quota ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_run_quota (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    quota_key   TEXT NOT NULL UNIQUE,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    runs_used   INTEGER NOT NULL DEFAULT 1,
    quota_limit INTEGER NOT NULL DEFAULT 3,
    quota_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_quota_key  ON agent_run_quota (quota_key);
CREATE INDEX IF NOT EXISTS idx_quota_user ON agent_run_quota (user_id);
ALTER TABLE agent_run_quota ENABLE ROW LEVEL SECURITY;
CREATE POLICY "quota_own" ON agent_run_quota FOR SELECT USING (auth.uid() = user_id);

-- ── Agent Generated Documents ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_documents (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    workflow_id UUID REFERENCES workflows(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    doc_type    TEXT NOT NULL DEFAULT 'document',  -- contract|invoice|proposal|pitch_deck
    content     TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agent_docs_user     ON agent_documents (user_id);
CREATE INDEX IF NOT EXISTS idx_agent_docs_workflow ON agent_documents (workflow_id);
ALTER TABLE agent_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "docs_own"    ON agent_documents FOR ALL  USING (auth.uid() = user_id);

-- ── Scheduled Social Posts ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS scheduled_posts (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform    TEXT NOT NULL,                    -- twitter|linkedin|instagram
    content     TEXT NOT NULL,
    schedule_at TIMESTAMPTZ,
    status      TEXT NOT NULL DEFAULT 'pending', -- pending|posted|failed|cancelled
    post_url    TEXT,
    error       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_scheduled_posts_user   ON scheduled_posts (user_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_posts_status ON scheduled_posts (status);
ALTER TABLE scheduled_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "posts_own" ON scheduled_posts FOR ALL USING (auth.uid() = user_id);

-- ── User Social Tokens (encrypted, per user) ─────────────────────
CREATE TABLE IF NOT EXISTS user_social_tokens (
    id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform     TEXT NOT NULL,          -- twitter|linkedin
    access_token TEXT NOT NULL,
    token_data   JSONB DEFAULT '{}',     -- extra fields (person_urn, refresh_token, etc.)
    expires_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, platform)
);
ALTER TABLE user_social_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tokens_own" ON user_social_tokens FOR ALL USING (auth.uid() = user_id);
