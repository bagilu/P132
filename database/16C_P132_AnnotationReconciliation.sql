-- P132 SQL16C
-- 16C_P132_AnnotationReconciliation.sql
-- Annotation Reconciliation V0.1
--
-- Principle:
--   Annotation may become invalid as linguistic analysis improves.
--   Historical learner Exposure / Evidence must not be deleted.
--
-- This migration adds provenance/lifecycle metadata to Chinese ArticleOccurrence,
-- invalidates conflicting automatic lexical annotations instead of deleting them,
-- and integrates reconciliation into the Chinese annotation pipeline.

alter table public."TblP132ArticleOccurrence"
  add column if not exists "AnnotationMethod" text,
  add column if not exists "MatcherVersion" text,
  add column if not exists "AnnotationVersion" text,
  add column if not exists "InvalidatedAt" timestamptz,
  add column if not exists "InvalidationReason" text;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='ChkP132OccurrenceAnnotationMethod'
      and conrelid='public."TblP132ArticleOccurrence"'::regclass
  ) then
    alter table public."TblP132ArticleOccurrence"
      add constraint "ChkP132OccurrenceAnnotationMethod"
      check ("AnnotationMethod" is null or "AnnotationMethod" in
        ('manual','lexical_match','nlp','ai'));
  end if;
end $$;

create index if not exists "IdxP132OccurrenceLifecycle"
  on public."TblP132ArticleOccurrence"
    ("ArticleID","ReplacementEligible","AnnotationMethod","StartOffset","EndOffset");

-- Existing rows predate provenance. Do not guess whether they were manual or automatic.
-- They remain NULL/legacy and are therefore NOT automatically invalidated by SQL16C.

create or replace function public."P132_ReconcileArticleOccurrences"(p_article_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  a public."TblP132Article";
  invalidated_count integer:=0;
begin
  select * into a
  from public."TblP132Article"
  where "ArticleID"=p_article_id and "IsPublished";
  if not found then raise exception 'Article not found'; end if;

  if a."LanguageCode"<>'zh-TW' then
    return jsonb_build_object(
      'article_id',p_article_id,'invalidated',0,
      'reason','non_zh_tw_article','reconciler_version','P132-RECON-0.1'
    );
  end if;

  -- Conservative policy:
  -- * Only rows explicitly known to be automatic lexical matches are touched.
  -- * Exact whole-span matches remain eligible.
  -- * Partial overlap with a protected span is invalidated.
  -- * No occurrence is deleted; therefore Exposure/Evidence history survives.
  update public."TblP132ArticleOccurrence" o
  set "ReplacementEligible"=false,
      "InvalidatedAt"=coalesce(o."InvalidatedAt",now()),
      "InvalidationReason"='protected_span_partial_overlap'
  where o."ArticleID"=p_article_id
    and o."ReplacementEligible"
    and o."AnnotationMethod"='lexical_match'
    and exists(
      select 1
      from public."TblP132ArticleProtectedSpan" p
      where p."ArticleID"=p_article_id
        and o."StartOffset"<p."EndOffset"
        and o."EndOffset">p."StartOffset"
        and not(
          o."StartOffset"=p."StartOffset"
          and o."EndOffset"=p."EndOffset"
        )
    );

  get diagnostics invalidated_count=row_count;

  return jsonb_build_object(
    'article_id',p_article_id,
    'invalidated',invalidated_count,
    'reconciler_version','P132-RECON-0.1',
    'policy','invalidate_automatic_partial_overlap_preserve_history'
  );
end $$;

revoke all on function public."P132_ReconcileArticleOccurrences"(bigint) from public;
revoke all on function public."P132_ReconcileArticleOccurrences"(bigint) from anon;
revoke all on function public."P132_ReconcileArticleOccurrences"(bigint) from authenticated;
grant execute on function public."P132_ReconcileArticleOccurrences"(bigint) to service_role;

-- Matcher V0.4: protected-span aware + provenance-aware.
create or replace function public."P132_AnnotateArticleOccurrences"(p_article_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  a public."TblP132Article";
  body text;
  inserted_count integer:=0;
begin
  select * into a
  from public."TblP132Article"
  where "ArticleID"=p_article_id and "IsPublished";

  if not found then raise exception 'Article not found'; end if;
  if a."LanguageCode"<>'zh-TW' then
    return jsonb_build_object('article_id',p_article_id,'inserted',0,'reason','non_zh_tw_article');
  end if;

  body:=coalesce(a."ContentText",a."Summary",'');
  if body='' then
    return jsonb_build_object('article_id',p_article_id,'inserted',0,'reason','empty_article');
  end if;

  create temporary table if not exists pg_temp.p132_match_candidate(
    "ConceptID" bigint,
    "OriginalText" text,
    "StartOffset" integer,
    "EndOffset" integer,
    "TokenLength" integer,
    primary key("ConceptID","StartOffset","EndOffset")
  ) on commit drop;
  truncate pg_temp.p132_match_candidate;

  insert into pg_temp.p132_match_candidate
    ("ConceptID","OriginalText","StartOffset","EndOffset","TokenLength")
  select distinct c."ConceptID",c."CanonicalZh",
         pos-1,(pos-1)+char_length(c."CanonicalZh"),char_length(c."CanonicalZh")
  from public."TblP132VocabularyConcept" c
  cross join lateral generate_series(
    1,greatest(1,length(body)-char_length(c."CanonicalZh")+1)
  ) pos
  where c."IsActive" and c."ReviewStatus"='approved'
    and char_length(c."CanonicalZh")>=1
    and substring(body from pos for char_length(c."CanonicalZh"))=c."CanonicalZh"
    and exists(
      select 1 from public."TblP132ConceptInfiltrationPolicy" p
      where p."ConceptID"=c."ConceptID" and p."Phase1Eligible"
        and p."SuitabilityGrade" in('A','B')
    )
    and exists(
      select 1 from public."TblP132VocabularyForm" f
      where f."ConceptID"=c."ConceptID"
        and f."LanguageCode" in('en','ja') and f."IsActive"
    );

  delete from pg_temp.p132_match_candidate c
  using public."TblP132ArticleProtectedSpan" p
  where p."ArticleID"=p_article_id
    and c."StartOffset"<p."EndOffset"
    and c."EndOffset">p."StartOffset"
    and not(c."StartOffset"=p."StartOffset" and c."EndOffset"=p."EndOffset");

  -- Only currently eligible existing occurrences block new matching.
  -- Invalidated historical rows remain in place for Evidence integrity.
  delete from pg_temp.p132_match_candidate c
  using public."TblP132ArticleOccurrence" o
  where o."ArticleID"=p_article_id
    and o."ReplacementEligible"
    and c."StartOffset"<o."EndOffset" and c."EndOffset">o."StartOffset";

  delete from pg_temp.p132_match_candidate loser
  where exists(
    select 1 from pg_temp.p132_match_candidate winner
    where winner."ConceptID"<>loser."ConceptID"
      and winner."StartOffset"<loser."EndOffset"
      and winner."EndOffset">loser."StartOffset"
      and (
        winner."TokenLength">loser."TokenLength"
        or (winner."TokenLength"=loser."TokenLength" and winner."StartOffset"<loser."StartOffset")
        or (winner."TokenLength"=loser."TokenLength"
            and winner."StartOffset"=loser."StartOffset"
            and winner."ConceptID"<loser."ConceptID")
      )
  );

  insert into public."TblP132ArticleOccurrence"
    ("ArticleID","ConceptID","OriginalText","StartOffset","EndOffset",
     "ContextText","ReplacementEligible","MatchConfidence",
     "AnnotationMethod","MatcherVersion","AnnotationVersion")
  select p_article_id,c."ConceptID",c."OriginalText",c."StartOffset",c."EndOffset",
         substring(body from greatest(1,c."StartOffset"-30)+1
                   for least(length(body),c."EndOffset"+30)-greatest(0,c."StartOffset"-30)),
         true,1.0000,'lexical_match','P132-MATCH-0.4','P132-ANNOT-0.2'
  from pg_temp.p132_match_candidate c
  where not exists(
    select 1 from public."TblP132ArticleOccurrence" o
    where o."ArticleID"=p_article_id
      and o."ReplacementEligible"
      and c."StartOffset"<o."EndOffset" and c."EndOffset">o."StartOffset"
  )
  order by c."StartOffset"
  on conflict("ArticleID","StartOffset","EndOffset") do update set
    "ReplacementEligible"=true,
    "MatchConfidence"=excluded."MatchConfidence",
    "AnnotationMethod"=coalesce(public."TblP132ArticleOccurrence"."AnnotationMethod",excluded."AnnotationMethod"),
    "MatcherVersion"=excluded."MatcherVersion",
    "AnnotationVersion"=excluded."AnnotationVersion",
    "InvalidatedAt"=null,
    "InvalidationReason"=null;

  get diagnostics inserted_count=row_count;

  return jsonb_build_object(
    'article_id',p_article_id,
    'rows_inserted_or_refreshed',inserted_count,
    'matcher_version','P132-MATCH-0.4',
    'annotation_version','P132-ANNOT-0.2',
    'method','protected_span_provenance_exact_canonical_zh_longest_match'
  );
end $$;

-- Pipeline V0.3:
-- protected spans -> reconcile stale automatic annotations -> fresh lexical matching.
create or replace function public."P132_AnnotateArticle"(p_article_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare p jsonb; r jsonb; m jsonb;
begin
  p:=public."P132_DetectProtectedSpans"(p_article_id);
  r:=public."P132_ReconcileArticleOccurrences"(p_article_id);
  m:=public."P132_AnnotateArticleOccurrences"(p_article_id);
  return jsonb_build_object(
    'article_id',p_article_id,
    'protected_span_result',p,
    'reconciliation_result',r,
    'lexical_match_result',m,
    'pipeline_version','P132-LING-0.3'
  );
end $$;

create or replace function public."P132_AnnotatePublishedArticles"(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare r record; n int:=0; total_changed int:=0; total_invalidated int:=0; result jsonb;
begin
  for r in
    select "ArticleID" from public."TblP132Article"
    where "IsPublished" and "LanguageCode"='zh-TW'
    order by "ArticleID"
    limit least(greatest(p_limit,1),500)
  loop
    result:=public."P132_AnnotateArticle"(r."ArticleID");
    n:=n+1;
    total_changed:=total_changed+
      coalesce((result->'lexical_match_result'->>'rows_inserted_or_refreshed')::int,0);
    total_invalidated:=total_invalidated+
      coalesce((result->'reconciliation_result'->>'invalidated')::int,0);
  end loop;
  return jsonb_build_object(
    'articles_processed',n,
    'occurrence_rows_inserted_or_refreshed',total_changed,
    'occurrences_invalidated',total_invalidated,
    'matcher_version','P132-MATCH-0.4',
    'annotation_version','P132-ANNOT-0.2',
    'reconciler_version','P132-RECON-0.1',
    'pipeline_version','P132-LING-0.3'
  );
end $$;

revoke all on function public."P132_AnnotateArticleOccurrences"(bigint) from public;
revoke all on function public."P132_AnnotateArticleOccurrences"(bigint) from anon;
revoke all on function public."P132_AnnotateArticleOccurrences"(bigint) from authenticated;
revoke all on function public."P132_AnnotateArticle"(bigint) from public;
revoke all on function public."P132_AnnotateArticle"(bigint) from anon;
revoke all on function public."P132_AnnotateArticle"(bigint) from authenticated;
revoke all on function public."P132_AnnotatePublishedArticles"(integer) from public;
revoke all on function public."P132_AnnotatePublishedArticles"(integer) from anon;
revoke all on function public."P132_AnnotatePublishedArticles"(integer) from authenticated;

grant execute on function public."P132_AnnotateArticleOccurrences"(bigint) to service_role;
grant execute on function public."P132_AnnotateArticle"(bigint) to service_role;
grant execute on function public."P132_AnnotatePublishedArticles"(integer) to service_role;

-- IMPORTANT legacy migration policy:
-- Pre-SQL16C rows have AnnotationMethod IS NULL. They are intentionally not guessed.
-- The known Article 17 / 湖 occurrence was manually disabled during regression testing
-- and remains valid historical evidence. New automatic annotations receive provenance,
-- so future reconciliation is automatic and safe.

select
  'SQL16C installed' as "Status",
  'P132-LING-0.3' as "PipelineVersion",
  'P132-MATCH-0.4' as "MatcherVersion",
  'P132-RECON-0.1' as "ReconcilerVersion";
