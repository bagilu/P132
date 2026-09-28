(() => {
 const C=window.P132_CONFIG;if(!C){document.body.innerHTML='<main><h2>尚未建立 config.js</h2><p>請由 config-sample.js 複製建立 config.js。</p></main>';return;}
 const sb=supabase.createClient(C.SUPABASE_URL,C.SUPABASE_ANON_KEY,{auth:{storageKey:'P132-auth',persistSession:true}});
 const $=id=>document.getElementById(id); let current=null,currentSessionId=null,currentArticleLanguage='zh-TW',showOriginal=false,activePopover=null,feedItems=[],currentFeedIndex=-1,feedLang='',feedLoading=false,feedDone=false,feedCursor=null,feedObserver=null;
 ['registerLink','forgotLink'].forEach(id=>$(id).href=C.P130_URL||'#');
 async function boot(){const {data:{session}}=await sb.auth.getSession();show(session);if(session)await init();}
 function show(s){$('auth').hidden=!!s;$('app').hidden=!s;}
 $('login').onclick=async()=>{const {error}=await sb.auth.signInWithPassword({email:$('email').value,password:$('password').value});$('authMsg').textContent=error?error.message:'';if(!error){show(true);await init();}};
 $('logout').onclick=async()=>{await sb.auth.signOut();location.reload();};
 $('lang').onchange=async()=>{await sb.rpc('P132_SetTargetLanguage',{p_language:$('lang').value});await loadFeed();};
 async function init(){const {data:p,error}=await sb.rpc('P132_EnsureLearnerProfile');if(error)return alert(error.message);if(p?.target_language)$('lang').value=p.target_language;await loadFeed();}
 function appendFeedItem(a){const i=feedItems.length;feedItems.push(a);const d=document.createElement('div');d.className='feed-item';d.innerHTML=`<div class="feed-meta">${esc(a.source_name||'')} · ${esc(a.language_code||'')}</div><h3>${esc(a.title)}</h3><p>${esc(a.summary||'')}</p><button>開始閱讀</button>`;d.querySelector('button').onclick=()=>openArticle(a.article_id,i);$('feed').appendChild(d);}
 async function loadFeed(reset=true){
   if(feedLoading||(feedDone&&!reset))return;
   if(reset){feedItems=[];feedCursor=null;feedDone=false;$('feed').innerHTML='';$('feedLoading').textContent='';}
   feedLoading=true;$('feedLoading').textContent=reset?'正在載入新聞……':'正在載入較早的新聞……';$('loadMore').hidden=true;
   const args={p_limit:20,p_language_filter:feedLang||null,p_before_sort_at:feedCursor?.sort_at||null,p_before_article_id:feedCursor?.article_id||null};
   const {data,error}=await sb.rpc('P132_GetReadingFeedPage',args);
   feedLoading=false;
   if(error){$('feedLoading').textContent=error.message;$('loadMore').hidden=false;return;}
   const rows=data||[];rows.forEach(appendFeedItem);
   if(rows.length){const last=rows[rows.length-1];feedCursor={sort_at:last.sort_at,article_id:last.article_id};}
   feedDone=rows.length<20;
   $('feedLoading').textContent=feedDone?(feedItems.length?'已經沒有更早的新聞了。':'目前沒有這個語言的新聞。'):'';
   $('loadMore').hidden=feedDone;
 }
 document.querySelectorAll('.feed-filter').forEach(b=>b.onclick=async()=>{document.querySelectorAll('.feed-filter').forEach(x=>x.classList.remove('active'));b.classList.add('active');feedLang=b.dataset.feedLang||'';$('reader').hidden=true;$('feed').parentElement.hidden=false;await loadFeed(true);});
 $('loadMore').onclick=()=>loadFeed(false);
 feedObserver=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)&&!feedDone&&!feedLoading&&feedItems.length)loadFeed(false);},{rootMargin:'500px 0px'});
 feedObserver.observe($('feedSentinel'));
 async function openArticle(id,index=null){
   if(index!==null)currentFeedIndex=index;
   const item=feedItems[currentFeedIndex]||{};
   currentArticleLanguage=item.language_code||'zh-TW';
   const {data:sid,error:sessionError}=await sb.rpc('P132_StartReadingSession',{p_article_id:id});if(sessionError)return alert(sessionError.message);
   currentSessionId=sid;
   const {data,error}=await sb.rpc('P132_PrepareArticle',{p_article_id:id,p_reading_session_id:sid});if(error)return alert(error.message);
   current=data;showOriginal=false;
   $('prevArticle').disabled=currentFeedIndex<=0;$('nextArticle').disabled=currentFeedIndex<0||currentFeedIndex>=feedItems.length-1;
   $('readerStatus').textContent=currentFeedIndex===feedItems.length-1?'已經是最後一則新聞。':'';
   $('title').textContent=data.title;$('sourceLink').href=data.original_url;$('feed').parentElement.hidden=true;$('reader').hidden=false;
   if(currentArticleLanguage==='en'||currentArticleLanguage==='ja'){
     $('toggleOriginal').hidden=true;
     const {data:foreign,error:foreignError}=await sb.rpc('P132_GetForeignArticleTerms',{p_article_id:id,p_reading_session_id:sid});
     if(foreignError){$('article').textContent='外語詞彙標註讀取失敗：'+foreignError.message;return;}
     renderForeignArticle(data,foreign);
   }else{
     $('toggleOriginal').hidden=false;$('toggleOriginal').textContent='顯示原文';renderSegments(data.segments||[]);
   }
 }
 function closePopover(){if(activePopover){activePopover.remove();activePopover=null;}}
 function openPopover(anchor,s){closePopover();const pop=document.createElement('div');pop.className='translation-popover';pop.innerHTML='<div class="popover-head">中文意思</div><div class="popover-meaning">讀取中…</div>';document.body.appendChild(pop);const r=anchor.getBoundingClientRect();const pr=pop.getBoundingClientRect();let left=Math.min(window.innerWidth-pr.width-8,Math.max(8,r.left));let top=r.bottom+6;if(top+pr.height>window.innerHeight-8)top=Math.max(8,r.top-pr.height-6);pop.style.left=left+'px';pop.style.top=top+'px';activePopover=pop;sb.rpc('P132_RequestTranslation',{p_exposure_id:s.exposure_id}).then(({data,error})=>{if(!pop.isConnected)return;pop.querySelector('.popover-meaning').textContent=error?error.message:(data?.meaning_zh||'—');});}
 function articleSourceText(data){return (data?.segments||[]).map(s=>s.text||'').join('');}
 function foreignPopover(anchor,term,response){
   closePopover();const pop=document.createElement('div');pop.className='translation-popover foreign-popover';
   const meaning=response?.meaning_zh||term.meaning_zh||'';
   pop.innerHTML='<div class="popover-head">中文意思</div><div class="popover-meaning"></div>';
   pop.querySelector('.popover-meaning').textContent=meaning||'目前尚無中文詞義。';
   if(!meaning){
     const form=document.createElement('div');form.className='meaning-entry';
     const input=document.createElement('input');input.type='text';input.placeholder='輸入你理解的中文意思';
     const save=document.createElement('button');save.type='button';save.textContent='儲存個人詞義';
     save.onclick=async()=>{const v=input.value.trim();if(!v)return;save.disabled=true;const {data,error}=await sb.rpc('P132_SubmitPersonalTermMeaning',{p_occurrence_id:term.foreign_term_occurrence_id,p_meaning_zh:v});save.disabled=false;if(error)return alert(error.message);term.meaning_zh=data?.meaning_zh||v;pop.querySelector('.popover-meaning').textContent=term.meaning_zh;form.remove();};
     form.append(input,save);pop.append(form);
   }
   document.body.appendChild(pop);const r=anchor.getBoundingClientRect();const pr=pop.getBoundingClientRect();pop.style.left=Math.min(window.innerWidth-pr.width-8,Math.max(8,r.left))+'px';let top=r.bottom+6;if(top+pr.height>window.innerHeight-8)top=Math.max(8,r.top-pr.height-6);pop.style.top=top+'px';activePopover=pop;
 }
 function makeForeignTerm(term){
   const wrap=document.createElement('span');wrap.className='vocab-wrap foreign-term'+(term.term_kind==='function_word'?' function-word':'');
   const w=document.createElement('span');w.className='word';w.textContent=term.surface_text;
   const actions=document.createElement('span');actions.className='micro-actions';
   const tr=document.createElement('button');tr.className='micro-icon translate';tr.type='button';tr.title='翻譯';tr.setAttribute('aria-label','翻譯');tr.textContent='●';
   tr.onclick=async e=>{e.stopPropagation();const {data,error}=await sb.rpc('P132_ForeignTermAction',{p_exposure_id:term.exposure_id,p_action:'translation_request'});if(error)return alert(error.message);if(!actions.contains(ok))actions.append(ok);foreignPopover(tr,term,data);};
   const ok=document.createElement('button');ok.className='micro-icon understand';ok.type='button';ok.title='我懂';ok.setAttribute('aria-label','我懂');ok.textContent='●';
   ok.onclick=async e=>{e.stopPropagation();const {error}=await sb.rpc('P132_ForeignTermAction',{p_exposure_id:term.exposure_id,p_action:'understand'});if(error)return alert(error.message);ok.remove();};
   actions.append(tr);if(term.show_understand!==false)actions.append(ok);wrap.append(w,actions);return wrap;
 }
 function renderForeignArticle(data,foreign){
   closePopover();const box=$('article');box.innerHTML='';const source=articleSourceText(data);const terms=(foreign?.terms||[]).slice().sort((a,b)=>a.start_offset-b.start_offset);let cursor=0;
   terms.forEach(t=>{const start=Math.max(0,Number(t.start_offset)||0),end=Math.max(start,Number(t.end_offset)||start);if(start<cursor||start>source.length)return;if(start>cursor)box.append(document.createTextNode(source.slice(cursor,start)));box.append(makeForeignTerm(t));cursor=Math.min(source.length,end);});
   if(cursor<source.length)box.append(document.createTextNode(source.slice(cursor)));
   if(!terms.length){box.textContent=source;$('readerStatus').textContent='這篇外語新聞尚未建立可互動的詞彙標註。';}
 }
 function renderSegments(segs){closePopover();const box=$('article');box.innerHTML='';segs.forEach(s=>{if(!s.exposure_id){box.append(document.createTextNode(s.text));return;}if(showOriginal){box.append(document.createTextNode(s.text));return;}const wrap=document.createElement('span');wrap.className='vocab-wrap';const w=document.createElement('span');w.className='word';w.textContent=s.display_text;const actions=document.createElement('span');actions.className='micro-actions';const tr=document.createElement('button');tr.className='micro-icon translate';tr.type='button';tr.title='翻譯';tr.setAttribute('aria-label','翻譯');tr.textContent='●';tr.onclick=e=>{e.stopPropagation();openPopover(tr,s);};const ok=document.createElement('button');ok.className='micro-icon understand';ok.type='button';ok.title='我懂';ok.setAttribute('aria-label','我懂');ok.textContent='●';ok.onclick=async e=>{e.stopPropagation();const {error}=await sb.rpc('P132_ReportUnderstand',{p_exposure_id:s.exposure_id});if(error)return alert(error.message);ok.remove();};actions.append(tr);if(s.show_understand!==false)actions.append(ok);wrap.append(w,actions);box.append(wrap);});}
 $('toggleOriginal').onclick=()=>{if(!current||currentArticleLanguage==='en'||currentArticleLanguage==='ja')return;showOriginal=!showOriginal;$('toggleOriginal').textContent=showOriginal?'顯示漸浸版':'顯示原文';renderSegments(current.segments||[]);};
 $('backToFeed').onclick=()=>{closePopover();$('feed').parentElement.hidden=false;$('reader').hidden=true;};
 $('prevArticle').onclick=()=>{if(currentFeedIndex>0)openArticle(feedItems[currentFeedIndex-1].article_id,currentFeedIndex-1);};
 $('nextArticle').onclick=()=>{if(currentFeedIndex>=0&&currentFeedIndex<feedItems.length-1)openArticle(feedItems[currentFeedIndex+1].article_id,currentFeedIndex+1);};
 document.addEventListener('pointerdown',e=>{if(activePopover&&!activePopover.contains(e.target)&&!e.target.closest('.translate'))closePopover();});
 document.addEventListener('keydown',e=>{if(e.key==='Escape')closePopover();});
 window.addEventListener('scroll',closePopover,{passive:true});window.addEventListener('resize',closePopover);
 function esc(x){return String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));} boot();
})();