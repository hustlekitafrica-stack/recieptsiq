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

    const body = await req.json() as { image_base64?: string };
    const base64Image = body.image_base64;
    if (!base64Image) {
      return new Response(JSON.stringify({ error: 'image_base64 is required' }), {
        status: 400, headers: corsHeaders,
      });
    }

    if (!OPENAI_API_KEY) throw new Error('OPENAI_API_KEY secret is not configured.');

    const aiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        max_tokens: 2000,
        messages: [{
          role: 'user',
          content: [
            {
              type: 'image_url',
              image_url: { url: `data:image/jpeg;base64,${base64Image}`, detail: 'high' },
            },
            {
              type: 'text',
              text: 'Extract ALL text from this receipt image exactly as printed. Return only the raw text, preserving line breaks. No explanation, no formatting, just the text.',
            },
          ],
        }],
      }),
    });

    if (!aiRes.ok) {
      const errBody = await aiRes.json().catch(() => ({}));
      throw new Error(`OpenAI error ${aiRes.status}: ${errBody?.error?.message ?? aiRes.statusText}`);
    }

    const aiData = await aiRes.json();
    const text: string = aiData.choices?.[0]?.message?.content?.trim() ?? '';
    if (!text) throw new Error('Could not read any text from this image. Ensure the receipt is well-lit and fully in frame.');

    return new Response(JSON.stringify({ text }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
