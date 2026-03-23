-- ═══════════════════════════════════════════════════════════
-- RiseUp — Migration 005: Superpower Features
-- Income Memory · Market Pulse · Contracts · CRM
-- Challenges · Portfolio
--
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ── Income Memory Events ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS income_memory_events (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type          TEXT NOT NULL,
  title               TEXT NOT NULL,
  amount_usd          NUMERIC(12,2) DEFAULT 0,
  platform            TEXT,
  skill_used          TEXT,
  time_taken_minutes  INTEGER,
  note                TEXT,
  outcome             TEXT DEFAULT 'success',
  created_at          TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE income_memory_events ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='memory_own' AND tablename='income_memory_events') THEN
    CREATE POLICY memory_own ON income_memory_events FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_memory_user ON income_memory_events(user_id);
CREATE INDEX IF NOT EXISTS idx_memory_type ON income_memory_events(user_id, event_type);


-- ── Contracts ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS contracts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  contract_number TEXT UNIQUE,
  client_name     TEXT NOT NULL,
  client_email    TEXT,
  service_type    TEXT NOT NULL,
  deliverables    JSONB DEFAULT '[]',
  amount_usd      NUMERIC(12,2) NOT NULL,
  payment_terms   TEXT DEFAULT '50% upfront, 50% on delivery',
  duration_days   INTEGER DEFAULT 14,
  status          TEXT DEFAULT 'draft',
  contract_text   TEXT,
  ai_data         JSONB DEFAULT '{}',
  signed_at       TIMESTAMPTZ,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='contracts_own' AND tablename='contracts') THEN
    CREATE POLICY contracts_own ON contracts FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_contracts_user ON contracts(user_id);


-- ── Invoices ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoices (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invoice_number TEXT UNIQUE,
  contract_id    UUID REFERENCES contracts(id) ON DELETE SET NULL,
  client_name    TEXT NOT NULL,
  client_email   TEXT,
  amount_usd     NUMERIC(12,2) NOT NULL,
  due_date       TIMESTAMPTZ,
  status         TEXT DEFAULT 'draft',
  invoice_data   JSONB DEFAULT '{}',
  paid_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='invoices_own' AND tablename='invoices') THEN
    CREATE POLICY invoices_own ON invoices FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_invoices_user ON invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(user_id, status);


-- ── CRM Clients ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm_clients (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  email            TEXT,
  phone            TEXT,
  platform         TEXT,
  service_interest TEXT,
  budget_usd       NUMERIC(12,2),
  notes            TEXT,
  status           TEXT DEFAULT 'prospect',
  next_follow_up   DATE,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE crm_clients ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='crm_own' AND tablename='crm_clients') THEN
    CREATE POLICY crm_own ON crm_clients FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_crm_user ON crm_clients(user_id);
CREATE INDEX IF NOT EXISTS idx_crm_status ON crm_clients(user_id, status);
CREATE INDEX IF NOT EXISTS idx_crm_followup ON crm_clients(user_id, next_follow_up);


-- ── CRM Interactions ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm_interactions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id        UUID NOT NULL REFERENCES crm_clients(id) ON DELETE CASCADE,
  interaction_type TEXT NOT NULL,
  summary          TEXT NOT NULL,
  outcome          TEXT,
  next_action      TEXT,
  next_action_date DATE,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE crm_interactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='interactions_own' AND tablename='crm_interactions') THEN
    CREATE POLICY interactions_own ON crm_interactions FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_interactions_client ON crm_interactions(client_id);


-- ── Income Challenges ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS income_challenges (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title          TEXT NOT NULL,
  challenge_type TEXT NOT NULL,
  emoji          TEXT DEFAULT '🎯',
  target_usd     NUMERIC(12,2) NOT NULL,
  current_usd    NUMERIC(12,2) DEFAULT 0,
  duration_days  INTEGER NOT NULL,
  start_date     DATE NOT NULL,
  end_date       DATE NOT NULL,
  status         TEXT DEFAULT 'active',
  daily_plan     JSONB DEFAULT '[]',
  milestones     JSONB DEFAULT '[]',
  plan_data      JSONB DEFAULT '{}',
  current_day    INTEGER DEFAULT 1,
  streak         INTEGER DEFAULT 0,
  progress_pct   NUMERIC(5,2) DEFAULT 0,
  last_checkin   DATE,
  completed_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE income_challenges ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='challenges_own' AND tablename='income_challenges') THEN
    CREATE POLICY challenges_own ON income_challenges FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_challenges_user ON income_challenges(user_id, status);


-- ── Challenge Check-ins ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS challenge_checkins (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id    UUID NOT NULL REFERENCES income_challenges(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day_number      INTEGER NOT NULL,
  action_taken    TEXT NOT NULL,
  amount_earned_usd NUMERIC(12,2) DEFAULT 0,
  note            TEXT,
  checkin_date    DATE NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE challenge_checkins ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='checkins_own' AND tablename='challenge_checkins') THEN
    CREATE POLICY checkins_own ON challenge_checkins FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_checkins_challenge ON challenge_checkins(challenge_id);


-- ── Portfolio Items ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS portfolio_items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workflow_id      UUID REFERENCES workflows(id) ON DELETE SET NULL,
  title            TEXT NOT NULL,
  service_type     TEXT,
  client_industry  TEXT,
  challenge_solved TEXT,
  result_achieved  TEXT,
  amount_usd       NUMERIC(12,2),
  platform_used    TEXT,
  skills_used      JSONB DEFAULT '[]',
  duration_days    INTEGER,
  testimonial      TEXT,
  case_study_data  JSONB DEFAULT '{}',
  is_public        BOOLEAN DEFAULT TRUE,
  source           TEXT DEFAULT 'manual',
  created_at       TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE portfolio_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='portfolio_own' AND tablename='portfolio_items') THEN
    CREATE POLICY portfolio_own ON portfolio_items FOR ALL USING (auth.uid() = user_id);
    CREATE POLICY portfolio_public ON portfolio_items FOR SELECT USING (is_public = true);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_portfolio_user ON portfolio_items(user_id);
CREATE INDEX IF NOT EXISTS idx_portfolio_public ON portfolio_items(is_public, created_at DESC);


-- ── Feature Usage Tracking (for free tier limits) ────────────
CREATE TABLE IF NOT EXISTS feature_usage (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  feature     TEXT NOT NULL,
  usage_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  count       INTEGER DEFAULT 0,
  UNIQUE(user_id, feature, usage_date)
);
ALTER TABLE feature_usage ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='usage_own' AND tablename='feature_usage') THEN
    CREATE POLICY usage_own ON feature_usage FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_usage_user_date ON feature_usage(user_id, usage_date);


-- ── Ad Impressions + Actions ──────────────────────────────────
CREATE TABLE IF NOT EXISTS ad_impressions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ad_id      TEXT NOT NULL,
  placement  TEXT NOT NULL,
  screen     TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ad_actions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ad_id      TEXT NOT NULL,
  action     TEXT NOT NULL,
  placement  TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE ad_impressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ad_actions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='impressions_own' AND tablename='ad_impressions') THEN
    CREATE POLICY impressions_own ON ad_impressions FOR ALL USING (auth.uid() = user_id);
    CREATE POLICY actions_own ON ad_actions FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

SELECT '✅ Migration 005 complete — All Superpower Features ready!' AS result;
