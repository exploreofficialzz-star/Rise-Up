-- Migration 008: GrowthAI Intelligence Tables
-- Run in Supabase SQL Editor AFTER migrations 006 and 007

-- ── Earnings Tracker ─────────────────────────────────────────────
-- Tracks all income streams per user
CREATE TABLE IF NOT EXISTS earnings (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount      NUMERIC(12,2) NOT NULL,
    currency    TEXT NOT NULL DEFAULT 'USD',
    source      TEXT NOT NULL,          -- e.g. "Upwork", "YouTube", "Freelance"
    description TEXT,
    earned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_earnings_user    ON earnings (user_id);
CREATE INDEX IF NOT EXISTS idx_earnings_date    ON earnings (earned_at DESC);
ALTER TABLE earnings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "earnings_own" ON earnings FOR ALL USING (auth.uid() = user_id);

-- ── Contacts / Network ────────────────────────────────────────────
-- Stores prospects, partners, clients
CREATE TABLE IF NOT EXISTS contacts (
    id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    email             TEXT,
    phone             TEXT,
    title             TEXT,
    company           TEXT,
    relationship_type TEXT DEFAULT 'prospect',  -- prospect|client|partner|investor|mentor
    notes             TEXT,
    last_contacted_at TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts (user_id);
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "contacts_own" ON contacts FOR ALL USING (auth.uid() = user_id);

-- ── Opportunity Cache ─────────────────────────────────────────────
-- Caches scraped opportunities with AI scores to avoid re-scraping
CREATE TABLE IF NOT EXISTS opportunity_cache (
    id              TEXT PRIMARY KEY,       -- scraper-generated hash
    title           TEXT NOT NULL,
    description     TEXT,
    opp_type        TEXT,
    source          TEXT,
    source_url      TEXT,
    company_name    TEXT,
    location        TEXT DEFAULT 'Remote',
    is_remote       BOOLEAN DEFAULT TRUE,
    pay_amount      NUMERIC,
    pay_period      TEXT,
    required_skills TEXT[],
    posted_at       TIMESTAMPTZ,
    ai_match_score  INTEGER DEFAULT 0,
    ai_summary      TEXT,
    ai_risk_level   TEXT DEFAULT 'medium',
    ai_action_steps TEXT[],
    ai_time_to_earn TEXT,
    scraped_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);
CREATE INDEX IF NOT EXISTS idx_opp_cache_score   ON opportunity_cache (ai_match_score DESC);
CREATE INDEX IF NOT EXISTS idx_opp_cache_type    ON opportunity_cache (opp_type);
CREATE INDEX IF NOT EXISTS idx_opp_cache_expires ON opportunity_cache (expires_at);

-- Auto-purge expired cache entries (requires pg_cron or scheduled function)
-- Alternatively, your app handles this with expires_at checks.

-- ── Daily Plans ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_plans (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    plan_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    goal        TEXT,
    overview    TEXT,
    plan_data   JSONB NOT NULL DEFAULT '{}',
    tasks_count INTEGER DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, plan_date)
);
CREATE INDEX IF NOT EXISTS idx_daily_plans_user ON daily_plans (user_id, plan_date DESC);
ALTER TABLE daily_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plans_own" ON daily_plans FOR ALL USING (auth.uid() = user_id);

-- ── Extend profiles table with GrowthAI fields ───────────────────
-- Add columns if they don't already exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='profiles' AND column_name='target_monthly_income') THEN
        ALTER TABLE profiles ADD COLUMN target_monthly_income NUMERIC DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='profiles' AND column_name='interests') THEN
        ALTER TABLE profiles ADD COLUMN interests TEXT[] DEFAULT '{}';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='profiles' AND column_name='industries') THEN
        ALTER TABLE profiles ADD COLUMN industries TEXT[] DEFAULT '{}';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='profiles' AND column_name='preferred_work_type') THEN
        ALTER TABLE profiles ADD COLUMN preferred_work_type TEXT DEFAULT 'remote';
    END IF;
END $$;

-- ── Extend tasks table with daily_plan category ───────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tasks' AND column_name='category') THEN
        ALTER TABLE tasks ADD COLUMN category TEXT DEFAULT 'general';
    END IF;
END $$;
