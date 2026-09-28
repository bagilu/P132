-- P132 SQL17D
-- Foreign Term Segmentation & Lexicon Growth Pipeline
-- Term-first: discover terms before requiring a Concept mapping.
-- English V0.1 uses deterministic tokenization + conservative phrase heuristics.
-- Japanese is intentionally NOT whitespace-tokenized; it remains lexicon/manual until
-- a Japanese-specific segmenter is introduced.
--
-- Principle:
-- Foreign Article -> Segmentation -> Multiword consolidation -> Occurrence
--                 -> optional Concept/Form mapping -> learner evidence/growth.
--
-- SQL17D is additive and does not modify SQL16/16B reconciliation work.

alter table public."TblP132ForeignTermOccurrence"
  drop constraint if exists "TblP132ForeignTermOccurrence_TermKind_check";
alter table public."TblP132ForeignTermOccurrence"
  add constraint "TblP132ForeignTermOccurrence_TermKind_check"
  check("TermKind" in('term','multiword','proper_noun','fixed_expression','function_word'));

alter table public."TblP132ForeignTermOccurrence"
  drop constraint if exists "TblP132ForeignTermOccurrence_AnnotationMethod_check";
alter table public."TblP132ForeignTermOccurrence"
  add constraint "TblP132ForeignTermOccurrence_AnnotationMethod_check"
  check("AnnotationMethod" in('manual','lexicon','rule','nlp','ai'));

-- Function words remain valid learnable terms. Classification lets the future UI
-- reduce visual prominence without pretending that they are not language.
create table if not exists public."TblP132EnglishFunctionWord"(
  "NormalizedTerm" text primary key,
  "Category" text not null default 'function_word',
  "IsActive" boolean not null default true,
  "CreatedAt" timestamptz not null default now()
);
alter table public."TblP132EnglishFunctionWord" enable row level security;
revoke all on table public."TblP132EnglishFunctionWord" from public,anon,authenticated;
grant select,insert,update,delete on table public."TblP132EnglishFunctionWord" to service_role;

insert into public."TblP132EnglishFunctionWord"("NormalizedTerm","Category") values
('a','article'),('an','article'),('the','article'),
('and','conjunction'),('or','conjunction'),('but','conjunction'),('if','conjunction'),
('because','conjunction'),('while','conjunction'),('when','conjunction'),('than','conjunction'),
('of','preposition'),('to','preposition'),('in','preposition'),('on','preposition'),
('at','preposition'),('by','preposition'),('for','preposition'),('from','preposition'),
('with','preposition'),('about','preposition'),('against','preposition'),('between','preposition'),
('into','preposition'),('through','preposition'),('during','preposition'),('before','preposition'),
('after','preposition'),('above','preposition'),('below','preposition'),('under','preposition'),
('over','preposition'),('as','preposition'),
('i','pronoun'),('you','pronoun'),('he','pronoun'),('she','pronoun'),('it','pronoun'),
('we','pronoun'),('they','pronoun'),('me','pronoun'),('him','pronoun'),('her','pronoun'),
('us','pronoun'),('them','pronoun'),('who','pronoun'),('which','pronoun'),('that','pronoun'),
('this','determiner'),('these','determiner'),('those','determiner'),
('my','determiner'),('your','determiner'),('his','determiner'),('its','determiner'),
('our','determiner'),('their','determiner'),
('is','auxiliary'),('am','auxiliary'),('are','auxiliary'),('was','auxiliary'),('were','auxiliary'),
('be','auxiliary'),('been','auxiliary'),('being','auxiliary'),('do','auxiliary'),('does','auxiliary'),
('did','auxiliary'),('have','auxiliary'),('has','auxiliary'),('had','auxiliary'),
('can','modal'),('could','modal'),('may','modal'),('might','modal'),('must','modal'),
('shall','modal'),('should','modal'),('will','modal'),('would','modal'),
('not','particle'),('no','determiner'),('yes','particle')
on conflict("NormalizedTerm") do update set
 "Category"=excluded."Category","IsActive"=true;

-- Best-effort bridge from a discovered surface term to an approved Shared Lexicon form.
-- Exact normalized form only; ambiguity is left unmapped rather than guessed.
create or replace function public."P132_MapForeignOccurrenceToLexicon"(p_occurrence_id bigint)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o public."TblP132ForeignTermOccurrence"; cid bigint; fid bigint; matches int;
begin
 select * into o from public."TblP132ForeignTermOccurrence"
 where "ForeignTermOccurrenceID"=p_occurrence_id;
 if not found then raise exception 'Foreign term occurrence not found'; end if;

 select count(distinct f."ConceptID") into matches
 from public."TblP132VocabularyForm" f
 join public."TblP132VocabularyConcept" c on c."ConceptID"=f."ConceptID"
 where f."LanguageCode"=o."LanguageCode" and f."IsActive"
   and c."IsActive" and c."ReviewStatus"='approved'
   and (case when o."LanguageCode"='en' then lower(btrim(coalesce(f."Lemma",f."SurfaceForm")))
             else btrim(coalesce(f."Lemma",f."SurfaceForm")) end)=o."NormalizedTerm";

 if matches=1 then
   select f."ConceptID",f."FormID" into cid,fid
   from public."TblP132VocabularyForm" f
   join public."TblP132VocabularyConcept" c on c."ConceptID"=f."ConceptID"
   where f."LanguageCode"=o."LanguageCode" and f."IsActive"
     and c."IsActive" and c."ReviewStatus"='approved'
     and (case when o."LanguageCode"='en' then lower(btrim(coalesce(f."Lemma",f."SurfaceForm")))
               else btrim(coalesce(f."Lemma",f."SurfaceForm")) end)=o."NormalizedTerm"
   order by f."IsPreferred" desc,f."FormID" limit 1;
   update public."TblP132ForeignTermOccurrence"
   set "ConceptID"=cid,"FormID"=fid
   where "ForeignTermOccurrenceID"=p_occurrence_id;
 end if;

 return jsonb_build_object('occurrence_id',p_occurrence_id,'candidate_concepts',matches,
   'mapped',matches=1,'concept_id',cid,'form_id',fid);
end $$;
revoke all on function public."P132_MapForeignOccurrenceToLexicon"(bigint) from public,anon,authenticated;
grant execute on function public."P132_MapForeignOccurrenceToLexicon"(bigint) to service_role;

-- English deterministic segmenter.
-- 1. preserve existing manual/lexicon/NLP/AI spans;
-- 2. detect simple capitalized multiword proper-name sequences;
-- 3. detect common lexical multiword patterns conservatively;
-- 4. fill remaining English word tokens, including function words;
-- 5. exact-map each discovered term to the Shared Lexicon where unambiguous.
--
-- This is intentionally a baseline segmenter, not POS tagging or semantic WSD.
create or replace function public."P132_SegmentEnglishArticle"(p_article_id bigint)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 a public."TblP132Article"; body text; m text[]; token text;
 s int;e int; search_from int:=1; n int:=0; mapped int:=0; oid bigint; k text;
begin
 select * into a from public."TblP132Article"
 where "ArticleID"=p_article_id and "IsPublished";
 if not found then raise exception 'Article not found'; end if;
 if a."LanguageCode"<>'en' then
   return jsonb_build_object('article_id',p_article_id,'reason','not_english','terms_inserted',0);
 end if;
 body:=coalesce(a."ContentText",a."Summary",'');
 if body='' then return jsonb_build_object('article_id',p_article_id,'reason','empty_article','terms_inserted',0); end if;

 -- Refresh only unexposed SQL17D rule rows. Historical exposed occurrences are immutable.
 delete from public."TblP132ForeignTermOccurrence" o
 where o."ArticleID"=p_article_id and o."AnnotationMethod"='rule'
   and o."AnnotationVersion"='P132-TERM-0.2'
   and not exists(select 1 from public."TblP132ForeignTermExposure" x
                  where x."ForeignTermOccurrenceID"=o."ForeignTermOccurrenceID");

 create temporary table if not exists pg_temp.p132_en_candidate(
   "SurfaceText" text,"NormalizedTerm" text,"StartOffset" int,"EndOffset" int,
   "TermKind" text,"Priority" int,"Confidence" numeric
 ) on commit drop;
 truncate pg_temp.p132_en_candidate;

 -- Capitalized 2-4 word sequences: conservative proper-noun/multiword candidates.
 -- Avoid sentence-level semantics; these are lexical-unit boundaries only.
 for m in select regexp_matches(body,
   '([A-Z][A-Za-z]+(?:[ -][A-Z][A-Za-z]+){1,3})','g')
 loop
   token:=m[1];
   s:=strpos(substring(body from search_from),token);
   if s>0 then
     s:=search_from+s-2; e:=s+char_length(token);
     insert into pg_temp.p132_en_candidate values
       (token,lower(token),s,e,'proper_noun',300,0.9500);
     search_from:=s+2;
   end if;
 end loop;

 -- Existing known multiword lexicon forms are high-priority phrase candidates.
 insert into pg_temp.p132_en_candidate
 select substring(body from g for char_length(f."SurfaceForm")),
        lower(btrim(f."SurfaceForm")),g-1,(g-1)+char_length(f."SurfaceForm"),
        'multiword',400,1.0000
 from public."TblP132VocabularyForm" f
 join public."TblP132VocabularyConcept" c on c."ConceptID"=f."ConceptID"
 cross join lateral generate_series(1,greatest(1,length(body)-char_length(f."SurfaceForm")+1)) g
 where f."LanguageCode"='en' and f."IsActive" and c."IsActive" and c."ReviewStatus"='approved'
   and f."SurfaceForm" ~ '[[:space:]]'
   and lower(substring(body from g for char_length(f."SurfaceForm")))=lower(f."SurfaceForm")
   and (g=1 or substring(body from g-1 for 1)!~'[A-Za-z0-9]')
   and (g+char_length(f."SurfaceForm")>length(body)
        or substring(body from g+char_length(f."SurfaceForm") for 1)!~'[A-Za-z0-9]');

 -- Token pass with exact offsets. Hyphenated/apostrophe words stay together.
 search_from:=1;
 for m in select regexp_matches(body,'([A-Za-z]+(?:[''’-][A-Za-z]+)*)','g')
 loop
   token:=m[1];
   s:=strpos(substring(body from search_from),token);
   if s>0 then
     s:=search_from+s-2; e:=s+char_length(token); k:=lower(token);
     insert into pg_temp.p132_en_candidate
     select token,k,s,e,
       case when exists(select 1 from public."TblP132EnglishFunctionWord" w
                        where w."NormalizedTerm"=k and w."IsActive")
            then 'function_word' else 'term' end,
       case when exists(select 1 from public."TblP132EnglishFunctionWord" w
                        where w."NormalizedTerm"=k and w."IsActive")
            then 50 else 100 end,
       case when exists(select 1 from public."TblP132EnglishFunctionWord" w
                        where w."NormalizedTerm"=k and w."IsActive")
            then 0.9900 else 0.9000 end;
     search_from:=e+1;
   end if;
 end loop;

 -- Insert candidates only if no higher-priority/longer candidate overlaps.
 -- Existing active annotation wins over new rule annotation.
 for m in
   select array[c."SurfaceText",c."NormalizedTerm",c."StartOffset"::text,c."EndOffset"::text,
                c."TermKind",c."Confidence"::text]
   from pg_temp.p132_en_candidate c
   where not exists(
     select 1 from pg_temp.p132_en_candidate z
     where z."StartOffset"<c."EndOffset" and z."EndOffset">c."StartOffset"
       and (z."Priority">c."Priority"
            or (z."Priority"=c."Priority"
                and (z."EndOffset"-z."StartOffset")>(c."EndOffset"-c."StartOffset")))
   )
   order by c."StartOffset",(c."EndOffset"-c."StartOffset") desc
 loop
   if not exists(
     select 1 from public."TblP132ForeignTermOccurrence" x
     where x."ArticleID"=p_article_id and x."IsActive"
       and x."StartOffset"<m[4]::int and x."EndOffset">m[3]::int
   ) then
     insert into public."TblP132ForeignTermOccurrence"
      ("ArticleID","LanguageCode","SurfaceText","NormalizedTerm","StartOffset","EndOffset",
       "TermKind","AnnotationMethod","AnnotationVersion","Confidence")
     values(p_article_id,'en',m[1],m[2],m[3]::int,m[4]::int,m[5],'rule','P132-TERM-0.2',m[6]::numeric)
     on conflict("ArticleID","StartOffset","EndOffset") do nothing
     returning "ForeignTermOccurrenceID" into oid;
     if oid is not null then
       n:=n+1;
       perform public."P132_MapForeignOccurrenceToLexicon"(oid);
       if exists(select 1 from public."TblP132ForeignTermOccurrence"
                 where "ForeignTermOccurrenceID"=oid and "ConceptID" is not null) then mapped:=mapped+1; end if;
       oid:=null;
     end if;
   end if;
 end loop;

 return jsonb_build_object('article_id',p_article_id,'language','en',
   'terms_inserted',n,'terms_mapped_to_lexicon',mapped,
   'annotation_version','P132-TERM-0.2',
   'policy','term_first_multiword_first_unknown_terms_survive');
end $$;
revoke all on function public."P132_SegmentEnglishArticle"(bigint) from public,anon,authenticated;
grant execute on function public."P132_SegmentEnglishArticle"(bigint) to service_role;

-- Unified entry point. English receives SQL17D segmentation.
-- Japanese deliberately keeps SQL17A lexicon/manual behavior until a Japanese-specific
-- tokenizer/segmenter is added; this avoids fake whitespace segmentation.
create or replace function public."P132_AnnotateForeignArticle"(p_article_id bigint)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare lang text; base jsonb; seg jsonb;
begin
 select "LanguageCode" into lang from public."TblP132Article"
 where "ArticleID"=p_article_id and "IsPublished";
 if not found then raise exception 'Article not found'; end if;
 if lang not in('en','ja') then
   return jsonb_build_object('article_id',p_article_id,'reason','not_foreign_source');
 end if;

 -- Known lexicon multiwords first.
 base:=public."P132_AnnotateForeignTerms"(p_article_id);
 if lang='en' then
   seg:=public."P132_SegmentEnglishArticle"(p_article_id);
   return jsonb_build_object('pipeline_version','P132-FOREIGN-ANNOT-0.2',
     'article_id',p_article_id,'language',lang,'lexicon_pass',base,'segmentation_pass',seg);
 end if;
 return jsonb_build_object('pipeline_version','P132-FOREIGN-ANNOT-0.2',
   'article_id',p_article_id,'language',lang,'lexicon_pass',base,
   'segmentation_pass',jsonb_build_object('status','deferred','reason','Japanese requires language-specific segmentation'));
end $$;
revoke all on function public."P132_AnnotateForeignArticle"(bigint) from public,anon,authenticated;
grant execute on function public."P132_AnnotateForeignArticle"(bigint) to service_role;

-- Audit view: coverage and unknown-term growth queue by article.
create or replace view public."VwP132ForeignTermCoverage" as
select a."ArticleID",a."Title",a."LanguageCode",
 count(o."ForeignTermOccurrenceID") filter(where o."IsActive") as "TermOccurrences",
 count(o."ForeignTermOccurrenceID") filter(where o."IsActive" and o."ConceptID" is not null) as "MappedOccurrences",
 count(o."ForeignTermOccurrenceID") filter(where o."IsActive" and o."ConceptID" is null) as "UnknownOccurrences",
 count(distinct o."NormalizedTerm") filter(where o."IsActive") as "DistinctTerms",
 count(distinct o."NormalizedTerm") filter(where o."IsActive" and o."ConceptID" is null) as "DistinctUnknownTerms"
from public."TblP132Article" a
left join public."TblP132ForeignTermOccurrence" o on o."ArticleID"=a."ArticleID"
where a."LanguageCode" in('en','ja')
group by a."ArticleID",a."Title",a."LanguageCode";

revoke all on public."VwP132ForeignTermCoverage" from public,anon,authenticated;
grant select on public."VwP132ForeignTermCoverage" to service_role;

-- Post-migration audit only.
select 'SQL17D installed' as "Status",
       'P132-FOREIGN-ANNOT-0.2' as "PipelineVersion",
       'English deterministic baseline; Japanese segmentation intentionally deferred' as "Scope";
