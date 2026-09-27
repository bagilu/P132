-- P132 V0.1.1: five additional demo articles.
-- Safe to re-run: articles/forms/occurrences are inserted only when absent.
with s as (select "SourceID" from public."TblP132NewsSource" where "FeedURL"='https://example.invalid/p132-demo-rss' limit 1),
d(external_id,title,summary,content,category) as (values
('demo-002','大學推動跨領域研究','大學鼓勵學生參與跨領域研究。','大學鼓勵學生參與跨領域研究，並透過課程與專題培養解決問題的能力。','education'),
('demo-003','人工智慧協助資料分析','新科技正在改變資料分析與資訊系統。','人工智慧技術快速發展，許多團隊開始利用科技分析資料，並改善資訊系統的使用方式。','technology'),
('demo-004','城市推動再生能源','環境政策與能源轉型成為重要議題。','城市推動新的環境政策，希望增加再生能源使用，並降低長期能源成本。','environment'),
('demo-005','企業觀察市場與投資','企業依市場變化調整投資方向。','企業持續觀察市場變化，評估新的投資機會，也關注消費者需求與產業發展。','business'),
('demo-006','花蓮旅遊與地方文化','旅客透過旅行認識花蓮文化。','許多旅客來到花蓮旅行，除了欣賞自然景觀，也透過地方活動認識不同文化。','travel'))
insert into public."TblP132Article"("SourceID","ExternalID","Title","Summary","ContentText","OriginalURL","PublishedAt","Category")
select s."SourceID",d.external_id,d.title,d.summary,d.content,'https://example.invalid/'||d.external_id,now(),d.category from s cross join d
on conflict("SourceID","ExternalID") do nothing;

with d(zh,meaning,pos,domain) as (values
('大學','提供高等教育、研究與公共服務的教育機構','noun','education'),('學生','在教育機構中學習的人','noun','education'),('研究','有系統地探索問題並建立知識的活動','noun','education'),('科技','運用科學知識解決實際問題的技術與方法','noun','technology'),('資料','可被記錄、分析與使用的資訊材料','noun','technology'),('系統','由相互關聯部分組成並共同運作的整體','noun','technology'),('能源','可用來產生動力、熱或電力的資源','noun','environment'),('環境','生物與人類生活周遭的自然及社會條件','noun','environment'),('企業','從事生產、服務或商業活動的組織','noun','business'),('市場','買賣雙方交換商品、服務或資源的環境','noun','business'),('投資','投入資源以期待未來產生報酬的行為','noun','business'),('旅行','離開日常所在地前往其他地方的活動','noun','travel'),('旅客','為旅行而前往其他地方的人','noun','travel'),('文化','群體共享並傳承的生活方式、價值與表達','noun','culture'))
insert into public."TblP132VocabularyConcept"("CanonicalZh","MeaningZh","PartOfSpeech","Domain")
select d.zh,d.meaning,d.pos,d.domain from d where not exists(select 1 from public."TblP132VocabularyConcept" c where c."CanonicalZh"=d.zh and c."MeaningZh"=d.meaning);

with f(zh,lang,surface,lemma,reading) as (values
('大學','en','university','university',null),('大學','ja','大学','大学','だいがく'),('學生','en','student','student',null),('學生','ja','学生','学生','がくせい'),('研究','en','research','research',null),('研究','ja','研究','研究','けんきゅう'),('科技','en','technology','technology',null),('科技','ja','技術','技術','ぎじゅつ'),('資料','en','data','data',null),('資料','ja','データ','データ','データ'),('系統','en','system','system',null),('系統','ja','システム','システム','システム'),('能源','en','energy','energy',null),('能源','ja','エネルギー','エネルギー','エネルギー'),('環境','en','environment','environment',null),('環境','ja','環境','環境','かんきょう'),('企業','en','company','company',null),('企業','ja','企業','企業','きぎょう'),('市場','en','market','market',null),('市場','ja','市場','市場','しじょう'),('投資','en','investment','investment',null),('投資','ja','投資','投資','とうし'),('旅行','en','travel','travel',null),('旅行','ja','旅行','旅行','りょこう'),('旅客','en','visitor','visitor',null),('旅客','ja','旅行者','旅行者','りょこうしゃ'),('文化','en','culture','culture',null),('文化','ja','文化','文化','ぶんか'))
insert into public."TblP132VocabularyForm"("ConceptID","LanguageCode","SurfaceForm","Lemma","Reading","IsPreferred")
select c."ConceptID",f.lang,f.surface,f.lemma,f.reading,true from f join public."TblP132VocabularyConcept" c on c."CanonicalZh"=f.zh and c."IsActive"
where not exists(select 1 from public."TblP132VocabularyForm" x where x."ConceptID"=c."ConceptID" and x."LanguageCode"=f.lang and x."SurfaceForm"=f.surface);

with wanted(external_id,zh,sentence_index) as (values
('demo-002','大學',1),('demo-002','學生',1),('demo-002','研究',1),('demo-003','科技',1),('demo-003','資料',1),('demo-003','系統',1),('demo-004','環境',1),('demo-004','政策',1),('demo-004','能源',1),('demo-005','企業',1),('demo-005','市場',1),('demo-005','投資',1),('demo-006','旅客',1),('demo-006','旅行',1),('demo-006','文化',1)),
rows as (select a."ArticleID",a."ContentText",w.zh,w.sentence_index,c."ConceptID",position(w.zh in a."ContentText")-1 as start_offset from wanted w join public."TblP132Article" a on a."ExternalID"=w.external_id join public."TblP132VocabularyConcept" c on c."CanonicalZh"=w.zh and c."IsActive" and c."ReviewStatus"='approved')
insert into public."TblP132ArticleOccurrence"("ArticleID","ConceptID","OriginalText","StartOffset","EndOffset","SentenceIndex","ContextText","MatchConfidence")
select "ArticleID","ConceptID",zh,start_offset,start_offset+char_length(zh),sentence_index,"ContentText",1.0 from rows where start_offset>=0
on conflict("ArticleID","StartOffset","EndOffset") do nothing;
