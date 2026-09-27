-- P132 V0.2
-- 09_P132_SharedLexicon_Basic_A.sql
-- Curated first batch of Phase-1 A-grade English Shared Lexicon concepts.
-- Prerequisites: 06, 07, 08.
-- Additive + rerunnable. Does NOT alter learner evidence or reading behavior.

do $$
declare
  r record;
  v_source_id bigint;
  v_entry_id bigint;
  v_concept_id bigint;
begin
  select "LexiconSourceID" into v_source_id
  from public."TblP132LexiconSource"
  where "SourceCode"='NAER_12YBE_EN_2000';

  if v_source_id is null then
    raise exception 'P132: run migrations 06 and 07 first.';
  end if;

  for r in
    select * from (values
-- English, CanonicalZh, MeaningZh, POS, Domain
('airport','機場','供飛機起降及旅客進出使用的機場','noun','transport'),
('animal','動物','動物','noun','general'),
('apple','蘋果','蘋果','noun','food'),
('April','四月','四月','noun','time'),
('arm','手臂','人的手臂','noun','body'),
('art','藝術','藝術','noun','culture'),
('August','八月','八月','noun','time'),
('baby','嬰兒','嬰兒','noun','people'),
('badminton','羽毛球','羽毛球運動','noun','sports'),
('banana','香蕉','香蕉','noun','food'),
('baseball','棒球','棒球運動','noun','sports'),
('basketball','籃球','籃球運動','noun','sports'),
('bathroom','浴室','浴室','noun','place'),
('beach','海灘','海灘','noun','geography'),
('bedroom','臥室','臥室','noun','place'),
('bee','蜜蜂','蜜蜂','noun','animal'),
('beef','牛肉','牛肉','noun','food'),
('bicycle (bike)','自行車','自行車；腳踏車','noun','transport'),
('bird','鳥','鳥類','noun','animal'),
('birthday','生日','生日','noun','life'),
('blackboard','黑板','黑板','noun','education'),
('blanket','毯子','毯子；毛毯','noun','object'),
('boat','船','小型船隻','noun','transport'),
('book','書','書籍','noun','education'),
('bookstore','書店','販售書籍的商店','noun','place'),
('bottle','瓶子','瓶子','noun','object'),
('boy','男孩','男孩','noun','people'),
('bread','麵包','麵包','noun','food'),
('breakfast','早餐','早餐','noun','food'),
('bridge','橋','橋梁','noun','infrastructure'),
('brother','兄弟','兄弟；哥哥或弟弟','noun','family'),
('bus','公車','公共汽車；公車','noun','transport'),
('butter','奶油','奶油','noun','food'),
('butterfly','蝴蝶','蝴蝶','noun','animal'),
('camera','相機','照相機；相機','noun','technology'),
('candle','蠟燭','蠟燭','noun','object'),
('car','汽車','汽車','noun','transport'),
('castle','城堡','城堡','noun','place'),
('cat','貓','貓','noun','animal'),
('cellphone','手機','行動電話；手機','noun','technology'),
('centimeter','公分','公分；厘米','noun','measurement'),
('chair','椅子','椅子','noun','object'),
('cheese','起司','起司；乳酪','noun','food'),
('chicken','雞','雞；雞肉（依語境）','noun','food'),
('child','兒童','兒童；孩子','noun','people'),
('China','中國','中國','proper_noun','geography'),
('Chinese','中文','中文；漢語（此 Concept 限語言義）','noun','language'),
('chocolate','巧克力','巧克力','noun','food'),
('Christmas','聖誕節','聖誕節','proper_noun','festival'),
('church','教堂','基督宗教教堂','noun','place'),
('city','城市','城市','noun','geography'),
('classroom','教室','教室','noun','education'),
('clothes','衣服','衣服；衣物','noun','object'),
('cloud','雲','雲','noun','weather'),
('coffee','咖啡','咖啡','noun','food'),
('computer','電腦','電腦；計算機','noun','technology'),
('cookie','餅乾','餅乾','noun','food'),
('country','國家','國家','noun','geography'),
('cousin','堂表兄弟姊妹','堂／表兄弟姊妹','noun','family'),
('cow','牛','牛','noun','animal'),
('daughter','女兒','女兒','noun','family'),
('day','日','一天；日','noun','time'),
('December','十二月','十二月','noun','time'),
('dentist','牙醫','牙醫師','noun','occupation'),
('department store','百貨公司','百貨公司','noun','place'),
('desk','書桌','書桌；桌子','noun','object'),
('dictionary','字典','字典；辭典','noun','education'),
('dinner','晚餐','晚餐','noun','food'),
('doctor (Dr.)','醫師','醫師；醫生','noun','occupation'),
('dog','狗','狗','noun','animal'),
('dollar','元','以 dollar 為名稱的貨幣單位','noun','money'),
('door','門','門','noun','object'),
('driver','駕駛','駕駛者；司機','noun','occupation'),
('duck','鴨','鴨','noun','animal'),
('ear','耳朵','耳朵','noun','body'),
('earthquake','地震','地震','noun','environment'),
('east','東方','東方；東部','noun','direction'),
('Easter','復活節','復活節','proper_noun','festival'),
('egg','蛋','蛋；雞蛋','noun','food'),
('elementary school','小學','國民小學；小學','noun','education'),
('elephant','大象','大象','noun','animal'),
('e-mail','電子郵件','電子郵件','noun','technology'),
('engineer','工程師','工程師','noun','occupation'),
('English','英語','英語；英文（此 Concept 限語言義）','noun','language'),
('envelope','信封','信封','noun','object'),
('eraser','橡皮擦','橡皮擦','noun','education'),
('eye','眼睛','眼睛','noun','body'),
('factory','工廠','工廠','noun','business'),
('family','家庭','家庭；家人','noun','family'),
('farmer','農民','農民；農夫','noun','occupation'),
('February','二月','二月','noun','time'),
('festival','節慶','節日；節慶','noun','culture'),
('finger','手指','手指','noun','body'),
('fish','魚','魚','noun','animal'),
('flower','花','花朵','noun','nature'),
('food','食物','食物','noun','food'),
('fork','叉子','餐叉；叉子','noun','object'),
('Friday','星期五','星期五','noun','time'),
('friend','朋友','朋友','noun','people'),
('frog','青蛙','青蛙','noun','animal'),
('fruit','水果','水果','noun','food'),
('future','未來','未來','noun','time'),
('garden','花園','花園','noun','place'),
('garbage','垃圾','垃圾','noun','environment'),
('gift','禮物','禮物','noun','object'),
('girl','女孩','女孩','noun','people'),
('glasses','眼鏡','眼鏡','noun','object'),
('goat','山羊','山羊','noun','animal'),
('grape','葡萄','葡萄','noun','food'),
('grass','草','草；草地植物','noun','nature'),
('group','群組','群體；群組','noun','general'),
('guitar','吉他','吉他','noun','music'),
('hair','頭髮','頭髮','noun','body'),
('Halloween','萬聖節','萬聖節','proper_noun','festival'),
('hamburger (burger)','漢堡','漢堡','noun','food'),
('hand','手','手','noun','body'),
('hat','帽子','帽子','noun','object'),
('health','健康','健康','noun','health'),
('heart','心臟','心臟（身體器官義）','noun','body'),
('helicopter','直升機','直升機','noun','transport'),
('hill','山丘','山丘','noun','geography'),
('history','歷史','歷史','noun','education'),
('holiday','假日','假日；節假日','noun','time'),
('homework','作業','家庭作業','noun','education'),
('horse','馬','馬','noun','animal'),
('hospital','醫院','醫院','noun','health'),
('hotel','旅館','旅館；飯店','noun','travel'),
('hour','小時','小時','noun','time'),
('house','房屋','房屋；住宅','noun','place'),
('husband','丈夫','丈夫','noun','family'),
('ice cream','冰淇淋','冰淇淋','noun','food'),
('idea','想法','想法；主意','noun','general'),
('Internet (Net)','網際網路','網際網路；網路','noun','technology'),
('island','島嶼','島嶼','noun','geography'),
('jacket','夾克','夾克；外套','noun','object'),
('January','一月','一月','noun','time'),
('job','工作','職業；工作','noun','work'),
('juice','果汁','果汁','noun','food'),
('July','七月','七月','noun','time'),
('June','六月','六月','noun','time'),
('junior high school','國中','國民中學；國中','noun','education'),
('key','鑰匙','鑰匙','noun','object'),
('kilogram','公斤','公斤','noun','measurement'),
('kitchen','廚房','廚房','noun','place'),
('lake','湖','湖泊','noun','geography'),
('language','語言','語言','noun','language'),
('lemon','檸檬','檸檬','noun','food'),
('lesson','課程','一課；課程','noun','education'),
('library','圖書館','圖書館','noun','education'),
('lion','獅子','獅子','noun','animal'),
('living room','客廳','客廳','noun','place'),
('lunch','午餐','午餐','noun','food'),
('machine','機器','機器','noun','technology'),
('March','三月','三月','noun','time'),
('market','市場','市場','noun','business'),
('math (mathematics)','數學','數學','noun','education'),
('meal','餐','一餐；餐點','noun','food'),
('medicine','藥物','藥；藥物','noun','health'),
('meeting','會議','會議','noun','work'),
('member','成員','成員；會員','noun','organization'),
('menu','菜單','菜單','noun','food'),
('metro','捷運','都市捷運系統','noun','transport'),
('milk','牛奶','牛奶','noun','food'),
('minute','分鐘','分鐘','noun','time'),
('Monday','星期一','星期一','noun','time'),
('money','金錢','金錢；錢','noun','money'),
('monkey','猴子','猴子','noun','animal'),
('month','月','月份','noun','time'),
('moon','月亮','月亮','noun','nature'),
('morning','早晨','早晨；上午','noun','time'),
('mother (mom, mommy)','母親','母親；媽媽','noun','family'),
('motorcycle','機車','摩托車；機車','noun','transport'),
('mountain','山','山；山岳','noun','geography'),
('museum','博物館','博物館','noun','culture'),
('music','音樂','音樂','noun','music'),
('name','名稱','名稱；名字','noun','general'),
('nature','自然','自然；大自然','noun','environment'),
('neighbor','鄰居','鄰居','noun','people'),
('news','新聞','新聞','noun','media'),
('newspaper','報紙','報紙','noun','media'),
('night','夜晚','夜晚；晚上','noun','time'),
('noodle','麵條','麵；麵條','noun','food'),
('north','北方','北方；北部','noun','direction'),
('nose','鼻子','鼻子','noun','body'),
('November','十一月','十一月','noun','time'),
('nurse','護理師','護理師；護士','noun','occupation'),
('October','十月','十月','noun','time'),
('office','辦公室','辦公室','noun','work'),
('oil','油','油','noun','general'),
('orange','柳橙','柳橙；橘子（水果義）','noun','food'),
('page','頁','書頁；頁面','noun','general'),
('pants','長褲','長褲','noun','object'),
('paper','紙','紙；紙張','noun','object'),
('parent','父母','父親或母親；家長','noun','family'),
('park','公園','公園','noun','place'),
('peach','桃子','桃子','noun','food'),
('pear','梨','梨子','noun','food'),
('pencil','鉛筆','鉛筆','noun','education'),
('people','人們','人們','noun','people'),
('person','人','人；個人','noun','people'),
('piano','鋼琴','鋼琴','noun','music'),
('picture','圖片','圖片；圖畫','noun','media'),
('pizza','披薩','披薩','noun','food'),
('planet','行星','行星','noun','science'),
('police','警察','警察；警方','noun','public_service'),
('post office','郵局','郵局','noun','public_service'),
('potato','馬鈴薯','馬鈴薯','noun','food'),
('problem','問題','問題','noun','general'),
('program','程式','程式；節目（依 Concept 應再分義，本批限電腦程式義）','noun','technology'),
('public','公共的','公共的；公眾的','adjective','society'),
('pumpkin','南瓜','南瓜','noun','food'),
('rabbit','兔子','兔子','noun','animal'),
('radio','收音機','收音機；廣播設備','noun','media'),
('rain','雨','雨','noun','weather'),
('rainbow','彩虹','彩虹','noun','nature'),
('reporter','記者','記者','noun','occupation'),
('restaurant','餐廳','餐廳','noun','food'),
('rice','米飯','米；米飯（依語境）','noun','food'),
('river','河流','河流','noun','geography'),
('robot','機器人','機器人','noun','technology'),
('Saturday','星期六','星期六','noun','time'),
('school','學校','學校','noun','education'),
('science','科學','科學','noun','science'),
('sea','海洋','海；海洋','noun','geography'),
('season','季節','季節','noun','time'),
('September','九月','九月','noun','time'),
('ship','船舶','船；船舶','noun','transport'),
('sister','姊妹','姊妹；姊姊或妹妹','noun','family'),
('snake','蛇','蛇','noun','animal'),
('snow','雪','雪','noun','weather'),
('soccer','足球','足球運動','noun','sports'),
('son','兒子','兒子','noun','family'),
('song','歌曲','歌曲','noun','music'),
('south','南方','南方；南部','noun','direction'),
('spider','蜘蛛','蜘蛛','noun','animal'),
('sports','運動','體育運動','noun','sports'),
('spring','春季','春天；春季（季節義）','noun','time'),
('station','車站','車站（交通設施義）','noun','transport'),
('strawberry','草莓','草莓','noun','food'),
('street','街道','街道','noun','infrastructure'),
('student','學生','學生','noun','education'),
('summer','夏季','夏天；夏季','noun','time'),
('sun','太陽','太陽','noun','nature'),
('Sunday','星期日','星期日；星期天','noun','time'),
('supermarket','超級市場','超級市場；超市','noun','place'),
('table','桌子','桌子','noun','object'),
('Taiwan','臺灣','臺灣','proper_noun','geography'),
('taxi','計程車','計程車','noun','transport'),
('tea','茶','茶','noun','food'),
('teacher','教師','教師；老師','noun','education'),
('telephone (phone)','電話','電話','noun','technology'),
('temple','寺廟','寺廟；廟宇','noun','culture'),
('tennis','網球','網球運動','noun','sports'),
('theater','劇院','劇院；戲院','noun','culture'),
('ticket','票','票；票券','noun','general'),
('tiger','老虎','老虎','noun','animal'),
('today','今天','今天','noun','time'),
('tomato','番茄','番茄；西紅柿','noun','food'),
('tomorrow','明天','明天','noun','time'),
('town','城鎮','城鎮','noun','geography'),
('toy','玩具','玩具','noun','object'),
('traffic','交通','道路交通','noun','transport'),
('train','火車','火車','noun','transport'),
('tree','樹','樹木','noun','nature'),
('trip','旅行','旅行；旅程','noun','travel'),
('truck','卡車','卡車；貨車','noun','transport'),
('Tuesday','星期二','星期二','noun','time'),
('turtle','烏龜','烏龜；龜','noun','animal'),
('typhoon','颱風','颱風','noun','weather'),
('umbrella','雨傘','雨傘','noun','object'),
('uncle','叔伯舅姑姨丈','叔叔、伯伯、舅舅等男性長輩親屬','noun','family'),
('vacation','假期','假期；休假','noun','time'),
('vegetable','蔬菜','蔬菜','noun','food'),
('video','影片','影片；視訊（本批限影片義）','noun','media'),
('violin','小提琴','小提琴','noun','music'),
('visitor','訪客','訪客；參訪者','noun','people'),
('wall','牆','牆壁','noun','object'),
('wallet','錢包','錢包','noun','object'),
('water','水','水','noun','nature'),
('watermelon','西瓜','西瓜','noun','food'),
('weather','天氣','天氣','noun','weather'),
('Wednesday','星期三','星期三','noun','time'),
('week','星期','一星期；一週','noun','time'),
('weekend','週末','週末','noun','time'),
('west','西方','西方；西部','noun','direction'),
('wife','妻子','妻子','noun','family'),
('window','窗戶','窗戶','noun','object'),
('winter','冬季','冬天；冬季','noun','time'),
('woman','女性','女人；女性','noun','people'),
('world','世界','世界','noun','general'),
('year','年','一年；年份','noun','time'),
('zebra','斑馬','斑馬','noun','animal'),
('zoo','動物園','動物園','noun','place')
    ) as x(en,zh,meaning,pos,domain)
  loop
    select e."VocabularySourceEntryID" into v_entry_id
    from public."TblP132VocabularySourceEntry" e
    where e."LexiconSourceID"=v_source_id
      and e."LanguageCode"='en'
      and e."SourceSurfaceForm"=r.en
      and e."IsBasic1200"=true;

    if v_entry_id is null then
      raise exception 'P132 09: official Basic1200 source entry not found: %', r.en;
    end if;

    -- Prefer an already approved mapping with this exact intended Chinese concept.
    select c."ConceptID" into v_concept_id
    from public."TblP132VocabularySourceMapping" m
    join public."TblP132VocabularyConcept" c on c."ConceptID"=m."ConceptID"
    where m."VocabularySourceEntryID"=v_entry_id
      and c."CanonicalZh"=r.zh and c."MeaningZh"=r.meaning
      and m."ReviewStatus"='approved'
    order by c."ConceptID" limit 1;

    if v_concept_id is null then
      -- Reuse an existing P132 concept only on exact Chinese meaning + exact EN form.
      select c."ConceptID" into v_concept_id
      from public."TblP132VocabularyConcept" c
      join public."TblP132VocabularyForm" f on f."ConceptID"=c."ConceptID"
      where c."CanonicalZh"=r.zh and c."MeaningZh"=r.meaning
        and f."LanguageCode"='en'
        and lower(btrim(coalesce(f."Lemma",f."SurfaceForm")))=lower(
          case
            when position(' (' in r.en)>0 then left(r.en,position(' (' in r.en)-1)
            else r.en
          end)
      order by c."ConceptID" limit 1;
    end if;

    if v_concept_id is null then
      insert into public."TblP132VocabularyConcept"
        ("CanonicalZh","MeaningZh","PartOfSpeech","Domain","ReviewStatus","IsActive")
      values(r.zh,r.meaning,r.pos,r.domain,'approved',true)
      returning "ConceptID" into v_concept_id;
    end if;

    -- Preferred English surface: official headword before parenthetical variants.
    insert into public."TblP132VocabularyForm"
      ("ConceptID","LanguageCode","SurfaceForm","Lemma","PartOfSpeech","IsPreferred","IsActive")
    select v_concept_id,'en',
      case when position(' (' in r.en)>0 then left(r.en,position(' (' in r.en)-1) else r.en end,
      case when position(' (' in r.en)>0 then left(r.en,position(' (' in r.en)-1) else r.en end,
      r.pos,true,true
    where not exists (
      select 1 from public."TblP132VocabularyForm" f
      where f."ConceptID"=v_concept_id and f."LanguageCode"='en'
        and lower(f."SurfaceForm")=lower(case when position(' (' in r.en)>0 then left(r.en,position(' (' in r.en)-1) else r.en end)
    );

    insert into public."TblP132VocabularySourceMapping"
      ("VocabularySourceEntryID","ConceptID","MappingType","MappingConfidence","ReviewStatus","IsPrimary","ReviewNote","ReviewedAt")
    values(v_entry_id,v_concept_id,'sense',1.0000,'approved',true,
      'Curated P132 V0.2 Basic A batch.',now())
    on conflict ("VocabularySourceEntryID","ConceptID") do update
      set "ReviewStatus"='approved',"MappingConfidence"=1.0000,
          "IsPrimary"=true,"ReviewNote"='Curated P132 V0.2 Basic A batch.',
          "ReviewedAt"=now();

    update public."TblP132VocabularySourceEntry"
      set "ImportStatus"='mapped',"ReviewedAt"=coalesce("ReviewedAt",now())
      where "VocabularySourceEntryID"=v_entry_id;

    insert into public."TblP132ConceptInfiltrationPolicy"
      ("ConceptID","TargetLanguage","SuitabilityGrade","Phase1Eligible","SuitabilityReason","ReviewedAt","UpdatedAt")
    values(v_concept_id,'en','A',true,
      'A: high semantic clarity and generally suitable for direct lexical insertion into Chinese Phase-1 reading.',
      now(),now())
    on conflict ("ConceptID","TargetLanguage") do update
      set "SuitabilityGrade"='A',"Phase1Eligible"=true,
          "SuitabilityReason"=excluded."SuitabilityReason",
          "ReviewedAt"=now(),"UpdatedAt"=now();
  end loop;
end $$;

-- Audit: curated A concepts from official Basic1200.
select count(distinct m."ConceptID") as "BasicAConcepts"
from public."TblP132VocabularySourceMapping" m
join public."TblP132VocabularySourceEntry" e
  on e."VocabularySourceEntryID"=m."VocabularySourceEntryID"
join public."TblP132LexiconSource" s on s."LexiconSourceID"=e."LexiconSourceID"
join public."TblP132ConceptInfiltrationPolicy" p
  on p."ConceptID"=m."ConceptID" and p."TargetLanguage"='en'
where s."SourceCode"='NAER_12YBE_EN_2000'
  and e."IsBasic1200"=true
  and m."ReviewStatus"='approved'
  and p."SuitabilityGrade"='A'
  and p."Phase1Eligible"=true;

-- Inspect the actual batch.
select e."SourceSurfaceForm",c."CanonicalZh",c."MeaningZh",c."PartOfSpeech",c."Domain"
from public."TblP132VocabularySourceMapping" m
join public."TblP132VocabularySourceEntry" e on e."VocabularySourceEntryID"=m."VocabularySourceEntryID"
join public."TblP132LexiconSource" s on s."LexiconSourceID"=e."LexiconSourceID"
join public."TblP132VocabularyConcept" c on c."ConceptID"=m."ConceptID"
join public."TblP132ConceptInfiltrationPolicy" p on p."ConceptID"=c."ConceptID" and p."TargetLanguage"='en'
where s."SourceCode"='NAER_12YBE_EN_2000' and e."IsBasic1200"=true
  and p."SuitabilityGrade"='A' and p."Phase1Eligible"=true
order by e."SourceOrder",c."ConceptID";
