-- P132 V0.2 repair after the original 07 line-break parsing defect.
-- Run this once, then rerun corrected 07, then 08, then 09.
-- Scope: only source entries belonging to NAER_12YBE_EN_2000.
do $$
declare v_source_id bigint;
begin
  select "LexiconSourceID" into v_source_id
  from public."TblP132LexiconSource"
  where "SourceCode"='NAER_12YBE_EN_2000';

  if v_source_id is null then
    raise exception 'P132: NAER source missing; run 06 first.';
  end if;

  delete from public."TblP132VocabularySourceEntry"
  where "LexiconSourceID"=v_source_id;
end $$;

select count(*) as "RemainingNAERSourceEntries"
from public."TblP132VocabularySourceEntry" e
join public."TblP132LexiconSource" s
  on s."LexiconSourceID"=e."LexiconSourceID"
where s."SourceCode"='NAER_12YBE_EN_2000';
-- Expected: 0
