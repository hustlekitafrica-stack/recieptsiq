import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL         = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const OPENAI_API_KEY       = Deno.env.get('OPENAI_API_KEY')!;
const OPENAI_MODEL         = Deno.env.get('OPENAI_MODEL') ?? 'gpt-4o-mini';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ReceiptRow {
  date: string;
  merchant: string;
  amount: number;
  currency: string;
  category: string;
}

interface ChatRequest {
  message: string;
  currency: string;
  receipt_context: ReceiptRow[];
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

    const body = await req.json() as ChatRequest;
    const { message, currency, receipt_context } = body;

    // Build compact receipt summary (cap at 200 rows)
    const rows = (receipt_context ?? []).slice(0, 200);
    const contextLines = rows.map(
      (r) => `${r.date} | ${r.merchant} | ${r.currency} ${r.amount.toLocaleString()} | ${r.category}`
    ).join('\n');

    const systemPrompt = `You are ReceiptIQ, an AI business financial assistant for a small business owner in East Africa.
You have access to the user's receipt data shown below. Answer questions concisely and helpfully.
Always refer to specific data when answering. If data is insufficient, say so honestly.
Use ${currency} amounts. Be brief — 2-5 sentences max unless a breakdown is needed.

Receipt data (Date | Merchant | Amount | Category):
${contextLines || '(No receipts yet)'}`;

    const aiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        temperature: 0.3,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: message },
        ],
      }),
    });

    if (!aiRes.ok) {
      const errBody = await aiRes.json().catch(() => ({}));
      throw new Error(`OpenAI error ${aiRes.status}: ${(errBody as any)?.error?.message ?? aiRes.statusText}`);
    }

    const aiData = await aiRes.json();
    const reply = aiData.choices?.[0]?.message?.content as string | undefined;
    if (!reply?.trim()) throw new Error('OpenAI returned an empty response.');

    return new Response(JSON.stringify({ reply: reply.trim() }), {
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
