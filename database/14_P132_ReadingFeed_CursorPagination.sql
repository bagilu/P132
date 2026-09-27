-- P132 V1.0013
-- 14_P132_ReadingFeed_CursorPagination.sql
-- Language-filtered cursor pagination for the news feed.
-- Cursor uses SortAt + ArticleID, avoiding OFFSET drift as new RSS items arrive.

create or replace function public."P132_GetReadingFeedPage"(
  p_limit integer default 20,
  p_language_filter text default null,
  p_before_sort_at timestamptz default null,
  p_before_article_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  uid uuid:=auth.uid();
  lim integer:=least(50,greatest(1,coalesce(p_limit,20)));
  result jsonb;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if p_language_filter is not null and p_language_filter not in ('zh-TW','en','ja') then
    raise exception 'Unsupported language filter';
  end if;

  with ranked as (
    select a."ArticleID",a."Title",a."Summary",a."OriginalURL",a."PublishedAt",
           a."LanguageCode",a."SourceID",s."SourceName",
           coalesce(a."PublishedAt",a."FetchedAt",a."CreatedAt") as "SortAt"
    from public."TblP132Article" a
    join public."TblP132NewsSource" s on s."SourceID"=a."SourceID"
    where a."IsPublished"
      and (p_language_filter is null or a."LanguageCode"=p_language_filter)
  ), page as (
    select *
    from ranked r
    where p_before_sort_at is null
       or r."SortAt" < p_before_sort_at
       or (r."SortAt" = p_before_sort_at and r."ArticleID" < p_before_article_id)
    order by r."SortAt" desc,r."ArticleID" desc
    limit lim
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'article_id',"ArticleID",'title',"Title",'summary',"Summary",
    'original_url',"OriginalURL",'published_at',"PublishedAt",
    'language_code',"LanguageCode",'source_id',"SourceID",'source_name',"SourceName",
    'sort_at',"SortAt"
  ) order by "SortAt" desc,"ArticleID" desc),'[]'::jsonb)
  into result from page;
  return result;
end $$;

revoke all on function public."P132_GetReadingFeedPage"(integer,text,timestamptz,bigint) from public;
revoke all on function public."P132_GetReadingFeedPage"(integer,text,timestamptz,bigint) from anon;
grant execute on function public."P132_GetReadingFeedPage"(integer,text,timestamptz,bigint) to authenticated;

select routine_name
from information_schema.routines
where routine_schema='public' and routine_name='P132_GetReadingFeedPage';
