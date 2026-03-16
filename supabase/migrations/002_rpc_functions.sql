-- ============================================================
-- Migration 002: Helper RPC Functions
-- ============================================================

-- Increment message count on conversation
CREATE OR REPLACE FUNCTION increment_message_count(conv_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.conversations
  SET message_count = message_count + 1,
      updated_at = NOW()
  WHERE id = conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment total_earned on profile
CREATE OR REPLACE FUNCTION increment_total_earned(uid UUID, amount NUMERIC)
RETURNS void AS $$
BEGIN
  UPDATE public.profiles
  SET total_earned = total_earned + amount,
      updated_at = NOW()
  WHERE id = uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment post likes
CREATE OR REPLACE FUNCTION increment_post_likes(pid UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.community_posts
  SET likes = likes + 1
  WHERE id = pid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check and update expired subscriptions
CREATE OR REPLACE FUNCTION check_expired_subscriptions()
RETURNS void AS $$
BEGIN
  UPDATE public.profiles
  SET subscription_tier = 'free'
  WHERE subscription_tier = 'premium'
    AND subscription_expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get user earnings by time period
CREATE OR REPLACE FUNCTION get_earnings_by_period(uid UUID, period TEXT DEFAULT 'month')
RETURNS TABLE(total NUMERIC, count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(e.amount), 0) as total,
    COUNT(e.id) as count
  FROM public.earnings e
  WHERE e.user_id = uid
    AND CASE period
      WHEN 'today' THEN e.earned_at >= CURRENT_DATE
      WHEN 'week' THEN e.earned_at >= CURRENT_DATE - INTERVAL '7 days'
      WHEN 'month' THEN e.earned_at >= CURRENT_DATE - INTERVAL '30 days'
      WHEN 'year' THEN e.earned_at >= CURRENT_DATE - INTERVAL '365 days'
      ELSE e.earned_at >= CURRENT_DATE - INTERVAL '30 days'
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Leaderboard view
CREATE OR REPLACE VIEW public.leaderboard AS
SELECT
  p.id,
  p.full_name,
  p.stage,
  p.country,
  p.total_earned,
  p.currency,
  RANK() OVER (ORDER BY p.total_earned DESC) as rank
FROM public.profiles p
WHERE p.total_earned > 0
ORDER BY p.total_earned DESC
LIMIT 100;

GRANT SELECT ON public.leaderboard TO authenticated;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION increment_message_count TO authenticated;
GRANT EXECUTE ON FUNCTION increment_total_earned TO authenticated;
GRANT EXECUTE ON FUNCTION increment_post_likes TO authenticated;
GRANT EXECUTE ON FUNCTION get_earnings_by_period TO authenticated;
