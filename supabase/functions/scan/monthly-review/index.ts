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
  month_label:    string;         // e.g. "June 2026"
  currency:       string;         // ISO 4217
  total_spent:    number;
  receipt_count:  number;
  biggest_category:        string | null;
  biggest_category_amount: number;
  category_breakdown:      string; // "groceries KES 4,200, fuel KES 5,000, ..."
  budget_status:           string; // multi-line budget summary
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── Auth ────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('authorization') ?? '';
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { data: { user }, error: authErr } =
      await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: corsHeaders,
      });
    }

    // ── Input ───────────────────────────────────────────────────────────────
    const body = await req.json() as ReviewRequest;

    const prompt = `You are ReceiptIQ's AI Financial Coach. Generate a friendly, encouraging monthly financial review for a user in East Africa.

User data for ${body.month_label}:
- Total spent: ${body.currency} ${body.total_spent.toLocaleString()}
- Receipts: ${body.receipt_count}
- Biggest category: ${body.biggest_category ?? '—'} (${body.currency} ${body.biggest_category_amount.toLocaleString()})
- Category breakdown: ${body.category_breakdown}
- Budget status:
${body.budget_status}

Rules:
- Be encouraging and practical, never shaming.
- Highlight one positive trend or win.
- Flag any budget overruns gently.
- Give 2–3 actionable, specific tips.
- Keep total review under 180 words.
- Use local context when relevant (Kenya / Tanzania / Uganda / Nigeria / Ghana).

Return JSON with this exact schema:
{
  "headline": "string (catchy one-line headline)",
  "summary": "string (2-3 sentence overview)",
  "insights": ["string", "string", "..."],
  "tips": ["string", "string", "string"],
  "budget_alerts": ["string", "..."],
  "tone": "positive|neutral|caution"
}`;

    // ── Call OpenAI ─────────────────────────────────────────────────────────
    const aiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        temperature: 0.4,
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

    const parsed = JSON.parse(content);

    return new Response(JSON.stringify(parsed), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
