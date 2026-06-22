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
  "category": string,           // dominant item category (see rules below)
  "items": [
    { "name": string, "quantity": number, "unit_price": number, "amount": number, "category": string }
  ]
}

ITEM CATEGORY RULES — read carefully:
1. Every item MUST have its own specific category that describes WHAT THAT ITEM IS.
   Use granular, real-world labels, e.g.:
   "Cooking Oil", "White Sugar", "Wheat Flour", "Tomato Sauce", "Mineral Water",
   "Bread", "Fresh Milk", "Eggs", "Laundry Detergent", "Dish Soap",
   "Mobile Airtime", "Internet Data", "Prescription Drug", "Vitamins",
   "School Notebook", "Pens & Stationery", "Engine Oil", "Petrol",
   "Electricity", "Rent", "Staff Salary", "Packaging Material",
   "Building Materials", "Hardware Tools", "Printer Paper", "Clothing"
2. NEVER apply the same generic label to every item on the receipt.
   Each item's category must reflect that specific item, not a catch-all bucket.
3. NEVER use vague labels like "groceries", "household", "baking_supplies",
   "general", "items", "goods", "products", or "miscellaneous" for individual items.
4. The top-level "category" field must equal the most common category among the items
   (by count). Do not invent a new label for the receipt level.

NUMBER RULES:
- Plain numbers only — no currency symbols or thousands separators.
- Missing fields: use sensible defaults (0, null, or "${currency}").

VAT RULES — always extract or compute:
- If the receipt shows a VAT/Tax total line, use that value.
- Kenyan receipts use tax codes: A = 16% VAT, B = 8% VAT, E/F = exempt.
  Sum VAT for taxable items: (amount / 1.16 × 0.16) for code A items.
- If a VAT PIN or "TAX INVOICE" heading appears, VAT is included in the total — compute it.
- Only set vat to null if the receipt is clearly VAT-exempt with no tax at all.`;
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

    const { ocr_text, currency } = await req.json() as { ocr_text: string; currency: string };
    if (!ocr_text) {
      return new Response(JSON.stringify({ error: 'ocr_text is required' }), {
        status: 400, headers: corsHeaders,
      });
    }

    const fallbackCurrency = currency ?? 'KES';
    const aiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: OPENAI_MODEL, temperature: 0,
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
