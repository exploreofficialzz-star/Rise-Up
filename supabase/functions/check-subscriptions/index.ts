// Supabase Edge Function: check-subscriptions
// Runs daily via a cron job to expire premium subscriptions
// Deploy: supabase functions deploy check-subscriptions --no-verify-jwt

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (_req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // Expire premium subscriptions that have passed their end date
  const { data, error } = await supabase
    .from('profiles')
    .update({ subscription_tier: 'free' })
    .eq('subscription_tier', 'premium')
    .lt('subscription_expires_at', new Date().toISOString())
    .select('id, email')

  if (error) {
    console.error('Error expiring subscriptions:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  console.log(`Expired ${data?.length ?? 0} subscriptions`)

  // Also expire feature unlocks
  await supabase
    .from('feature_unlocks')
    .update({ is_active: false })
    .eq('is_active', true)
    .lt('expires_at', new Date().toISOString())

  return new Response(
    JSON.stringify({
      success: true,
      expired_subscriptions: data?.length ?? 0,
      timestamp: new Date().toISOString(),
    }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
