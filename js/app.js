(() => {
 const C=window.P132_CONFIG;if(!C){document.body.innerHTML='<main><h2>尚未建立 config.js</h2><p>請由 config-sample.js 複製建立 config.js。</p></main>';return;}
 const sb=supabase.createClient(C.SUPABASE_URL,C.SUPABASE_ANON_KEY,{auth:{storageKey:'P132-auth',persistSession:true}});
 const $=id=>document.getElementById(id); let current=null;
 ['registerLink','forgotLink'].forEach(id=>$(id).href=C.P130_URL||'#');
 async function boot(){const {data:{session}}=await sb.auth.getSession();show(session);if(session)await init();}
 function show(s){$('auth').hidden=!!s;$('app').hidden=!s;}
 $('login').onclick=async()=>{const {error}=await sb.auth.signInWithPassword({email:$('email').value,password:$('password').value});$('authMsg').textContent=error?error.message:'';if(!error){show(true);await init();}};
 $('logout').onclick=async()=>{await sb.auth.signOut();location.reload();};
 $('lang').onchange=async()=>{await sb.rpc('P132_SetTargetLanguage',{p_language:$('lang').value});await loadFeed();};
 async function init(){const {data:p,error}=await sb.rpc('P132_EnsureLearnerProfile');if(error)return alert(error.message);if(p?.target_language)$('lang').value=p.target_language;await loadFeed();}
 async function loadFeed(){ $('reader').hidden=true; const {data,error}=await sb.rpc('P132_GetReadingFeed',{p_limit:20}); if(error){$('feed').textContent=error.message;return;} $('feed').innerHTML=''; (data||[]).forEach(a=>{const d=document.createElement('div');d.className='feed-item';d.innerHTML=`<h3>${esc(a.title)}</h3><p>${esc(a.summary||'')}</p><button>開始閱讀</button>`;d.querySelector('button').onclick=()=>openArticle(a.article_id);$('feed').appendChild(d);});}
 async function openArticle(id){const {data,error}=await sb.rpc('P132_PrepareArticle',{p_article_id:id});if(error)return alert(error.message);current=data;$('title').textContent=data.title;$('sourceLink').href=data.original_url;$('feed').parentElement.hidden=true;$('reader').hidden=false;renderSegments(data.segments||[]);}
 function renderSegments(segs){const box=$('article');box.innerHTML='';segs.forEach(s=>{if(!s.exposure_id){box.append(document.createTextNode(s.text));return;}const wrap=document.createElement('span');const w=document.createElement('span');w.className='word';w.textContent=s.display_text;w.title='點擊互動';const pop=document.createElement('span');pop.className='popover';pop.hidden=true;pop.innerHTML='<button class="tr">翻譯</button><button class="ok">我懂</button><span class="meaning"></span>';w.onclick=()=>pop.hidden=!pop.hidden;pop.querySelector('.tr').onclick=async()=>{const {data,error}=await sb.rpc('P132_RequestTranslation',{p_exposure_id:s.exposure_id});if(error)return alert(error.message);pop.querySelector('.meaning').textContent=data?.meaning_zh||'';};pop.querySelector('.ok').onclick=async()=>{const {error}=await sb.rpc('P132_ReportUnderstand',{p_exposure_id:s.exposure_id});if(error)return alert(error.message);pop.querySelector('.ok').textContent='✓ 我懂';};wrap.append(w,pop);box.append(wrap);});}
 $('back').onclick=()=>{$('feed').parentElement.hidden=false;$('reader').hidden=true;};
 function esc(x){return String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));} boot();
})();
