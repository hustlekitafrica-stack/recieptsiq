import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const VISION_KEY          = Deno.env.get('GOOGLE_VISION_API_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function toBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 8192;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
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

    const { storage_path } = await req.json() as { storage_path: string };
    if (!storage_path) {
      return new Response(JSON.stringify({ error: 'storage_path is required' }), {
        status: 400, headers: corsHeaders,
      });
    }

    const { data: fileBlob, error: storageErr } = await supabase.storage
      .from('ocr-temp').download(storage_path);
    if (storageErr || !fileBlob) throw new Error(`Storage download failed: ${storageErr?.message}`);

    const imageBytes = new Uint8Array(await fileBlob.arrayBuffer());
    const base64Image = toBase64(imageBytes);

    const visionRes = await fetch(
      `https://vision.googleapis.com/v1/images:annotate?key=${VISION_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requests: [{
            image: { content: base64Image },
            features: [{ type: 'DOCUMENT_TEXT_DETECTION' }],
            imageContext: { languageHints: ['en'] },
          }],
        }),
      },
    );
    const visionData = await visionRes.json();

    await supabase.storage.from('ocr-temp').remove([storage_path]).catch(() => {});

    const response0 = visionData.responses?.[0];
    if (response0?.error) throw new Error(`Vision API error: ${response0.error.message}`);

    const text: string = response0?.fullTextAnnotation?.text ?? '';
    if (!text.trim()) throw new Error('No text detected in this image.');

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
