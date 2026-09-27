-- P132 V0.2
-- 12_P132_ReadingSession_ExposureDedup.sql
-- A reading session is created when a learner opens an article.
-- Re-preparing the same article with the same session reuses exposures;
-- a later genuine reading creates a new session and may create new exposures.

create table if not exists public."TblP132ReadingSession"(
  "ReadingSessionID" uuid primary key default gen_random_uuid(),
  "UserID" uuid not null,
  "ArticleID" bigint not null references public."TblP132Article"("ArticleID") on delete cascade,
  "TargetLanguage" text not null check("TargetLanguage" in('en','ja')),
  "StartedAt" timestamptz not null default now(),
  "LastActivityAt" timestamptz not null default now(),
  "EndedAt" timestamptz,
  "CreatedAt" timestamptz not null default now()
);

alter table public."TblP132Exposure"
  add column if not exists "ReadingSessionID" uuid
  references public."TblP132ReadingSession"("ReadingSessionID") on delete set null;

create index if not exists "IdxP132ReadingSessionUserArticle"
  on public."TblP132ReadingSession"("UserID","ArticleID","StartedAt" desc);
create index if not exists "IdxP132ExposureReadingSession"
  on public."TblP132Exposure"("ReadingSessionID");

-- One occurrence can create at most one exposure inside one reading session.
create unique index if not exists "UqP132ExposureSessionOccurrence"
  on public."TblP132Exposure"("ReadingSessionID","OccurrenceID")
  where "ReadingSessionID" is not null;

alter table public."TblP132ReadingSession" enable row level security;
revoke all on table public."TblP132ReadingSession" from anon;
revoke all on table public."TblP132ReadingSession" from authenticated;

create or replace function public."P132_StartReadingSession"(p_article_id bigint)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare uid uuid:=auth.uid(); lang text; sid uuid;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  perform public."P132_EnsureLearnerProfile"();

  select "TargetLanguage" into lang
  from public."TblP132LearnerProfile" where "UserID"=uid;

  if not exists(select 1 from public."TblP132Article"
                where "ArticleID"=p_article_id and "IsPublished") then
    raise exception 'Article not found';
  end if;

  insert into public."TblP132ReadingSession"
    ("UserID","ArticleID","TargetLanguage")
  values(uid,p_article_id,lang)
  returning "ReadingSessionID" into sid;

  return sid;
end $$;

-- SQL 12 version: session-aware preparation.
create or replace function public."P132_PrepareArticle"(p_article_id bigint,p_reading_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 uid uuid:=auth.uid(); lang text; art public."TblP132Article"; body text;
 new_rate numeric; new_budget int; review_budget int; cur int:=0;
 r record; segments jsonb:='[]'::jsonb; displaytext text; eid bigint;
begin
 if uid is null then raise exception 'Authentication required'; end if;
 perform public."P132_EnsureLearnerProfile"();
 select "TargetLanguage",coalesce("PreferredInfiltrationRate",0.0200)
 into lang,new_rate from public."TblP132LearnerProfile" where "UserID"=uid;

 select * into art from public."TblP132Article"
 where "ArticleID"=p_article_id and "IsPublished";
 if not found then raise exception 'Article not found'; end if;

 if p_reading_session_id is null or not exists(
   select 1 from public."TblP132ReadingSession" s
   where s."ReadingSessionID"=p_reading_session_id
     and s."UserID"=uid and s."ArticleID"=p_article_id
     and s."TargetLanguage"=lang and s."EndedAt" is null
 ) then raise exception 'Invalid reading session'; end if;

 update public."TblP132ReadingSession"
 set "LastActivityAt"=now()
 where "ReadingSessionID"=p_reading_session_id;

 body:=coalesce(art."ContentText",art."Summary",'');
 new_rate:=least(0.10,greatest(0.005,new_rate));
 new_budget:=least(10,greatest(1,ceil(length(body)::numeric*new_rate/2.0)::int));
 review_budget:=least(6,greatest(1,ceil(length(body)::numeric/180.0)::int));

 create temporary table if not exists pg_temp.p132_selected(
   "OccurrenceID" bigint primary key,"ConceptID" bigint,"OriginalText" text,
   "StartOffset" int,"EndOffset" int,"FormID" bigint,"SurfaceForm" text,"Reading" text,
   state text,show_understand boolean
 ) on commit drop;
 truncate pg_temp.p132_selected;

 -- Reuse the exact presentation already chosen for this session first.
 insert into pg_temp.p132_selected
 select o."OccurrenceID",o."ConceptID",o."OriginalText",o."StartOffset",o."EndOffset",
        f."FormID",f."SurfaceForm",f."Reading",
        case
          when last_ev."EvidenceType"='understand' then 'immersed'
          when last_ev."EvidenceType"='translation_request' then 'review'
          else 'new'
        end,
        case when last_ev."EvidenceType"='understand' then false else true end
 from public."TblP132Exposure" x
 join public."TblP132ArticleOccurrence" o on o."OccurrenceID"=x."OccurrenceID"
 join public."TblP132VocabularyForm" f on f."FormID"=x."DisplayedFormID"
 left join lateral(
   select v."EvidenceType" from public."TblP132LearnerEvidence" v
   join public."TblP132Exposure" ex on ex."ExposureID"=v."ExposureID"
   where ex."UserID"=uid and ex."ConceptID"=o."ConceptID" and ex."TargetLanguage"=lang
   order by v."OccurredAt" desc,v."EvidenceID" desc limit 1
 ) last_ev on true
 where x."ReadingSessionID"=p_reading_session_id;

 -- Immersed lane not already present in this session.
 insert into pg_temp.p132_selected
 select o."OccurrenceID",o."ConceptID",o."OriginalText",o."StartOffset",o."EndOffset",
        f."FormID",f."SurfaceForm",f."Reading",'immersed',false
 from public."TblP132ArticleOccurrence" o
 join public."TblP132VocabularyConcept" c on c."ConceptID"=o."ConceptID"
 join public."TblP132ConceptInfiltrationPolicy" p
   on p."ConceptID"=o."ConceptID" and p."TargetLanguage"=lang
   and p."Phase1Eligible" and p."SuitabilityGrade" in('A','B')
 join lateral(select * from public."TblP132VocabularyForm" ff
   where ff."ConceptID"=o."ConceptID" and ff."LanguageCode"=lang and ff."IsActive"
   order by ff."IsPreferred" desc,ff."FormID" limit 1) f on true
 join lateral(select v."EvidenceType" from public."TblP132LearnerEvidence" v
   join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
   where x."UserID"=uid and x."ConceptID"=o."ConceptID" and x."TargetLanguage"=lang
   order by v."OccurredAt" desc,v."EvidenceID" desc limit 1) last_ev
   on last_ev."EvidenceType"='understand'
 where o."ArticleID"=p_article_id and o."ReplacementEligible"
   and c."IsActive" and c."ReviewStatus"='approved'
   and not exists(select 1 from pg_temp.p132_selected z where z."OccurrenceID"=o."OccurrenceID");

 -- Review lane.
 insert into pg_temp.p132_selected
 select q."OccurrenceID",q."ConceptID",q."OriginalText",q."StartOffset",q."EndOffset",
        q."FormID",q."SurfaceForm",q."Reading",'review',true
 from (
   select distinct on(o."ConceptID")
     o."OccurrenceID",o."ConceptID",o."OriginalText",o."StartOffset",o."EndOffset",
     f."FormID",f."SurfaceForm",f."Reading",s."LastTranslationAt",o."MatchConfidence"
   from public."TblP132ArticleOccurrence" o
   join public."TblP132VocabularyConcept" c on c."ConceptID"=o."ConceptID"
   join public."TblP132ConceptInfiltrationPolicy" p
     on p."ConceptID"=o."ConceptID" and p."TargetLanguage"=lang
     and p."Phase1Eligible" and p."SuitabilityGrade" in('A','B')
   join public."TblP132LearnerVocabularyState" s
     on s."UserID"=uid and s."ConceptID"=o."ConceptID" and s."TargetLanguage"=lang
   join lateral(select * from public."TblP132VocabularyForm" ff
     where ff."ConceptID"=o."ConceptID" and ff."LanguageCode"=lang and ff."IsActive"
     order by ff."IsPreferred" desc,ff."FormID" limit 1) f on true
   join lateral(select v."EvidenceType" from public."TblP132LearnerEvidence" v
     join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
     where x."UserID"=uid and x."ConceptID"=o."ConceptID" and x."TargetLanguage"=lang
     order by v."OccurredAt" desc,v."EvidenceID" desc limit 1) last_ev
     on last_ev."EvidenceType"='translation_request'
   where o."ArticleID"=p_article_id and o."ReplacementEligible"
     and c."IsActive" and c."ReviewStatus"='approved'
     and not exists(select 1 from pg_temp.p132_selected z where z."OccurrenceID"=o."OccurrenceID")
   order by o."ConceptID",o."StartOffset"
 ) q
 order by q."LastTranslationAt" asc nulls first,q."MatchConfidence" desc nulls last
 limit review_budget;

 -- New lane.
 insert into pg_temp.p132_selected
 select q."OccurrenceID",q."ConceptID",q."OriginalText",q."StartOffset",q."EndOffset",
        q."FormID",q."SurfaceForm",q."Reading",'new',true
 from (
   select distinct on(o."ConceptID")
     o."OccurrenceID",o."ConceptID",o."OriginalText",o."StartOffset",o."EndOffset",
     f."FormID",f."SurfaceForm",f."Reading",o."MatchConfidence"
   from public."TblP132ArticleOccurrence" o
   join public."TblP132VocabularyConcept" c on c."ConceptID"=o."ConceptID"
   join public."TblP132ConceptInfiltrationPolicy" p
     on p."ConceptID"=o."ConceptID" and p."TargetLanguage"=lang
     and p."Phase1Eligible" and p."SuitabilityGrade"='A'
   join lateral(select * from public."TblP132VocabularyForm" ff
     where ff."ConceptID"=o."ConceptID" and ff."LanguageCode"=lang and ff."IsActive"
     order by ff."IsPreferred" desc,ff."FormID" limit 1) f on true
   where o."ArticleID"=p_article_id and o."ReplacementEligible"
     and c."IsActive" and c."ReviewStatus"='approved'
     and not exists(select 1 from public."TblP132LearnerEvidence" v
       join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
       where x."UserID"=uid and x."ConceptID"=o."ConceptID" and x."TargetLanguage"=lang)
     and not exists(select 1 from pg_temp.p132_selected z where z."OccurrenceID"=o."OccurrenceID")
   order by o."ConceptID",o."MatchConfidence" desc nulls last,o."StartOffset"
 ) q
 order by q."MatchConfidence" desc nulls last,q."StartOffset"
 limit new_budget;

 for r in
   select s.* from pg_temp.p132_selected s
   order by s."StartOffset",(s."EndOffset"-s."StartOffset") desc
 loop
   if r."StartOffset">=cur then
     if r."StartOffset">cur then
       segments:=segments||jsonb_build_array(
         jsonb_build_object('text',substring(body from cur+1 for r."StartOffset"-cur)));
     end if;
     displaytext:=case when lang='ja' and r."Reading" is not null
       then r."SurfaceForm"||'（'||r."Reading"||'）' else r."SurfaceForm" end;

     select x."ExposureID" into eid
     from public."TblP132Exposure" x
     where x."ReadingSessionID"=p_reading_session_id
       and x."OccurrenceID"=r."OccurrenceID"
     limit 1;

     if eid is null then
       insert into public."TblP132Exposure"
         ("UserID","ArticleID","OccurrenceID","ConceptID","DisplayedFormID","TargetLanguage",
          "PresentationMode","AlgorithmVersion","InfiltrationRate","ReadingSessionID")
       values(uid,p_article_id,r."OccurrenceID",r."ConceptID",r."FormID",lang,
         case when lang='ja' and r."Reading" is not null then 'surface_reading' else 'surface' end,
         'P132-ALG-0.3',new_rate,p_reading_session_id)
       returning "ExposureID" into eid;
       perform public."P132_RecalculateVocabularyState"(uid,r."ConceptID",lang);
     end if;

     segments:=segments||jsonb_build_array(jsonb_build_object(
       'text',r."OriginalText",'display_text',displaytext,'exposure_id',eid,
       'learning_state',r.state,'show_understand',r.show_understand));
     cur:=r."EndOffset";
   end if;
 end loop;

 if cur<length(body) then
   segments:=segments||jsonb_build_array(jsonb_build_object('text',substring(body from cur+1)));
 end if;

 return jsonb_build_object(
   'article_id',art."ArticleID",'title',art."Title",'original_url',art."OriginalURL",
   'target_language',lang,'algorithm_version','P132-ALG-0.3',
   'reading_session_id',p_reading_session_id,
   'new_vocabulary_rate',new_rate,'segments',segments);
end $$;

-- Remove access to the old one-argument prepare RPC so clients cannot bypass sessions.
revoke all on function public."P132_PrepareArticle"(bigint) from public;
revoke all on function public."P132_PrepareArticle"(bigint) from anon;
revoke all on function public."P132_PrepareArticle"(bigint) from authenticated;

revoke all on function public."P132_StartReadingSession"(bigint) from public;
grant execute on function public."P132_StartReadingSession"(bigint) to authenticated;
revoke all on function public."P132_PrepareArticle"(bigint,uuid) from public;
grant execute on function public."P132_PrepareArticle"(bigint,uuid) to authenticated;

-- Audit
select column_name,data_type
from information_schema.columns
where table_schema='public' and table_name='TblP132Exposure'
  and column_name='ReadingSessionID';
