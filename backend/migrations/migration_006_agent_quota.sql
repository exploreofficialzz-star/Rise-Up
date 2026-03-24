-- Migration: Agent Run Quota Table
-- Run this in your Supabase SQL editor

CREATE TABLE IF NOT EXISTS agent_run_quota (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    quota_key   TEXT NOT NULL UNIQUE,          -- "agent_runs:{user_id}:{date}"
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    runs_used   INTEGER NOT NULL DEFAULT 1,
    quota_limit INTEGER NOT NULL DEFAULT 3,
    quota_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast per-user daily lookups
CREATE INDEX IF NOT EXISTS idx_agent_quota_key     ON agent_run_quota (quota_key);
CREATE INDEX IF NOT EXISTS idx_agent_quota_user    ON agent_run_quota (user_id);
CREATE INDEX IF NOT EXISTS idx_agent_quota_date    ON agent_run_quota (quota_date);

-- Auto-update timestamp
CREATE OR REPLACE FUNCTION update_agent_quota_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER agent_quota_updated_at
    BEFORE UPDATE ON agent_run_quota
    FOR EACH ROW EXECUTE FUNCTION update_agent_quota_timestamp();

-- RLS: users can only see their own quota
ALTER TABLE agent_run_quota ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own quota"
    ON agent_run_quota FOR SELECT
    USING (auth.uid() = user_id);

-- Service role bypasses RLS (backend writes always work)
