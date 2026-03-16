-- ============================================================
-- RiseUp Database Schema
-- Owner: ChAs Tech Group
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- USERS & PROFILES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  phone TEXT,
  country TEXT DEFAULT 'NG',
  currency TEXT DEFAULT 'NGN',
  avatar_url TEXT,

  -- Onboarding data
  onboarding_completed BOOLEAN DEFAULT FALSE,
  wealth_type TEXT CHECK (wealth_type IN (
    'employee', 'creator', 'investor', 'trader',
    'business_owner', 'asset_builder', 'impact_leader'
  )),
  learning_style TEXT CHECK (learning_style IN ('visual', 'reading', 'hands_on', 'mixed')),
  risk_tolerance TEXT CHECK (risk_tolerance IN ('low', 'medium', 'high')),

  -- Financial snapshot
  monthly_income NUMERIC(12,2) DEFAULT 0,
  income_sources TEXT[] DEFAULT '{}',
  monthly_expenses NUMERIC(12,2) DEFAULT 0,
  survival_mode BOOLEAN DEFAULT TRUE,

  -- Goals
  short_term_goal TEXT,
  long_term_goal TEXT,
  ambitions TEXT,

  -- Skills & health
  current_skills TEXT[] DEFAULT '{}',
  health_energy TEXT CHECK (health_energy IN ('low', 'medium', 'high')) DEFAULT 'medium',
  obstacles TEXT,

  -- Subscription
  subscription_tier TEXT CHECK (subscription_tier IN ('free', 'premium')) DEFAULT 'free',
  subscription_expires_at TIMESTAMPTZ,
  total_earned NUMERIC(12,2) DEFAULT 0,

  -- AI memory
  ai_context JSONB DEFAULT '{}',
  stage TEXT CHECK (stage IN ('survival', 'earning', 'growing', 'wealth')) DEFAULT 'survival',

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- CONVERSATIONS & MESSAGES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT DEFAULT 'New Conversation',
  ai_model_used TEXT DEFAULT 'groq',
  message_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('user', 'assistant', 'system')) NOT NULL,
  content TEXT NOT NULL,
  ai_model TEXT,
  metadata JSONB DEFAULT '{}',
  tokens_used INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TASKS (Income opportunities)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT CHECK (category IN (
    'freelance', 'microtask', 'gig', 'trade', 'sale',
    'content', 'local', 'digital', 'affiliate'
  )) NOT NULL,
  difficulty TEXT CHECK (difficulty IN ('easy', 'medium', 'hard')) DEFAULT 'easy',
  estimated_hours NUMERIC(5,2),
  estimated_earnings NUMERIC(12,2),
  actual_earnings NUMERIC(12,2) DEFAULT 0,
  currency TEXT DEFAULT 'NGN',
  platform TEXT,
  platform_url TEXT,
  steps JSONB DEFAULT '[]',
  status TEXT CHECK (status IN ('suggested', 'accepted', 'in_progress', 'completed', 'skipped')) DEFAULT 'suggested',
  ai_generated BOOLEAN DEFAULT TRUE,
  ai_reasoning TEXT,
  deadline TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- SKILL MODULES (Earn while learning)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.skill_modules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL,
  duration_days INT DEFAULT 7,
  difficulty TEXT CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')) DEFAULT 'beginner',
  income_potential TEXT,
  is_premium BOOLEAN DEFAULT FALSE,
  lessons JSONB DEFAULT '[]',
  tags TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_skill_enrollments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  module_id UUID NOT NULL REFERENCES public.skill_modules(id) ON DELETE CASCADE,
  status TEXT CHECK (status IN ('enrolled', 'in_progress', 'completed', 'dropped')) DEFAULT 'enrolled',
  progress_percent INT DEFAULT 0,
  current_lesson INT DEFAULT 0,
  lessons_completed INT DEFAULT 0,
  earnings_from_skill NUMERIC(12,2) DEFAULT 0,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  UNIQUE(user_id, module_id)
);

-- ============================================================
-- WEALTH ROADMAP
-- ============================================================
CREATE TABLE IF NOT EXISTS public.roadmaps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  current_stage TEXT CHECK (current_stage IN ('immediate_income', 'skill_growth', 'long_term_wealth')) DEFAULT 'immediate_income',
  stage_1_milestones JSONB DEFAULT '[]',
  stage_2_milestones JSONB DEFAULT '[]',
  stage_3_milestones JSONB DEFAULT '[]',
  overall_progress INT DEFAULT 0,
  ai_notes TEXT,
  next_review_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.milestones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  roadmap_id UUID NOT NULL REFERENCES public.roadmaps(id) ON DELETE CASCADE,
  stage INT NOT NULL CHECK (stage IN (1, 2, 3)),
  title TEXT NOT NULL,
  description TEXT,
  target_amount NUMERIC(12,2),
  achieved_amount NUMERIC(12,2) DEFAULT 0,
  target_date TIMESTAMPTZ,
  status TEXT CHECK (status IN ('pending', 'in_progress', 'completed')) DEFAULT 'pending',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- PAYMENTS & SUBSCRIPTIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  flutterwave_tx_ref TEXT UNIQUE,
  flutterwave_tx_id TEXT,
  amount NUMERIC(12,2) NOT NULL,
  currency TEXT NOT NULL,
  payment_type TEXT CHECK (payment_type IN ('subscription', 'feature_unlock', 'micro_payment')) NOT NULL,
  plan TEXT CHECK (plan IN ('monthly', 'yearly', 'feature')) DEFAULT 'monthly',
  status TEXT CHECK (status IN ('pending', 'successful', 'failed', 'refunded')) DEFAULT 'pending',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- FEATURE UNLOCKS (Ads & Payments)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.feature_unlocks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  feature_key TEXT NOT NULL,
  unlock_method TEXT CHECK (unlock_method IN ('ad', 'payment', 'subscription', 'achievement')) NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  expires_at TIMESTAMPTZ,
  ad_unit_id TEXT,
  payment_id UUID REFERENCES public.payments(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- EARNINGS TRACKER
-- ============================================================
CREATE TABLE IF NOT EXISTS public.earnings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  source_type TEXT CHECK (source_type IN ('task', 'skill', 'referral', 'investment', 'business', 'other')) NOT NULL,
  source_id UUID,
  amount NUMERIC(12,2) NOT NULL,
  currency TEXT DEFAULT 'NGN',
  description TEXT,
  earned_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ACHIEVEMENTS & GAMIFICATION
-- ============================================================
CREATE TABLE IF NOT EXISTS public.achievements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  badge_icon TEXT,
  points INT DEFAULT 0,
  unlock_feature TEXT
);

CREATE TABLE IF NOT EXISTS public.user_achievements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_id UUID NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, achievement_id)
);

-- ============================================================
-- COMMUNITY & MENTORSHIP
-- ============================================================
CREATE TABLE IF NOT EXISTS public.community_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  post_type TEXT CHECK (post_type IN ('win', 'tip', 'question', 'challenge')) DEFAULT 'win',
  likes INT DEFAULT 0,
  comments INT DEFAULT 0,
  tags TEXT[] DEFAULT '{}',
  is_visible BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- AD TRACKING
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ad_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ad_unit_id TEXT NOT NULL,
  ad_type TEXT CHECK (ad_type IN ('rewarded', 'interstitial', 'banner')) DEFAULT 'rewarded',
  feature_unlocked TEXT,
  reward_granted BOOLEAN DEFAULT FALSE,
  viewed_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_user ON public.messages(user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_user ON public.tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON public.tasks(status);
CREATE INDEX IF NOT EXISTS idx_enrollments_user ON public.user_skill_enrollments(user_id);
CREATE INDEX IF NOT EXISTS idx_earnings_user ON public.earnings(user_id);
CREATE INDEX IF NOT EXISTS idx_feature_unlocks_user ON public.feature_unlocks(user_id, feature_key);
CREATE INDEX IF NOT EXISTS idx_payments_user ON public.payments(user_id);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_skill_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roadmaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature_unlocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_views ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can access own conversations" ON public.conversations FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own messages" ON public.messages FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own tasks" ON public.tasks FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own enrollments" ON public.user_skill_enrollments FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own roadmap" ON public.roadmaps FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own milestones" ON public.milestones FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own payments" ON public.payments FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own unlocks" ON public.feature_unlocks FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own earnings" ON public.earnings FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own achievements" ON public.user_achievements FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Community posts visible to all" ON public.community_posts FOR SELECT USING (is_visible = TRUE);
CREATE POLICY "Users can manage own posts" ON public.community_posts FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can access own ad views" ON public.ad_views FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Skill modules visible to all" ON public.skill_modules FOR SELECT TO authenticated USING (TRUE);

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_payments_updated BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_roadmaps_updated BEFORE UPDATE ON public.roadmaps FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_conversations_updated BEFORE UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (NEW.id, NEW.email, NEW.raw_user_meta_data->>'full_name')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- SEED ACHIEVEMENTS
-- ============================================================
INSERT INTO public.achievements (key, title, description, badge_icon, points, unlock_feature) VALUES
  ('first_task', 'First Step', 'Completed your first income task', '🎯', 50, 'task_booster'),
  ('first_earn', 'Money Maker', 'Earned your first income through RiseUp', '💰', 100, 'ai_roadmap'),
  ('week_streak', '7-Day Warrior', 'Active for 7 days in a row', '🔥', 200, 'skill_boost'),
  ('first_skill', 'Knowledge Seeker', 'Started your first skill module', '📚', 75, NULL),
  ('skill_complete', 'Skill Unlocked', 'Completed a full skill module', '🏆', 300, 'mentorship'),
  ('first_milestone', 'Milestone Hit', 'Achieved your first roadmap milestone', '🗺️', 150, NULL),
  ('community_post', 'Community Voice', 'Shared your first win in the community', '🌟', 50, NULL),
  ('10k_earned', 'Five Figure Club', 'Earned ₦10,000+ through RiseUp', '💎', 500, 'investment_tools'),
  ('premium_upgrade', 'RiseUp Premium', 'Upgraded to premium membership', '👑', 1000, 'all_features')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- SEED SKILL MODULES
-- ============================================================
INSERT INTO public.skill_modules (title, description, category, duration_days, difficulty, income_potential, is_premium, lessons, tags) VALUES
  (
    'Social Media Marketing for Beginners',
    'Learn to manage social media pages and earn as a freelancer',
    'digital_marketing',
    14,
    'beginner',
    '₦15,000 - ₦80,000/month',
    FALSE,
    '[
      {"day": 1, "title": "Understanding Social Media Platforms", "task": "Create profiles on 3 platforms"},
      {"day": 2, "title": "Content Creation Basics", "task": "Create 5 sample posts"},
      {"day": 3, "title": "Finding Your First Client", "task": "Message 10 local businesses"},
      {"day": 7, "title": "Pricing Your Services", "task": "Create a simple service package"},
      {"day": 14, "title": "Land Your First Paid Client", "task": "Complete your first paid gig"}
    ]',
    ARRAY['social media', 'freelance', 'marketing', 'beginner']
  ),
  (
    'Graphic Design with Canva',
    'Design logos, flyers and social media content — no experience needed',
    'design',
    7,
    'beginner',
    '₦10,000 - ₦50,000/month',
    FALSE,
    '[
      {"day": 1, "title": "Canva Basics", "task": "Create your first 3 designs"},
      {"day": 3, "title": "Business Flyers", "task": "Design 5 flyers for local businesses"},
      {"day": 5, "title": "Logo Design", "task": "Create 3 sample logos"},
      {"day": 7, "title": "Launch on Fiverr/Upwork", "task": "Publish your first gig"}
    ]',
    ARRAY['design', 'canva', 'freelance', 'creative']
  ),
  (
    'Copywriting & Content Writing',
    'Write compelling content for businesses and earn per article',
    'writing',
    14,
    'beginner',
    '$50 - $500/month',
    FALSE,
    '[
      {"day": 1, "title": "What is Copywriting?", "task": "Write a 200-word product description"},
      {"day": 3, "title": "Blog Writing Basics", "task": "Write your first 500-word article"},
      {"day": 7, "title": "Finding Writing Jobs", "task": "Apply to 5 writing gigs"},
      {"day": 14, "title": "Build a Portfolio", "task": "Publish portfolio on Notion/Google Drive"}
    ]',
    ARRAY['writing', 'copywriting', 'content', 'freelance']
  ),
  (
    'Video Editing for Social Media',
    'Edit short-form videos for TikTok, Reels, YouTube Shorts',
    'video',
    21,
    'intermediate',
    '₦20,000 - ₦150,000/month',
    FALSE,
    '[
      {"day": 1, "title": "CapCut & Mobile Editing", "task": "Edit your first 30-second reel"},
      {"day": 7, "title": "Transitions & Effects", "task": "Create 3 viral-style clips"},
      {"day": 14, "title": "Client Work Flow", "task": "Edit a video for a sample brief"},
      {"day": 21, "title": "Price & Sell Your Service", "task": "Get your first paid editing job"}
    ]',
    ARRAY['video', 'editing', 'social media', 'creative']
  ),
  (
    'Digital Product Creation & Sales',
    'Create and sell digital products: eBooks, templates, presets',
    'digital_products',
    30,
    'intermediate',
    '$100 - $2000/month',
    TRUE,
    '[
      {"day": 1, "title": "What Digital Products Sell", "task": "Research top 10 selling digital products"},
      {"day": 7, "title": "Create Your First Product", "task": "Build a Notion template or eBook"},
      {"day": 14, "title": "Setup Gumroad/Selar Store", "task": "Publish your product for sale"},
      {"day": 21, "title": "Marketing Your Product", "task": "Post about your product on 3 platforms"},
      {"day": 30, "title": "First Sales Goal", "task": "Achieve your first 5 sales"}
    ]',
    ARRAY['digital products', 'passive income', 'ecommerce', 'creator']
  ),
  (
    'Affiliate Marketing Mastery',
    'Earn commissions promoting products you believe in',
    'affiliate_marketing',
    21,
    'beginner',
    '$50 - $1000/month',
    FALSE,
    '[
      {"day": 1, "title": "What is Affiliate Marketing?", "task": "Sign up for 3 affiliate programs"},
      {"day": 7, "title": "Content Strategy for Affiliates", "task": "Create 5 promotional posts"},
      {"day": 14, "title": "Building an Audience", "task": "Grow your first 100 followers"},
      {"day": 21, "title": "First Commission Check", "task": "Earn your first affiliate commission"}
    ]',
    ARRAY['affiliate', 'passive income', 'marketing', 'beginner']
  )
ON CONFLICT DO NOTHING;
