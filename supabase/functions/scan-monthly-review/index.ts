import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const OPENAI_API_KEY      = Deno.env.get('OPENAI_API_KEY')!;
const OPENAI_MODEL        = Deno.env.get('OPENAI_MODEL') ?? 'gpt-4o-mini';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ReviewRequest {
  month_label: string; currency: string; total_spent: number;
  receipt_count: number; biggest_category: string | null;
  biggest_category_amount: number; category_breakdown: string; budget_status: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = req.headers.get('authorization') ?? '';
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: { user }, error: authErr } =
      await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: corsHeaders,
      });
    }

    const body = await req.json() as ReviewRequest;
    const prompt = `You are ReceiptIQ's AI Financial Coach. Generate a friendly, encouraging monthly financial review for a user in East Africa.

User data for ${body.month_label}:
- Total spent: ${body.currency} ${body.total_spent.toLocaleString()}
- Receipts: ${body.receipt_count}
- Biggest category: ${body.biggest_category ?? '—'} (${body.currency} ${body.biggest_category_amount.toLocaleString()})
- Category breakdown: ${body.category_breakdown}
- Budget status:\n${body.budget_status}

Rules: Be encouraging and practical. Highlight one win. Flag overruns gently. Give 2-3 actionable tips. Under 180 words. Use local context when relevant.

Return JSON:
{
  "headline": "string",
  "summary": "string",
  "insights": ["string"],
  "tips": ["string"],
  "budget_alerts": ["string"],
  "tone": "positive|neutral|caution"
}`;

    const aiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: OPENAI_MODEL, temperature: 0.4,
        response_format: { type: 'json_object' },
        messages: [{ role: 'system', content: prompt }],
      }),
    });

    if (!aiRes.ok) {
      const errBody = await aiRes.json().catch(() => ({}));
      throw new Error(`OpenAI error ${aiRes.status}: ${errBody?.error?.message ?? aiRes.statusText}`);
    }

    const aiData = await aiRes.json();
    const content = aiData.choices?.[0]?.message?.content as string | undefined;
    if (!content?.trim()) throw new Error('OpenAI returned an empty response.');

    return new Response(JSON.stringify(JSON.parse(content)), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
