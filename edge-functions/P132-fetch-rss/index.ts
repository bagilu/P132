// P132-fetch-rss V0.1 scaffold. Deploy as a Supabase Edge Function.
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Never expose service role in GitHub Pages.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async (req) => {
  const url = new URL(req.url); const feed = url.searchParams.get('feed');
  if (!feed) return new Response(JSON.stringify({error:'feed is required'}),{status:400,headers:{'content-type':'application/json'}});
  const allowed = await createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!).from('TblP132NewsSource').select('SourceID,FeedURL').eq('FeedURL',feed).eq('IsActive',true).maybeSingle();
  if (!allowed.data) return new Response(JSON.stringify({error:'feed not registered'}),{status:403,headers:{'content-type':'application/json'}});
  const r=await fetch(feed,{headers:{'user-agent':'P132-ProgressiveImmersion/0.1'}}); const xml=await r.text();
  // V0.1 intentionally returns normalized-fetch diagnostics only. RSS dialect-specific parsing/import is the next migration.
  return new Response(JSON.stringify({source_id:allowed.data.SourceID,http_status:r.status,bytes:xml.length,preview:xml.slice(0,500)}),{headers:{'content-type':'application/json'}});
});
