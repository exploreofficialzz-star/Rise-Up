-- ═══════════════════════════════════════════════════════════════════
-- RiseUp — AI Workflow Engine Database Migration
-- Run in: Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════

-- 1. WORKFLOWS — Main workflow record per income goal
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workflows (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  goal                TEXT NOT NULL,
  income_type         TEXT NOT NULL DEFAULT 'other',
  -- income_type options: youtube, freelance, ecommerce, physical,
  --                      affiliate, content, service, other
  status              TEXT NOT NULL DEFAULT 'active',
  -- status options: active, paused, completed, archived
  currency            TEXT NOT NULL DEFAULT 'NGN',
  total_revenue       NUMERIC(12,2) NOT NULL DEFAULT 0,
  progress_percent    INTEGER NOT NULL DEFAULT 0,
  viability_score     INTEGER DEFAULT 75,
  realistic_timeline  TEXT DEFAULT '',
  potential_min       NUMERIC(12,2) DEFAULT 0,
  potential_max       NUMERIC(12,2) DEFAULT 0,
  honest_warning      TEXT DEFAULT '',
  research_snapshot   JSONB DEFAULT '{}',   -- full AI research stored
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their workflows"
  ON workflows FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_workflows_user ON workflows(user_id);
CREATE INDEX idx_workflows_status ON workflows(status);


-- 2. WORKFLOW STEPS — Individual tasks within a workflow
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workflow_steps (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id   UUID NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_index   INTEGER NOT NULL DEFAULT 1,
  title         TEXT NOT NULL,
  description   TEXT DEFAULT '',
  step_type     TEXT NOT NULL DEFAULT 'manual',
  -- step_type: automated (AI does it) | manual (user does it) | outsource
  time_minutes  INTEGER DEFAULT 30,
  tools         JSONB DEFAULT '[]',          -- array of tool names
  status        TEXT NOT NULL DEFAULT 'pending',
  -- status: pending | in_progress | done | skipped
  ai_output     TEXT DEFAULT '',             -- AI-generated content for this step
  completed_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workflow_steps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their workflow steps"
  ON workflow_steps FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_workflow_steps_workflow ON workflow_steps(workflow_id);
CREATE INDEX idx_workflow_steps_status ON workflow_steps(status);


-- 3. WORKFLOW TOOLS — Free & paid tools per workflow
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workflow_tools (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id       UUID NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  url               TEXT DEFAULT '',
  purpose           TEXT DEFAULT '',
  category          TEXT DEFAULT '',
  -- category: design, analytics, recording, editing, writing,
  --           communication, automation, other
  is_free           BOOLEAN NOT NULL DEFAULT TRUE,
  cost_monthly      NUMERIC(8,2) DEFAULT 0,
  unlock_at_revenue NUMERIC(12,2) DEFAULT 0,  -- suggest upgrade at this revenue level
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workflow_tools ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view tools for their workflows"
  ON workflow_tools FOR ALL
  USING (
    workflow_id IN (
      SELECT id FROM workflows WHERE user_id = auth.uid()
    )
  );

CREATE INDEX idx_workflow_tools_workflow ON workflow_tools(workflow_id);
CREATE INDEX idx_workflow_tools_free ON workflow_tools(is_free);


-- 4. WORKFLOW REVENUE — Revenue logs per workflow
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workflow_revenue (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id  UUID NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount       NUMERIC(12,2) NOT NULL,
  currency     TEXT NOT NULL DEFAULT 'NGN',
  source       TEXT DEFAULT '',
  note         TEXT DEFAULT '',
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workflow_revenue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their workflow revenue"
  ON workflow_revenue FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_workflow_revenue_workflow ON workflow_revenue(workflow_id);
CREATE INDEX idx_workflow_revenue_user ON workflow_revenue(user_id);
CREATE INDEX idx_workflow_revenue_date ON workflow_revenue(created_at);


-- 5. Add workflow_id to existing earnings table (if needed)
-- ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'earnings' AND column_name = 'workflow_id'
  ) THEN
    ALTER TABLE earnings ADD COLUMN workflow_id UUID REFERENCES workflows(id) ON DELETE SET NULL;
  END IF;
END $$;


-- 6. Useful functions
-- ─────────────────────────────────────────────────────────────────

-- Get workflow summary stats for a user
CREATE OR REPLACE FUNCTION get_workflow_stats(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'total_workflows',    COUNT(*),
    'active_workflows',   COUNT(*) FILTER (WHERE status = 'active'),
    'completed_workflows', COUNT(*) FILTER (WHERE status = 'completed'),
    'total_revenue',      COALESCE(SUM(total_revenue), 0),
    'avg_progress',       COALESCE(AVG(progress_percent), 0)
  )
  INTO result
  FROM workflows
  WHERE user_id = p_user_id;
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Auto-update timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER workflows_updated_at
  BEFORE UPDATE ON workflows
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER workflow_steps_updated_at
  BEFORE UPDATE ON workflow_steps
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
