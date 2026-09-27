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
import { XMLParser } from "https://esm.sh/fast-xml-parser@4.5.3";

const sb=createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {auth:{persistSession:false}}
);

function privateHost(h:string){
  const x=h.toLowerCase();
  if(x==="localhost"||x==="::1"||x.endsWith(".local")) return true;
  if(/^127\./.test(x)||/^10\./.test(x)||/^169\.254\./.test(x)||/^192\.168\./.test(x)) return true;
  const m=x.match(/^172\.(\d+)\./); if(m&&+m[1]>=16&&+m[1]<=31)return true;
  return false;
}
function val(x:unknown):string{
  if(x==null)return "";
  if(typeof x==="string"||typeof x==="number")return String(x).replace(/\s+/g," ").trim();
  if(Array.isArray(x))return val(x[0]);
  if(typeof x==="object"){
    const o=x as Record<string,unknown>;
    if("#text" in o)return val(o["#text"]);
    if("_text" in o)return val(o["_text"]);
  }
  return "";
}
function stripHtml(s:string){
  return s.replace(/<script[\s\S]*?<\/script>/gi," ").replace(/<style[\s\S]*?<\/style>/gi," ")
    .replace(/<[^>]+>/g," ").replace(/&nbsp;/g," ").replace(/&amp;/g,"&")
    .replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"').replace(/&#39;/g,"'")
    .replace(/\s+/g," ").trim();
}
function first(obj:Record<string,unknown>,names:string[]){
  for(const n of names)if(obj[n]!=null)return obj[n]; return null;
}
async function sha256(s:string){
  const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest))
    .map(b=>b.toString(16).padStart(2,"0")).join("");
}

const corsHeaders={
  "Access-Control-Allow-Origin":"https://bagilu.github.io",
  "Access-Control-Allow-Headers":"content-type, x-p132-ingest-secret",
  "Access-Control-Allow-Methods":"POST, OPTIONS",
  "Vary":"Origin"
};
function respond(body:string,status=200,contentType="text/plain"){
  return new Response(body,{status,headers:{...corsHeaders,"content-type":contentType}});
}
function json(data:unknown,status=200){
  return new Response(JSON.stringify(data),{status,headers:{...corsHeaders,"content-type":"application/json"}});
}

Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response(null,{status:204,headers:corsHeaders});

  if(req.method!=="POST")return respond("Method not allowed",405);
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

    const parser=new XMLParser({ignoreAttributes:false,attributeNamePrefix:"@",textNodeName:"#text",processEntities:true});
    const parsed=parser.parse(xml);
    const rawItems=parsed?.rss?.channel?.item ?? parsed?.feed?.entry ?? [];
    const items=(Array.isArray(rawItems)?rawItems:[rawItems]).filter(Boolean).slice(0,50);
    let imported=0,annotated=0;

    for(const raw of items){
      const item=raw as Record<string,unknown>;
      const title=val(first(item,["title"])); if(!title)continue;
      const linkObj=first(item,["link"]);
      let link=val(linkObj);
      if(linkObj&&typeof linkObj==="object"&&!Array.isArray(linkObj)){
        const lo=linkObj as Record<string,unknown>;
        link=val(lo["@href"])||link;
      }
      if(!link)continue;
      const guid=val(first(item,["guid","id"]));
      const summaryRaw=val(first(item,["description","summary"]));
      const contentRaw=val(first(item,["content:encoded","content"]));
      const summary=stripHtml(summaryRaw);
      const content=stripHtml(contentRaw)||summary;
      const published=val(first(item,["pubDate","published","updated"]));
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
    return json({source_id:sourceId,items_seen:items.length,articles_upserted:imported,
      occurrences_inserted:annotated,matcher_version:"P132-MATCH-0.2"});
  }catch(e){
    await sb.rpc("P132_MarkRSSFetch",{p_source_id:sourceId,p_ok:false,p_error:String(e)});
    return json({error:String(e)},500);
  }
});
