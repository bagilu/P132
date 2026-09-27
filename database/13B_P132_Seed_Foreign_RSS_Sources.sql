-- P132 V0.2
-- 13B_P132_Seed_Foreign_RSS_Sources.sql
-- First foreign-language RSS ingestion test sources.
-- Verified against the publishers' official RSS pages on 2026-09-27.
-- SourceID 5/6 are reserved here for the P132 admin console.

do $$
begin
  if exists(select 1 from public."TblP132NewsSource" where "SourceID"=5 and "FeedURL"<>'https://learningenglish.voanews.com/api/zmg_pl-vomx-tpeymtm') then
    raise exception 'P132 SourceID 5 is already occupied by another source';
  end if;
  if exists(select 1 from public."TblP132NewsSource" where "SourceID"=6 and "FeedURL"<>'https://www.nippon.com/ja/rss-others/news.xml') then
    raise exception 'P132 SourceID 6 is already occupied by another source';
  end if;
end $$;

insert into public."TblP132NewsSource"
 ("SourceID","SourceName","FeedURL","WebsiteURL","DefaultCategory","LanguageCode","IsActive","UpdatedAt")
values
 (5,'VOA Learning English－Science & Technology','https://learningenglish.voanews.com/api/zmg_pl-vomx-tpeymtm','https://learningenglish.voanews.com/','Science & Technology','en',true,now()),
 (6,'nippon.com 日本語－News','https://www.nippon.com/ja/rss-others/news.xml','https://www.nippon.com/ja/','News','ja',true,now())
on conflict("SourceID") do update set
 "SourceName"=excluded."SourceName","FeedURL"=excluded."FeedURL","WebsiteURL"=excluded."WebsiteURL",
 "DefaultCategory"=excluded."DefaultCategory","LanguageCode"=excluded."LanguageCode",
 "IsActive"=excluded."IsActive","UpdatedAt"=now();

select setval(pg_get_serial_sequence('public."TblP132NewsSource"','SourceID'),
 greatest((select max("SourceID") from public."TblP132NewsSource"),6),true);

select "SourceID","SourceName","FeedURL","LanguageCode","IsActive"
from public."TblP132NewsSource" where "SourceID" in(5,6) order by "SourceID";
