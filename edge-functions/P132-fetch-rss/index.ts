// P132 V0.2 — RSS ingestion Edge Function (canonical P-series name)
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, P132_INGEST_SECRET
// Canonical function name: P132-fetch-rss
//
// POST JSON:
//   { "source_id": 1 }
// Header:
//   x-p132-ingest-secret: <P132_INGEST_SECRET>
//
// Security note: FeedURL comes only from TblP132NewsSource. This function rejects
// localhost/private/link-local targets to reduce SSRF risk.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sb=createClient(
  Deno.env.get("https://mfljkyvdadxlrbxlboce.supabase.co")!,
  Deno.env.get("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mbGpreXZkYWR4bHJieGxib2NlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ4MTQwMDUsImV4cCI6MjA4MDM5MDAwNX0.Z4OeacVpO8yM1d1uOWZ6jU2Gl7wgEbhXvAFSqF5pBRs")!,
  {auth:{persistSession:false}}
);

function privateHost(h:string){
  const x=h.toLowerCase();
  if(x==="localhost"||x==="::1"||x.endsWith(".local")) return true;
  if(/^127\./.test(x)||/^10\./.test(x)||/^169\.254\./.test(x)||/^192\.168\./.test(x)) return true;
  const m=x.match(/^172\.(\d+)\./); if(m&&+m[1]>=16&&+m[1]<=31)return true;
  return false;
}
function textOf(el:Element|null){return (el?.textContent||"").replace(/\s+/g," ").trim();}
function stripHtml(s:string){
  return s.replace(/<script[\s\S]*?<\/script>/gi," ").replace(/<style[\s\S]*?<\/style>/gi," ")
    .replace(/<[^>]+>/g," ").replace(/&nbsp;/g," ").replace(/&amp;/g,"&")
    .replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"').replace(/&#39;/g,"'")
    .replace(/\s+/g," ").trim();
}
async function sha256(s:string){
  const b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function child(el:Element,names:string[]){
  for(const n of names){const q=el.querySelector(n);if(q)return q;} return null;
}

Deno.serve(async req=>{
  if(req.method!=="POST")return new Response("Method not allowed",{status:405});
  if(req.headers.get("x-p132-ingest-secret")!==Deno.env.get("P132_INGEST_SECRET"))
    return respond("Unauthorized",401);

  let sourceId:number;
  try{sourceId=Number((await req.json()).source_id);}catch{return respond("Bad JSON",400);}
  if(!Number.isSafeInteger(sourceId)||sourceId<=0)return respond("Invalid source_id",400);

  const {data:source,error:se}=await sb.from("TblP132NewsSource").select("*")
    .eq("SourceID",sourceId).eq("IsActive",true).single();
  if(se||!source)return respond("Source not found",404);

  try{
    const u=new URL(source.FeedURL);
    if(!["https:","http:"].includes(u.protocol)||privateHost(u.hostname))throw new Error("Feed URL rejected");
    const res=await fetch(u,{redirect:"error",headers:{"user-agent":"P132-Progressive-Immersion/0.2"}});
    if(!res.ok)throw new Error(`Feed HTTP ${res.status}`);
    const xml=await res.text();
    if(xml.length>5_000_000)throw new Error("Feed too large");

    const doc=new DOMParser().parseFromString(xml,"application/xml");
    if(!doc)throw new Error("Invalid XML");
    const items=[...doc.querySelectorAll("item, entry")].slice(0,50);
    let imported=0,annotated=0;

    for(const item of items){
      const title=textOf(child(item,["title"])); if(!title)continue;
      let link=textOf(child(item,["link"]));
      const linkEl=child(item,["link"]);
      if(!link&&linkEl)link=linkEl.getAttribute("href")||"";
      if(!link)continue;
      const guid=textOf(child(item,["guid","id"]));
      const summaryRaw=textOf(child(item,["description","summary"]));
      const contentRaw=textOf(child(item,["content\\:encoded","content"]));
      const summary=stripHtml(summaryRaw);
      const content=stripHtml(contentRaw)||summary;
      const published=textOf(child(item,["pubDate","published","updated"]));
      const publishedAt=published&&!Number.isNaN(Date.parse(published))?new Date(published).toISOString():null;
      const externalId=guid||await sha256(link);
      const hash=await sha256(title+"\n"+content);

      const {data:aid,error:ue}=await sb.rpc("P132_UpsertRSSArticle",{
        p_source_id:sourceId,p_external_id:externalId,p_title:title,p_summary:summary||null,
        p_content_text:content||null,p_original_url:link,p_published_at:publishedAt,
        p_category:source.DefaultCategory||null,p_content_hash:hash
      });
      if(ue)throw ue;
      imported++;
      const {data:ar,error:ae}=await sb.rpc("P132_AnnotateArticleOccurrences",{p_article_id:aid});
      if(ae)throw ae;
      annotated+=Number(ar?.inserted||0);
    }
    await sb.rpc("P132_MarkRSSFetch",{p_source_id:sourceId,p_ok:true,p_error:null});
    return Response.json({source_id:sourceId,items_seen:items.length,articles_upserted:imported,
      occurrences_inserted:annotated,matcher_version:"P132-MATCH-0.2"});
  }catch(e){
    await sb.rpc("P132_MarkRSSFetch",{p_source_id:sourceId,p_ok:false,p_error:String(e)});
    return json({error:String(e)},500);
  }
});
