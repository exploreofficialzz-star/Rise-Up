-- ============================================================
-- Migration 003: New Feature Tables
-- Streaks · Goals · Expenses/Budget · Achievements · Referrals · Notifications · Admin
-- ChAs Tech Group — RiseUp
-- ============================================================

-- ── 1. ADD COLUMNS TO PROFILES ──────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code     TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by       UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS current_streak    INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS longest_streak    INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_check_in     DATE,
  ADD COLUMN IF NOT EXISTS streak_frozen_at  DATE,
  ADD COLUMN IF NOT EXISTS xp_points         INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS level             INT DEFAULT 1,
  ADD COLUMN IF NOT EXISTS admin_note        TEXT;

-- Generate referral codes for all existing profiles
UPDATE public.profiles
SET referral_code = UPPER(SUBSTRING(MD5(id::text) FROM 1 FOR 8))
WHERE referral_code IS NULL;

-- Auto-generate referral code on new profile insert
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.referral_code IS NULL THEN
    NEW.referral_code := UPPER(SUBSTRING(MD5(NEW.id::text || NOW()::text) FROM 1 FOR 8));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_referral_code ON public.profiles;
CREATE TRIGGER set_referral_code
  BEFORE INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION generate_referral_code();

-- ── 2. STREAKS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_streaks (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  current_streak  INT DEFAULT 0,
  longest_streak  INT DEFAULT 0,
  last_check_in   DATE,
  total_check_ins INT DEFAULT 0,
  check_in_dates  DATE[] DEFAULT '{}',
  freeze_uses     INT DEFAULT 0,        -- streak shield uses
  max_freeze_uses INT DEFAULT 2,        -- max freezes allowed
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. GOALS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.goals (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT,
  goal_type       TEXT CHECK (goal_type IN (
    'savings', 'income', 'skill', 'debt_payoff', 'investment', 'emergency_fund', 'custom'
  )) DEFAULT 'savings',
  target_amount   NUMERIC(14,2),
  current_amount  NUMERIC(14,2) DEFAULT 0,
  currency        TEXT DEFAULT 'NGN',
  target_date     DATE,
  status          TEXT CHECK (status IN ('active', 'completed', 'paused', 'abandoned')) DEFAULT 'active',
  priority        TEXT CHECK (priority IN ('low', 'medium', 'high')) DEFAULT 'medium',
  ai_notes        TEXT,
  milestones      JSONB DEFAULT '[]',   -- [{percent:25, label:'Quarter way!', reached_at: null}]
  icon            TEXT DEFAULT '🎯',
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── 4. EXPENSES ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.expenses (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount      NUMERIC(12,2) NOT NULL,
  currency    TEXT DEFAULT 'NGN',
  category    TEXT CHECK (category IN (
    'food', 'transport', 'rent', 'utilities', 'entertainment',
    'clothing', 'health', 'education', 'savings', 'debt', 'business', 'other'
  )) DEFAULT 'other',
  description TEXT,
  spent_at    DATE DEFAULT CURRENT_DATE,
  is_recurring BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 5. BUDGETS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.budgets (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  month        TEXT NOT NULL,           -- 'YYYY-MM' e.g. '2026-03'
  category     TEXT NOT NULL,
  budget_amount NUMERIC(12,2) NOT NULL,
  currency     TEXT DEFAULT 'NGN',
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, month, category)
);

-- ── 6. ACHIEVEMENTS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.achievements (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key         TEXT UNIQUE NOT NULL,     -- e.g. 'first_task', 'streak_7'
  title       TEXT NOT NULL,
  description TEXT NOT NULL,
  icon        TEXT DEFAULT '🏆',
  category    TEXT CHECK (category IN (
    'tasks', 'earnings', 'skills', 'streak', 'community', 'premium', 'referral', 'milestone'
  )) DEFAULT 'milestone',
  xp_reward   INT DEFAULT 50,
  is_secret   BOOLEAN DEFAULT FALSE,
  unlock_condition JSONB DEFAULT '{}',  -- {type:'streak', value:7}
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_achievements (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_id UUID NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  unlocked_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, achievement_id)
);

-- Seed achievement definitions
INSERT INTO public.achievements (key, title, description, icon, category, xp_reward, unlock_condition) VALUES
  ('first_login',       'Welcome to RiseUp!',       'You took the first step 🚀',                     '🌱', 'milestone', 10,  '{"type":"login","value":1}'),
  ('onboarding_done',   'Know Thyself',             'Completed your wealth profile',                   '🧠', 'milestone', 50,  '{"type":"onboarding","value":true}'),
  ('first_task',        'Action Taker',             'Completed your first income task',                '✅', 'tasks',     75,  '{"type":"tasks_completed","value":1}'),
  ('tasks_5',           'Getting Momentum',         'Completed 5 income tasks',                        '💪', 'tasks',     150, '{"type":"tasks_completed","value":5}'),
  ('tasks_10',          'Task Machine',             'Completed 10 income tasks',                       '⚡', 'tasks',     250, '{"type":"tasks_completed","value":10}'),
  ('tasks_25',          'Unstoppable',              'Completed 25 income tasks',                       '🔥', 'tasks',     500, '{"type":"tasks_completed","value":25}'),
  ('first_earning',     'First Money',              'Logged your very first income',                   '💰', 'earnings',  100, '{"type":"total_earned","value":1}'),
  ('earned_10k_ngn',    '₦10K Club',                'Earned ₦10,000 through RiseUp',                  '💵', 'earnings',  200, '{"type":"total_earned_ngn","value":10000}'),
  ('earned_50k_ngn',    '₦50K Achiever',            'Earned ₦50,000 through RiseUp',                  '💸', 'earnings',  400, '{"type":"total_earned_ngn","value":50000}'),
  ('earned_100k_ngn',   '₦100K Boss',               'Earned ₦100,000 through RiseUp',                 '🤑', 'earnings',  750, '{"type":"total_earned_ngn","value":100000}'),
  ('earned_500k_ngn',   'Half Million Club',        'Earned ₦500,000 through RiseUp',                 '👑', 'earnings',  1500,'{"type":"total_earned_ngn","value":500000}'),
  ('streak_3',          '3-Day Streak',             'Checked in 3 days in a row',                     '🔥', 'streak',    30,  '{"type":"streak","value":3}'),
  ('streak_7',          'Week Warrior',             'Checked in 7 days straight',                     '⚡', 'streak',    100, '{"type":"streak","value":7}'),
  ('streak_14',         'Two-Week Champion',        'Checked in 14 days straight',                    '🏅', 'streak',    200, '{"type":"streak","value":14}'),
  ('streak_30',         'Iron Discipline',          'Checked in 30 days straight',                    '🏆', 'streak',    500, '{"type":"streak","value":30}'),
  ('streak_100',        'Centurion',                '100-day check-in streak',                        '💎', 'streak',    1000,'{"type":"streak","value":100}'),
  ('first_skill',       'Always Learning',          'Enrolled in your first skill module',             '📚', 'skills',    75,  '{"type":"skills_enrolled","value":1}'),
  ('skill_complete',    'Skill Unlocked',           'Completed a full skill module',                   '🎓', 'skills',    300, '{"type":"skills_completed","value":1}'),
  ('skills_3',          'Knowledge Hunter',         'Completed 3 skill modules',                      '🧩', 'skills',    600, '{"type":"skills_completed","value":3}'),
  ('first_post',        'Voice of the Community',  'Made your first community post',                  '📢', 'community', 50,  '{"type":"posts","value":1}'),
  ('first_referral',    'Wealth Spreader',          'Referred your first friend to RiseUp',           '🤝', 'referral',  200, '{"type":"referrals","value":1}'),
  ('referrals_5',       'Growth Agent',             'Referred 5 friends to RiseUp',                   '🚀', 'referral',  500, '{"type":"referrals","value":5}'),
  ('went_premium',      'Premium Member',           'Upgraded to RiseUp Premium',                     '⭐', 'premium',   300, '{"type":"premium","value":true}'),
  ('first_goal',        'Goal Setter',              'Created your first financial goal',               '🎯', 'milestone', 50,  '{"type":"goals","value":1}'),
  ('goal_complete',     'Goal Crusher',             'Completed a financial goal',                     '🏁', 'milestone', 300, '{"type":"goals_completed","value":1}'),
  ('budget_master',     'Budget Master',            'Set budgets for all spending categories',         '📊', 'milestone', 150, '{"type":"budgets","value":5}'),
  ('level_5',           'Level 5',                 'Reached Level 5 on RiseUp',                      '⬆️', 'milestone', 100, '{"type":"level","value":5}'),
  ('level_10',          'Level 10',                'Reached Level 10 on RiseUp',                     '🌟', 'milestone', 250, '{"type":"level","value":10}'),
  ('shared_win',        'Inspire Others',           'Shared a milestone on social media',             '📲', 'community', 50,  '{"type":"shares","value":1}')
ON CONFLICT (key) DO NOTHING;

-- ── 7. REFERRALS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.referrals (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referrer_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referred_id     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  referral_code   TEXT NOT NULL,
  referred_email  TEXT,
  status          TEXT CHECK (status IN ('pending','signed_up','completed','rewarded')) DEFAULT 'pending',
  referrer_reward TEXT,                 -- 'premium_7_days'
  referred_reward TEXT,                 -- 'premium_3_days'
  rewarded_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  completed_at    TIMESTAMPTZ
);

-- ── 8. FCM TOKENS (Push Notifications) ───────────────────────
CREATE TABLE IF NOT EXISTS public.fcm_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token       TEXT NOT NULL,
  platform    TEXT CHECK (platform IN ('android','ios','web')) DEFAULT 'android',
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, token)
);

-- ── 9. NOTIFICATIONS LOG ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  type        TEXT CHECK (type IN (
    'streak_reminder','task_reminder','achievement','payment',
    'referral','goal_milestone','weekly_report','system'
  )) DEFAULT 'system',
  data        JSONB DEFAULT '{}',
  is_read     BOOLEAN DEFAULT FALSE,
  sent_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ── 10. SHARES LOG ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.share_logs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  share_type  TEXT NOT NULL,   -- 'milestone','achievement','referral','skill_certificate'
  content     TEXT,
  platform    TEXT,            -- 'whatsapp','twitter','instagram','copy_link'
  shared_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ── RLS POLICIES ─────────────────────────────────────────────
ALTER TABLE public.user_streaks      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goals             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fcm_tokens        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.share_logs        ENABLE ROW LEVEL SECURITY;

-- Achievements definitions: public read
ALTER TABLE public.achievements      ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can read achievements"
  ON public.achievements FOR SELECT USING (true);

-- User-owned tables
CREATE POLICY "Users own their streaks"
  ON public.user_streaks FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their goals"
  ON public.goals FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their expenses"
  ON public.expenses FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their budgets"
  ON public.budgets FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their achievements"
  ON public.user_achievements FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their fcm tokens"
  ON public.fcm_tokens FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their notifications"
  ON public.notifications FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users own their share logs"
  ON public.share_logs FOR ALL USING (auth.uid() = user_id);

-- Referrals: referrer or referred can see their rows
CREATE POLICY "Users see their referrals"
  ON public.referrals FOR SELECT
  USING (auth.uid() = referrer_id OR auth.uid() = referred_id);
CREATE POLICY "Users create referrals"
  ON public.referrals FOR INSERT WITH CHECK (auth.uid() = referrer_id);

-- ── HELPER RPC FUNCTIONS ─────────────────────────────────────

-- Check-in and update streak
CREATE OR REPLACE FUNCTION process_daily_checkin(uid UUID)
RETURNS JSONB AS $$
DECLARE
  streak_row public.user_streaks%ROWTYPE;
  today DATE := CURRENT_DATE;
  yesterday DATE := CURRENT_DATE - INTERVAL '1 day';
  new_streak INT;
  result JSONB;
BEGIN
  -- Get or create streak record
  INSERT INTO public.user_streaks (user_id) VALUES (uid)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO streak_row FROM public.user_streaks WHERE user_id = uid;

  -- Already checked in today
  IF streak_row.last_check_in = today THEN
    RETURN jsonb_build_object(
      'already_checked_in', true,
      'current_streak', streak_row.current_streak,
      'longest_streak', streak_row.longest_streak
    );
  END IF;

  -- Calculate new streak
  IF streak_row.last_check_in = yesterday THEN
    new_streak := streak_row.current_streak + 1;
  ELSIF streak_row.last_check_in IS NULL THEN
    new_streak := 1;
  ELSE
    -- Streak broken
    new_streak := 1;
  END IF;

  -- Update streak record
  UPDATE public.user_streaks SET
    current_streak  = new_streak,
    longest_streak  = GREATEST(longest_streak, new_streak),
    last_check_in   = today,
    total_check_ins = total_check_ins + 1,
    check_in_dates  = array_append(check_in_dates, today),
    updated_at      = NOW()
  WHERE user_id = uid;

  -- Update profile columns
  UPDATE public.profiles SET
    current_streak = new_streak,
    longest_streak = GREATEST(longest_streak, new_streak),
    last_check_in  = today,
    xp_points      = xp_points + 10,  -- 10 XP per check-in
    updated_at     = NOW()
  WHERE id = uid;

  RETURN jsonb_build_object(
    'already_checked_in', false,
    'current_streak', new_streak,
    'longest_streak', GREATEST(streak_row.longest_streak, new_streak),
    'is_new_record', new_streak > streak_row.longest_streak,
    'xp_earned', 10
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Unlock achievement and award XP
CREATE OR REPLACE FUNCTION unlock_achievement(uid UUID, ach_key TEXT)
RETURNS JSONB AS $$
DECLARE
  ach public.achievements%ROWTYPE;
  already_unlocked BOOLEAN;
BEGIN
  SELECT * INTO ach FROM public.achievements WHERE key = ach_key;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'reason', 'not_found'); END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.user_achievements ua
    JOIN public.achievements a ON ua.achievement_id = a.id
    WHERE ua.user_id = uid AND a.key = ach_key
  ) INTO already_unlocked;

  IF already_unlocked THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_unlocked');
  END IF;

  INSERT INTO public.user_achievements (user_id, achievement_id)
  VALUES (uid, ach.id);

  -- Award XP
  UPDATE public.profiles SET
    xp_points  = xp_points + ach.xp_reward,
    level      = GREATEST(1, (xp_points + ach.xp_reward) / 500 + 1),
    updated_at = NOW()
  WHERE id = uid;

  RETURN jsonb_build_object(
    'success', true,
    'achievement', jsonb_build_object(
      'key', ach.key, 'title', ach.title, 'icon', ach.icon, 'xp', ach.xp_reward
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get monthly expense summary vs budget
CREATE OR REPLACE FUNCTION get_monthly_summary(uid UUID, month_str TEXT)
RETURNS JSONB AS $$
DECLARE
  result JSONB;
BEGIN
  SELECT jsonb_agg(row_to_json(r)) INTO result
  FROM (
    SELECT
      e.category,
      COALESCE(SUM(e.amount), 0) AS spent,
      COALESCE(b.budget_amount, 0) AS budgeted,
      COALESCE(b.budget_amount, 0) - COALESCE(SUM(e.amount), 0) AS remaining
    FROM public.expenses e
    LEFT JOIN public.budgets b
      ON b.user_id = uid AND b.month = month_str AND b.category = e.category
    WHERE e.user_id = uid
      AND TO_CHAR(e.spent_at, 'YYYY-MM') = month_str
    GROUP BY e.category, b.budget_amount
  ) r;
  RETURN COALESCE(result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Process referral completion
CREATE OR REPLACE FUNCTION complete_referral(referred_uid UUID, ref_code TEXT)
RETURNS JSONB AS $$
DECLARE
  referrer_id UUID;
  referral_row public.referrals%ROWTYPE;
  premium_expires TIMESTAMPTZ;
BEGIN
  -- Find referrer by code
  SELECT id INTO referrer_id FROM public.profiles WHERE referral_code = ref_code;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'reason', 'invalid_code'); END IF;
  IF referrer_id = referred_uid THEN RETURN jsonb_build_object('success', false, 'reason', 'self_referral'); END IF;

  -- Check already referred
  IF EXISTS(SELECT 1 FROM public.referrals WHERE referred_id = referred_uid) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_referred');
  END IF;

  -- Create referral record
  INSERT INTO public.referrals (referrer_id, referred_id, referral_code, status, referrer_reward, referred_reward)
  VALUES (referrer_id, referred_uid, ref_code, 'rewarded', 'premium_7_days', 'premium_3_days');

  -- Give referred user 3 days premium
  premium_expires := NOW() + INTERVAL '3 days';
  UPDATE public.profiles SET
    subscription_tier       = 'premium',
    subscription_expires_at = GREATEST(COALESCE(subscription_expires_at, NOW()), premium_expires),
    referred_by             = referrer_id,
    updated_at              = NOW()
  WHERE id = referred_uid;

  -- Give referrer 7 days premium
  premium_expires := NOW() + INTERVAL '7 days';
  UPDATE public.profiles SET
    subscription_tier       = 'premium',
    subscription_expires_at = GREATEST(COALESCE(subscription_expires_at, NOW()), premium_expires),
    updated_at              = NOW()
  WHERE id = referrer_id;

  RETURN jsonb_build_object('success', true, 'referrer_id', referrer_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── INDEXES ─────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_goals_user_status     ON public.goals(user_id, status);
CREATE INDEX IF NOT EXISTS idx_expenses_user_month   ON public.expenses(user_id, spent_at DESC);
CREATE INDEX IF NOT EXISTS idx_budgets_user_month    ON public.budgets(user_id, month);
CREATE INDEX IF NOT EXISTS idx_user_ach_user         ON public.user_achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer    ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_code        ON public.referrals(referral_code);
CREATE INDEX IF NOT EXISTS idx_fcm_user_active       ON public.fcm_tokens(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_notifications_user    ON public.notifications(user_id, is_read, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_share_logs_user       ON public.share_logs(user_id);

-- ── GRANTS ───────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION process_daily_checkin TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION unlock_achievement     TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_monthly_summary    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION complete_referral      TO service_role;
GRANT SELECT ON public.achievements              TO authenticated, anon;
