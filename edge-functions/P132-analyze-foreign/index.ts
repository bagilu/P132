// P132 Foreign Linguistic Analyzer V0.1.1
// Canonical function name: P132-analyze-foreign
// Run after database/17E_P132_ForeignLinguisticAnalysisArchitecture.sql
//
// POST JSON: { "article_id": 107 }
// Header: x-p132-ingest-secret: <P132_INGEST_SECRET>
//
// V0.1 deliberately uses a lightweight English analyzer contract in the Edge Function.
// It emits tokens/POS/lemma + conservative candidates. Japanese returns a clear
// deferred status until a Japanese morphological analyzer is connected.
// No learner Evidence is edited here.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const sb=createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {auth:{persistSession:false}}
);
const cors={
 "Access-Control-Allow-Origin":"https://bagilu.github.io",
 "Access-Control-Allow-Headers":"content-type, x-p132-ingest-secret",
 "Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"
};
const json=(x:unknown,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{...cors,"content-type":"application/json"}});

type Tok={token_index:number;surface_text:string;lemma:string;universal_pos:string;
 start_offset:number;end_offset:number;entity_type?:string;is_stopword:boolean;confidence:number};
type Cand={surface_text:string;normalized_term:string;lemma?:string;start_offset:number;end_offset:number;
 term_kind:string;candidate_method:string;pos_pattern?:string;confidence:number};

const stop=new Set(["a","an","the","and","or","but","if","because","while","when","than","of","to","in","on","at","by","for","from","with","about","against","between","into","through","during","before","after","above","below","under","over","as","that","this","these","those","who","which"]);
const pron=new Set(["i","you","he","she","it","we","they","me","him","her","us","them"]);
const aux=new Set(["am","is","are","was","were","be","been","being","do","does","did","have","has","had","can","could","may","might","must","shall","should","will","would"]);
const advWords=new Set(["quietly","quickly","slowly","carefully","successfully","finally","recently","nearly","very","also","only"]);
const verbWords=new Set(["develop","developed","prove","proved","make","made","build","built","invent","invented","include","included","protect","protecting","turn","turned"]);
const adjWords=new Set(["powered","possible","private","total","lunar","genetic","first"]);
const timeWords=new Set(["year","years","day","days","week","weeks","month","months","hour","hours","minute","minutes","century","centuries","decade","decades"]);

function lemma(w:string,pos:string){
 const x=w.toLowerCase();
 const irregular:Record<string,string>={was:"be",were:"be",is:"be",are:"be",been:"be",has:"have",had:"have",did:"do",made:"make",built:"build"};
 if(irregular[x])return irregular[x];
 if(pos==="VERB"&&x.endsWith("ied")&&x.length>4)return x.slice(0,-3)+"y";
 if(pos==="VERB"&&x.endsWith("ed")&&x.length>4)return x.slice(0,-2).replace(/([b-df-hj-np-tv-z])\1$/,"$1");
 if(pos==="NOUN"&&x.endsWith("ies")&&x.length>4)return x.slice(0,-3)+"y";
 if(pos==="NOUN"&&x.endsWith("s")&&!x.endsWith("ss")&&x.length>3)return x.slice(0,-1);
 return x;
}
function posOf(surface:string,index:number){
 const x=surface.toLowerCase();
 if(stop.has(x))return "ADP";
 if(pron.has(x))return "PRON";
 if(aux.has(x))return "AUX";
 if(advWords.has(x)||x.endsWith("ly"))return "ADV";
 if(verbWords.has(x)||x.endsWith("ed")||x.endsWith("ing"))return "VERB";
 if(adjWords.has(x)||x.includes("-than-")||/(ous|ful|less|ive|al|ic|able|ible)$/.test(x))return "ADJ";
 if(/^\d/.test(x))return "NUM";
 if(/^[A-Z]/.test(surface)&&index>0)return "PROPN";
 return "NOUN";
}
function tokenize(body:string):Tok[]{
 const re=/[A-Za-z]+(?:['’\-][A-Za-z]+)*/g; const out:Tok[]=[]; let m:RegExpExecArray|null;let i=0;
 while((m=re.exec(body))){
   const p=posOf(m[0],i),l=lemma(m[0],p),low=m[0].toLowerCase();
   out.push({token_index:i++,surface_text:m[0],lemma:l,universal_pos:p,
     start_offset:m.index,end_offset:m.index+m[0].length,
     entity_type:p==="PROPN"?"PROPER_NAME":undefined,
     is_stopword:stop.has(low)||pron.has(low)||aux.has(low),confidence:0.82});
 }
 return out;
}
function gapOK(body:string,a:Tok,b:Tok){return !/[.!?;:]/.test(body.slice(a.end_offset,b.start_offset));}
function span(body:string,a:Tok,b:Tok){return body.slice(a.start_offset,b.end_offset);}
function candidates(body:string,t:Tok[]):Cand[]{
 const c:Cand[]=[];
 // Every lexical token remains a candidate so the learner can request help.
 for(const x of t)c.push({surface_text:x.surface_text,normalized_term:x.lemma,start_offset:x.start_offset,
   end_offset:x.end_offset,term_kind:x.is_stopword?"function_word":"term",candidate_method:"token",
   pos_pattern:x.universal_pos,confidence:x.is_stopword?0.78:0.84});
 // Consecutive proper nouns -> named entity. Do not bridge conjunctions ("Wilbur and Orville Wright").
 for(let i=0;i<t.length;i++)if(t[i].universal_pos==="PROPN"){
   let j=i;while(j+1<t.length&&t[j+1].universal_pos==="PROPN"&&gapOK(body,t[j],t[j+1]))j++;
   if(j>i){const s=span(body,t[i],t[j]);c.push({surface_text:s,normalized_term:s.toLowerCase(),
     start_offset:t[i].start_offset,end_offset:t[j].end_offset,term_kind:"proper_noun",
     candidate_method:"named_entity",pos_pattern:"PROPN+",confidence:0.93});i=j;}
 }
 // Noun phrase: ADJ/VERB(participial-looking) modifiers + NOUN/PROPN head.
 // Crucially, finite verbs such as "proved" do not absorb the following noun phrase.
 for(let i=0;i<t.length;i++){
   if(!["ADJ","NOUN"].includes(t[i].universal_pos))continue;
   let j=i;let hasHead=t[i].universal_pos==="NOUN";
   while(j+1<t.length&&j-i<3&&gapOK(body,t[j],t[j+1])&&["ADJ","NOUN"].includes(t[j+1].universal_pos)){
     j++;if(t[j].universal_pos==="NOUN")hasHead=true;
   }
   if(j>i&&hasHead){const s=span(body,t[i],t[j]);c.push({surface_text:s,normalized_term:s.toLowerCase(),
     start_offset:t[i].start_offset,end_offset:t[j].end_offset,term_kind:"multiword",
     candidate_method:"noun_chunk",pos_pattern:t.slice(i,j+1).map(x=>x.universal_pos).join("+"),confidence:0.90});}
 }
 // High-confidence grammatical MWEs.
 for(let i=0;i<t.length-1;i++){
   const a=t[i],b=t[i+1],x=a.surface_text.toLowerCase(),y=b.surface_text.toLowerCase();
   if((["more","less","fewer","greater"].includes(x)&&y==="than")||(timeWords.has(x)&&y==="ago")){
     const s=span(body,a,b);c.push({surface_text:s,normalized_term:s.toLowerCase(),start_offset:a.start_offset,
       end_offset:b.end_offset,term_kind:"fixed_expression",candidate_method:"mwe",
       pos_pattern:a.universal_pos+"+"+b.universal_pos,confidence:0.98});
   }
 }
 return c;
}

Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 if(req.headers.get("x-p132-ingest-secret")!==Deno.env.get("P132_INGEST_SECRET"))return json({error:"Unauthorized"},401);
 let articleId:number;try{articleId=Number((await req.json()).article_id)}catch{return json({error:"Bad JSON"},400)}
 if(!Number.isSafeInteger(articleId)||articleId<=0)return json({error:"Invalid article_id"},400);
 let runId:number|undefined;
 try{
   const {data:a,error:ae}=await sb.from("TblP132Article").select("ArticleID,LanguageCode,ContentText,Summary")
     .eq("ArticleID",articleId).eq("IsPublished",true).single();
   if(ae||!a)return json({error:"Article not found"},404);
   if(!["en","ja"].includes(a.LanguageCode))return json({error:"Not a foreign-language article"},400);
   if(a.LanguageCode==="ja")return json({article_id:articleId,language:"ja",status:"deferred",
     reason:"Japanese morphological analyzer not connected in P132 Foreign Linguistic Analyzer V0.1"},200);
   const body=(a.ContentText||a.Summary||"").trim();if(!body)return json({error:"Empty article"},400);
   const {data:rid,error:be}=await sb.rpc("P132_BeginForeignAnalysis",{
     p_article_id:articleId,p_analyzer_name:"P132-edge-english-baseline",p_analyzer_version:"0.1.1",
     p_model_name:null,p_model_version:null,p_metadata:{strategy:"rule_pos_noun_chunk_mwe"}});
   if(be)throw be;runId=Number(rid);
   const toks=tokenize(body),cands=candidates(body,toks);
   const {error:te}=await sb.rpc("P132_SaveForeignLinguisticTokens",{p_analysis_run_id:runId,p_tokens:toks});if(te)throw te;
   const {error:ce}=await sb.rpc("P132_SaveForeignTermCandidates",{p_analysis_run_id:runId,p_candidates:cands});if(ce)throw ce;
   const {data:mat,error:me}=await sb.rpc("P132_MaterializeForeignAnalysis",{p_analysis_run_id:runId});if(me)throw me;
   return json({article_id:articleId,language:"en",analysis_run_id:runId,
     tokens:toks.length,candidates:cands.length,materialization:mat});
 }catch(e){
   if(runId)await sb.rpc("P132_FailForeignAnalysis",{p_analysis_run_id:runId,p_error:String(e)});
   return json({error:String(e),analysis_run_id:runId||null},500);
 }
});
