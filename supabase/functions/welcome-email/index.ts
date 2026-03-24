// Supabase Edge Function: welcome-email
// Triggered via database webhook on new profile creation
// Deploy: supabase functions deploy welcome-email

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface WebhookPayload {
  type: 'INSERT'
  table: string
  record: {
    id: string
    email: string
    full_name: string | null
  }
}

Deno.serve(async (req) => {
  const payload: WebhookPayload = await req.json()

  if (payload.type !== 'INSERT' || payload.table !== 'profiles') {
    return new Response('Not a profile insert', { status: 200 })
  }

  const { email, full_name } = payload.record
  const name = full_name?.split(' ')[0] ?? 'Champion'

  // In production, integrate with your email provider (Resend, SendGrid, etc.)
  // For now, log the welcome
  console.log(`New user signup: ${name} <${email}>`)

  // Example with Resend (add RESEND_API_KEY to Supabase secrets):
  /*
  const resendKey = Deno.env.get('RESEND_API_KEY')
  if (resendKey) {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'RiseUp <hello@riseupapp.com>',
        to: [email],
        subject: `Welcome to RiseUp, ${name}! 🚀`,
        html: `
          <h2>Hey ${name}! 👋</h2>
          <p>Welcome to RiseUp — your personal AI wealth mentor.</p>
          <p>Here's what to do next:</p>
          <ol>
            <li>Complete your onboarding chat with our AI</li>
            <li>Get your first income task assigned</li>
            <li>Start your first skill module</li>
          </ol>
          <p>Your journey from survival mode to wealth starts NOW.</p>
          <p>— The RiseUp AI Team 🚀</p>
          <p><small>ChAs Tech Group</small></p>
        `,
      }),
    })
  }
  */

  return new Response(
    JSON.stringify({ success: true, email }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
