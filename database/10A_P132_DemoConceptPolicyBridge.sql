-- P132 V0.2
-- 10A_P132_DemoConceptPolicyBridge.sql
-- Compatibility bridge: V0.1/V0.1.1 demo ArticleOccurrences point to demo concepts
-- created before the Shared Lexicon policy layer existed.
-- Keep those concept IDs stable so existing Exposure/Evidence remains valid.

with demo("CanonicalZh","MeaningZh") as (values
('大學','提供高等教育、研究與公共服務的教育機構'),
('學生','在教育機構中學習的人'),
('研究','有系統地探索問題並建立知識的活動'),
('科技','運用科學知識解決實際問題的技術與方法'),
('資料','可被記錄、分析與使用的資訊材料'),
('系統','由相互關聯部分組成並共同運作的整體'),
('能源','可用來產生動力、熱或電力的資源'),
('環境','生物與人類生活周遭的自然及社會條件'),
('企業','從事生產、服務或商業活動的組織'),
('市場','買賣雙方交換商品、服務或資源的環境'),
('投資','投入資源以期待未來產生報酬的行為'),
('旅行','離開日常所在地前往其他地方的活動'),
('旅客','為旅行而前往其他地方的人'),
('文化','群體共享並傳承的生活方式、價值與表達')
),
concepts as (
 select c."ConceptID"
 from demo d
 join public."TblP132VocabularyConcept" c
   on c."CanonicalZh"=d."CanonicalZh" and c."MeaningZh"=d."MeaningZh"
 where c."IsActive" and c."ReviewStatus"='approved'
),
langs("TargetLanguage") as (values('en'),('ja'))
insert into public."TblP132ConceptInfiltrationPolicy"
 ("ConceptID","TargetLanguage","SuitabilityGrade","Phase1Eligible",
  "SuitabilityReason","ReviewedAt","UpdatedAt")
select c."ConceptID",l."TargetLanguage",'A',true,
 'V0.2 compatibility bridge for reviewed demo vocabulary used by existing ArticleOccurrences.',
 now(),now()
from concepts c cross join langs l
where exists(
 select 1 from public."TblP132VocabularyForm" f
 where f."ConceptID"=c."ConceptID"
   and f."LanguageCode"=l."TargetLanguage" and f."IsActive"
)
on conflict("ConceptID","TargetLanguage") do update set
 "SuitabilityGrade"='A',"Phase1Eligible"=true,
 "SuitabilityReason"=excluded."SuitabilityReason",
 "ReviewedAt"=now(),"UpdatedAt"=now();

-- Audit the five seeded demo articles.
select a."ExternalID",o."OriginalText",f."LanguageCode",f."SurfaceForm",
       p."SuitabilityGrade",p."Phase1Eligible"
from public."TblP132ArticleOccurrence" o
join public."TblP132Article" a on a."ArticleID"=o."ArticleID"
join public."TblP132VocabularyForm" f on f."ConceptID"=o."ConceptID" and f."IsPreferred" and f."IsActive"
left join public."TblP132ConceptInfiltrationPolicy" p
  on p."ConceptID"=o."ConceptID" and p."TargetLanguage"=f."LanguageCode"
where a."ExternalID" in('demo-002','demo-003','demo-004','demo-005','demo-006')
order by a."ExternalID",o."StartOffset",f."LanguageCode";
