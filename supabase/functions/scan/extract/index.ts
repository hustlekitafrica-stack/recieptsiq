import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const OPENAI_API_KEY      = Deno.env.get('OPENAI_API_KEY')!;
const OPENAI_MODEL        = Deno.env.get('OPENAI_MODEL') ?? 'gpt-4o-mini';

const CATEGORIES =
  'groceries, fuel, rent, utilities, transport, entertainment, ' +
  'businessSupplies, staffExpenses, school, medical, other';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function systemPrompt(currency: string): string {
  return `You are an expert at reading shopping/business receipts and returning STRICT JSON.
Extract the fields below from the receipt text. Respond with ONLY a JSON object, no prose.

Schema:
{
  "merchant": string,
  "date": string,               // ISO 8601 date (YYYY-MM-DD)
  "total": number,
  "vat": number|null,
  "currency": string,           // ISO 4217, default "${currency}"
  "category": string,           // one of: ${CATEGORIES}
  "items": [
    { "name": string, "quantity": number, "unit_price": number, "amount": number }
  ]
}

Rules:
- Numbers are plain numbers (no currency symbols or thousands separators).
- If a field is missing use a sensible default (0, null, or "${currency}").
- Pick the single best category from the allowed list.`;
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
    const { ocr_text, currency } =
      await req.json() as { ocr_text: string; currency: string };
    if (!ocr_text) {
      return new Response(JSON.stringify({ error: 'ocr_text is required' }), {
        status: 400, headers: corsHeaders,
      });
    }

    const fallbackCurrency = currency ?? 'KES';

    // ── Call OpenAI ─────────────────────────────────────────────────────────
    const aiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: systemPrompt(fallbackCurrency) },
          { role: 'user',   content: `Receipt text:\n"""\n${ocr_text}\n"""` },
        ],
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
