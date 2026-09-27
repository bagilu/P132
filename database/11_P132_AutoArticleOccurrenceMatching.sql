-- P132 V0.2
-- 11_P132_AutoArticleOccurrenceMatching.sql
-- Automatic Phase-1 occurrence generation from the reviewed Shared Lexicon.
--
-- Design:
-- * Chinese source articles are matched against CanonicalZh.
-- * Only concepts with an active target-language form AND Phase1Eligible policy participate.
-- * Phrase/longest-match wins at the same/overlapping position.
-- * Existing manually curated occurrences are preserved and take precedence.
-- * This annotates semantic candidates; P132_PrepareArticle still decides what to foreignize.
-- * Exact lexical matching only. It does NOT pretend to solve Chinese word-sense disambiguation.

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
  if auth.uid() is null then raise exception 'Authentication required'; end if;

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

  -- Generate every exact occurrence. generate_series gives reliable character offsets
  -- without relying on regex byte/character position behavior.
  insert into pg_temp.p132_match_candidate
    ("ConceptID","OriginalText","StartOffset","EndOffset","TokenLength")
  select distinct c."ConceptID",c."CanonicalZh",
         pos-1,(pos-1)+char_length(c."CanonicalZh"),char_length(c."CanonicalZh")
  from public."TblP132VocabularyConcept" c
  cross join lateral generate_series(
    1,
    greatest(1,length(body)-char_length(c."CanonicalZh")+1)
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
      where f."ConceptID"=c."ConceptID" and f."LanguageCode" in('en','ja') and f."IsActive"
    );

  -- Existing curated/manual occurrences always win.
  delete from pg_temp.p132_match_candidate c
  using public."TblP132ArticleOccurrence" o
  where o."ArticleID"=p_article_id
    and c."StartOffset"<o."EndOffset" and c."EndOffset">o."StartOffset";

  -- Phrase-first / longest meaningful match.
  -- For equal-length overlaps, prefer the earlier span, then the lower ConceptID.
  delete from pg_temp.p132_match_candidate loser
  where exists(
    select 1 from pg_temp.p132_match_candidate winner
    where winner."ConceptID"<>loser."ConceptID"
      and winner."StartOffset"<loser."EndOffset"
      and winner."EndOffset">loser."StartOffset"
      and (
        winner."TokenLength">loser."TokenLength"
        or (winner."TokenLength"=loser."TokenLength" and winner."StartOffset"<loser."StartOffset")
        or (winner."TokenLength"=loser."TokenLength" and winner."StartOffset"=loser."StartOffset"
            and winner."ConceptID"<loser."ConceptID")
      )
  );

  insert into public."TblP132ArticleOccurrence"
    ("ArticleID","ConceptID","OriginalText","StartOffset","EndOffset",
     "ContextText","ReplacementEligible","MatchConfidence")
  select p_article_id,c."ConceptID",c."OriginalText",c."StartOffset",c."EndOffset",
         substring(body from greatest(1,c."StartOffset"-30)+1
                   for least(length(body),c."EndOffset"+30)-greatest(0,c."StartOffset"-30)),
         true,1.0000
  from pg_temp.p132_match_candidate c
  where not exists(
    select 1 from public."TblP132ArticleOccurrence" o
    where o."ArticleID"=p_article_id
      and c."StartOffset"<o."EndOffset" and c."EndOffset">o."StartOffset"
  )
  order by c."StartOffset"
  on conflict("ArticleID","StartOffset","EndOffset") do nothing;

  get diagnostics inserted_count=row_count;

  return jsonb_build_object(
    'article_id',p_article_id,
    'inserted',inserted_count,
    'matcher_version','P132-MATCH-0.2',
    'method','exact_canonical_zh_longest_match'
  );
end $$;

-- Batch helper for already stored published Chinese articles.
create or replace function public."P132_AnnotatePublishedArticles"(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare r record; n int:=0; total_inserted int:=0; result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  for r in
    select "ArticleID" from public."TblP132Article"
    where "IsPublished" and "LanguageCode"='zh-TW'
    order by "ArticleID"
    limit least(greatest(p_limit,1),500)
  loop
    result:=public."P132_AnnotateArticleOccurrences"(r."ArticleID");
    n:=n+1;
    total_inserted:=total_inserted+coalesce((result->>'inserted')::int,0);
  end loop;
  return jsonb_build_object('articles_processed',n,'occurrences_inserted',total_inserted,
                            'matcher_version','P132-MATCH-0.2');
end $$;

revoke all on function public."P132_AnnotateArticleOccurrences"(bigint) from public;
revoke all on function public."P132_AnnotatePublishedArticles"(integer) from public;
grant execute on function public."P132_AnnotateArticleOccurrences"(bigint) to authenticated;
grant execute on function public."P132_AnnotatePublishedArticles"(integer) to authenticated;

-- Audit: automatic/manual occurrences currently available.
select a."ExternalID",count(o."OccurrenceID") as "OccurrenceCount"
from public."TblP132Article" a
left join public."TblP132ArticleOccurrence" o on o."ArticleID"=a."ArticleID"
where a."IsPublished"
group by a."ArticleID",a."ExternalID"
order by a."ArticleID";
