-- P132 V0.2 Progressive Immersion Engine
-- Prerequisites: 01-09.
-- Implements latest-action state:
--   understand -> immersed (always foreignize when eligible; red control only)
--   translation_request -> review (high re-exposure priority; red + green)
--   no evidence -> unconfirmed/new (subject to new-vocabulary quota; red + green)
-- Also fixes FamiliarityScore capacity and rendering-order bug.

alter table public."TblP132LearnerVocabularyState"
  alter column "FamiliarityScore" type numeric(7,4);

create or replace function public."P132_RecalculateVocabularyState"(p_user uuid,p_concept bigint,p_language text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
 e int:=0;t int:=0;u int:=0;s numeric:=0;stage text:='new';
 le timestamptz;lt timestamptz;lu timestamptz;latest_type text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if auth.uid()<>p_user then raise exception 'Forbidden'; end if;
 select count(*),max("DisplayedAt") into e,le
 from public."TblP132Exposure"
 where "UserID"=p_user and "ConceptID"=p_concept and "TargetLanguage"=p_language;

 select count(*) filter(where v."EvidenceType"='translation_request'),
        count(*) filter(where v."EvidenceType"='understand'),
        max(v."OccurredAt") filter(where v."EvidenceType"='translation_request'),
        max(v."OccurredAt") filter(where v."EvidenceType"='understand')
 into t,u,lt,lu
 from public."TblP132LearnerEvidence" v
 join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
 where x."UserID"=p_user and x."ConceptID"=p_concept and x."TargetLanguage"=p_language;

 select v."EvidenceType" into latest_type
 from public."TblP132LearnerEvidence" v
 join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
 where x."UserID"=p_user and x."ConceptID"=p_concept and x."TargetLanguage"=p_language
 order by v."OccurredAt" desc,v."EvidenceID" desc limit 1;

 -- FamiliarityScore remains descriptive only. Selection uses latest evidence state.
 s:=greatest(0,least(100,(e*2)+(u*15)-(t*10)));
 stage:=case
   when latest_type='understand' then 'stable'
   when latest_type='translation_request' then 'emerging'
   when e>0 then 'new'
   else 'new'
 end;

 insert into public."TblP132LearnerVocabularyState"
 ("UserID","ConceptID","TargetLanguage","ExposureCount","TranslationRequestCount","UnderstandCount",
  "FamiliarityScore","FamiliarityStage","LastExposedAt","LastTranslationAt","LastUnderstandAt","UpdatedAt")
 values(p_user,p_concept,p_language,e,t,u,s,stage,le,lt,lu,now())
 on conflict("UserID","ConceptID","TargetLanguage") do update set
 "ExposureCount"=excluded."ExposureCount",
 "TranslationRequestCount"=excluded."TranslationRequestCount",
 "UnderstandCount"=excluded."UnderstandCount",
 "FamiliarityScore"=excluded."FamiliarityScore",
 "FamiliarityStage"=excluded."FamiliarityStage",
 "LastExposedAt"=excluded."LastExposedAt",
 "LastTranslationAt"=excluded."LastTranslationAt",
 "LastUnderstandAt"=excluded."LastUnderstandAt",
 "UpdatedAt"=now();
end $$;

create or replace function public."P132_PrepareArticle"(p_article_id bigint)
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
 body:=coalesce(art."ContentText",art."Summary",'');
 new_rate:=least(0.10,greatest(0.005,new_rate));
 -- New vocabulary quota is independent of already-immersed vocabulary.
 new_budget:=least(10,greatest(1,ceil(length(body)::numeric*new_rate/2.0)::int));
 -- Review words are an independent lane; enough to reinforce without flooding a short article.
 review_budget:=least(6,greatest(1,ceil(length(body)::numeric/180.0)::int));

 create temporary table if not exists pg_temp.p132_selected(
   "OccurrenceID" bigint primary key,"ConceptID" bigint,"OriginalText" text,
   "StartOffset" int,"EndOffset" int,"FormID" bigint,"SurfaceForm" text,"Reading" text,
   state text,show_understand boolean
 ) on commit drop;
 truncate pg_temp.p132_selected;

 -- 1) Immersed: latest evidence is understand. Does NOT consume new/review quota.
 insert into pg_temp.p132_selected
 select o."OccurrenceID",o."ConceptID",o."OriginalText",o."StartOffset",o."EndOffset",
        f."FormID",f."SurfaceForm",f."Reading",'immersed',false
 from public."TblP132ArticleOccurrence" o
 join public."TblP132VocabularyConcept" c on c."ConceptID"=o."ConceptID"
 join public."TblP132ConceptInfiltrationPolicy" p
   on p."ConceptID"=o."ConceptID" and p."TargetLanguage"=lang
   and p."Phase1Eligible" and p."SuitabilityGrade" in('A','B')
 join lateral(
   select * from public."TblP132VocabularyForm" ff
   where ff."ConceptID"=o."ConceptID" and ff."LanguageCode"=lang and ff."IsActive"
   order by ff."IsPreferred" desc,ff."FormID" limit 1
 ) f on true
 join lateral(
   select v."EvidenceType"
   from public."TblP132LearnerEvidence" v
   join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
   where x."UserID"=uid and x."ConceptID"=o."ConceptID" and x."TargetLanguage"=lang
   order by v."OccurredAt" desc,v."EvidenceID" desc limit 1
 ) last_ev on last_ev."EvidenceType"='understand'
 where o."ArticleID"=p_article_id and o."ReplacementEligible"
   and c."IsActive" and c."ReviewStatus"='approved';

 -- 2) Review: latest evidence is translation_request. Highest re-exposure priority.
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

 -- 3) New/unconfirmed: only this lane consumes the learner's new-vocabulary quota.
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
     and not exists(
       select 1 from public."TblP132LearnerEvidence" v
       join public."TblP132Exposure" x on x."ExposureID"=v."ExposureID"
       where x."UserID"=uid and x."ConceptID"=o."ConceptID" and x."TargetLanguage"=lang
     )
     and not exists(select 1 from pg_temp.p132_selected z where z."OccurrenceID"=o."OccurrenceID")
   order by o."ConceptID",o."MatchConfidence" desc nulls last,o."StartOffset"
 ) q
 order by q."MatchConfidence" desc nulls last,q."StartOffset"
 limit new_budget;

 -- Resolve any overlapping spans deterministically, then render strictly by offset.
 for r in
   select s.* from pg_temp.p132_selected s
   order by s."StartOffset", (s."EndOffset"-s."StartOffset") desc
 loop
   if r."StartOffset">=cur then
     if r."StartOffset">cur then
       segments:=segments||jsonb_build_array(
         jsonb_build_object('text',substring(body from cur+1 for r."StartOffset"-cur)));
     end if;
     displaytext:=case when lang='ja' and r."Reading" is not null
       then r."SurfaceForm"||'（'||r."Reading"||'）' else r."SurfaceForm" end;
     insert into public."TblP132Exposure"
       ("UserID","ArticleID","OccurrenceID","ConceptID","DisplayedFormID","TargetLanguage",
        "PresentationMode","AlgorithmVersion","InfiltrationRate")
     values(uid,p_article_id,r."OccurrenceID",r."ConceptID",r."FormID",lang,
       case when lang='ja' and r."Reading" is not null then 'surface_reading' else 'surface' end,
       'P132-ALG-0.2',new_rate)
     returning "ExposureID" into eid;
     segments:=segments||jsonb_build_array(jsonb_build_object(
       'text',r."OriginalText",'display_text',displaytext,'exposure_id',eid,
       'learning_state',r.state,'show_understand',r.show_understand));
     perform public."P132_RecalculateVocabularyState"(uid,r."ConceptID",lang);
     cur:=r."EndOffset";
   end if;
 end loop;

 if cur<length(body) then
   segments:=segments||jsonb_build_array(jsonb_build_object('text',substring(body from cur+1)));
 end if;
 return jsonb_build_object(
   'article_id',art."ArticleID",'title',art."Title",'original_url',art."OriginalURL",
   'target_language',lang,'algorithm_version','P132-ALG-0.2',
   'new_vocabulary_rate',new_rate,'segments',segments);
end $$;

-- Revoke direct public access to the internal recalculation helper.
revoke all on function public."P132_RecalculateVocabularyState"(uuid,bigint,text) from public;
grant execute on function public."P132_RecalculateVocabularyState"(uuid,bigint,text) to authenticated;

-- Audit
select
  data_type,numeric_precision,numeric_scale
from information_schema.columns
where table_schema='public' and table_name='TblP132LearnerVocabularyState'
  and column_name='FamiliarityScore';
