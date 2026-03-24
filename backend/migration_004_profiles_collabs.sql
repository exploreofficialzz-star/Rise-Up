-- ═══════════════════════════════════════════════════════════════════
-- RiseUp — Migration 004: Profile fields + Collaboration tables
-- Run in: Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════

-- 1. Add bio and status fields to profiles (if missing)
-- ─────────────────────────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'bio'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN bio TEXT DEFAULT '';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN status TEXT DEFAULT '';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'followers_count'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN followers_count INTEGER DEFAULT 0;
    ALTER TABLE public.profiles ADD COLUMN following_count INTEGER DEFAULT 0;
  END IF;
END $$;


-- 2. COLLABORATIONS — Income goal partnerships
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS collaborations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT DEFAULT '',
  income_type     TEXT NOT NULL DEFAULT 'other',
  emoji           TEXT DEFAULT '🤝',
  tag             TEXT DEFAULT '',
  potential_revenue TEXT DEFAULT '',
  roles_needed    INTEGER DEFAULT 1,
  roles_filled    INTEGER DEFAULT 0,
  max_members     INTEGER DEFAULT 5,
  status          TEXT NOT NULL DEFAULT 'open',
  -- status: open | in_progress | completed | closed
  revenue_split   TEXT DEFAULT 'equal',  -- equal | by_role | negotiable
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE collaborations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view open collabs"
  ON collaborations FOR SELECT USING (status = 'open' OR owner_id = auth.uid());
CREATE POLICY "Owners manage their collabs"
  ON collaborations FOR ALL USING (owner_id = auth.uid());

CREATE INDEX idx_collabs_owner ON collaborations(owner_id);
CREATE INDEX idx_collabs_status ON collaborations(status);
CREATE INDEX idx_collabs_type ON collaborations(income_type);


-- 3. COLLABORATION ROLES — What each collab needs
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS collaboration_roles (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  collaboration_id  UUID NOT NULL REFERENCES collaborations(id) ON DELETE CASCADE,
  role_name         TEXT NOT NULL,
  role_description  TEXT DEFAULT '',
  is_filled         BOOLEAN DEFAULT FALSE,
  filled_by         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE collaboration_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view collab roles"
  ON collaboration_roles FOR SELECT USING (true);
CREATE POLICY "Collab owners manage roles"
  ON collaboration_roles FOR ALL USING (
    collaboration_id IN (SELECT id FROM collaborations WHERE owner_id = auth.uid())
  );


-- 4. COLLABORATION MEMBERS — Who's in each collab
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS collaboration_members (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  collaboration_id  UUID NOT NULL REFERENCES collaborations(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id           UUID REFERENCES collaboration_roles(id) ON DELETE SET NULL,
  status            TEXT DEFAULT 'pending', -- pending | accepted | rejected
  joined_at         TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(collaboration_id, user_id)
);

ALTER TABLE collaboration_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Members can see their collaborations"
  ON collaboration_members FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Owners can manage members"
  ON collaboration_members FOR ALL USING (
    collaboration_id IN (SELECT id FROM collaborations WHERE owner_id = auth.uid())
    OR user_id = auth.uid()
  );


-- 5. Post liked_by index for fast liked posts lookup
-- ─────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_post_likes_user ON post_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_post ON post_likes(post_id);


-- 6. Agent sessions table for conversation persistence
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_sessions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workflow_id UUID REFERENCES workflows(id) ON DELETE SET NULL,
  title       TEXT DEFAULT 'Agent Session',
  task        TEXT DEFAULT '',
  result_snapshot JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE agent_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their agent sessions"
  ON agent_sessions FOR ALL USING (user_id = auth.uid());

CREATE INDEX idx_agent_sessions_user ON agent_sessions(user_id);


-- 7. Auto-update timestamps trigger (reuse function from workflow migration)
-- ─────────────────────────────────────────────────────────────────
CREATE TRIGGER collaborations_updated_at
  BEFORE UPDATE ON collaborations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Done!
SELECT 'Migration 004 complete ✅' as result;
