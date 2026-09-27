-- P132 V0.2
-- 13A_P132_Seed_CNA_RSS_Sources.sql
-- Initial real-world RSS sources for ingestion testing.
-- Feed URLs are those published on CNA's official RSS service page.
-- Idempotent: FeedURL is the natural key.

insert into public."TblP132NewsSource"
  ("SourceName","FeedURL","WebsiteURL","DefaultCategory","LanguageCode","IsActive","UpdatedAt")
values
  ('中央社－生活','https://feeds.feedburner.com/rsscna/lifehealth','https://www.cna.com.tw/','生活','zh-TW',true,now()),
  ('中央社－科技','https://feeds.feedburner.com/rsscna/technology','https://www.cna.com.tw/','科技','zh-TW',true,now()),
  ('中央社－文化','https://feeds.feedburner.com/rsscna/culture','https://www.cna.com.tw/','文化','zh-TW',true,now())
on conflict("FeedURL") do update set
  "SourceName"=excluded."SourceName",
  "WebsiteURL"=excluded."WebsiteURL",
  "DefaultCategory"=excluded."DefaultCategory",
  "LanguageCode"=excluded."LanguageCode",
  "IsActive"=excluded."IsActive",
  "UpdatedAt"=now();

select "SourceID","SourceName","FeedURL","DefaultCategory","LanguageCode","IsActive"
from public."TblP132NewsSource"
where "FeedURL" in(
  'https://feeds.feedburner.com/rsscna/lifehealth',
  'https://feeds.feedburner.com/rsscna/technology',
  'https://feeds.feedburner.com/rsscna/culture'
)
order by "SourceID";
