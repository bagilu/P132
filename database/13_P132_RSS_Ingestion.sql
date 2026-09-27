-- P132 V0.2
-- 13_P132_RSS_Ingestion.sql
-- Trusted RSS ingestion layer. The Edge Function/service role calls these RPCs.
-- Learners cannot import or mutate news content.

alter table public."TblP132NewsSource"
  add column if not exists "FetchError" text,
  add column if not exists "LastFetchStatus" text
    check ("LastFetchStatus" is null or "LastFetchStatus" in ('ok','error'));

create index if not exists "IdxP132ArticleSourcePublished"
  on public."TblP132Article"("SourceID","PublishedAt" desc);

-- Upsert one normalized RSS item. ExternalID should preferably be the feed GUID;
-- if absent, the Edge Function supplies a stable hash-derived ID.
create or replace function public."P132_UpsertRSSArticle"(
  p_source_id bigint,
  p_external_id text,
  p_title text,
  p_summary text,
  p_content_text text,
  p_original_url text,
  p_published_at timestamptz,
  p_category text default null,
  p_content_hash text default null
)
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare aid bigint;
begin
  if coalesce(trim(p_external_id),'')='' then raise exception 'ExternalID required'; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Title required'; end if;
  if coalesce(trim(p_original_url),'')='' then raise exception 'OriginalURL required'; end if;
  if not exists(select 1 from public."TblP132NewsSource"
                where "SourceID"=p_source_id and "IsActive") then
    raise exception 'Active source not found';
  end if;

  insert into public."TblP132Article"
    ("SourceID","ExternalID","Title","Summary","ContentText","OriginalURL",
     "PublishedAt","Category","LanguageCode","ContentHash","FetchedAt","IsPublished")
  select p_source_id,trim(p_external_id),trim(p_title),nullif(trim(p_summary),''),
         nullif(trim(p_content_text),''),trim(p_original_url),p_published_at,
         coalesce(nullif(trim(p_category),''),s."DefaultCategory"),
         s."LanguageCode",p_content_hash,now(),true
  from public."TblP132NewsSource" s where s."SourceID"=p_source_id
  on conflict("SourceID","ExternalID") do update set
    "Title"=excluded."Title",
    "Summary"=excluded."Summary",
    "ContentText"=excluded."ContentText",
    "OriginalURL"=excluded."OriginalURL",
    "PublishedAt"=excluded."PublishedAt",
    "Category"=excluded."Category",
    "LanguageCode"=excluded."LanguageCode",
    "ContentHash"=excluded."ContentHash",
    "FetchedAt"=now()
  returning "ArticleID" into aid;

  return aid;
end $$;

create or replace function public."P132_MarkRSSFetch"(
  p_source_id bigint,p_ok boolean,p_error text default null
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  update public."TblP132NewsSource"
  set "LastFetchedAt"=now(),
      "LastFetchStatus"=case when p_ok then 'ok' else 'error' end,
      "FetchError"=case when p_ok then null else left(coalesce(p_error,'Unknown error'),2000) end,
      "UpdatedAt"=now()
  where "SourceID"=p_source_id;
end $$;

-- Back-office only.
revoke all on function public."P132_UpsertRSSArticle"(bigint,text,text,text,text,text,timestamptz,text,text) from public;
revoke all on function public."P132_UpsertRSSArticle"(bigint,text,text,text,text,text,timestamptz,text,text) from anon;
revoke all on function public."P132_UpsertRSSArticle"(bigint,text,text,text,text,text,timestamptz,text,text) from authenticated;
grant execute on function public."P132_UpsertRSSArticle"(bigint,text,text,text,text,text,timestamptz,text,text) to service_role;

revoke all on function public."P132_MarkRSSFetch"(bigint,boolean,text) from public;
revoke all on function public."P132_MarkRSSFetch"(bigint,boolean,text) from anon;
revoke all on function public."P132_MarkRSSFetch"(bigint,boolean,text) from authenticated;
grant execute on function public."P132_MarkRSSFetch"(bigint,boolean,text) to service_role;

-- SQL Editor audit.
select column_name,data_type
from information_schema.columns
where table_schema='public' and table_name='TblP132NewsSource'
  and column_name in('FetchError','LastFetchStatus')
order by column_name;
