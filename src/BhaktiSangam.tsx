import {useEffect,useRef,useState} from 'react';
import {supabase} from './lib/supabase';
import RamayanaTunes from './RamayanaTunes';
import './bhakti-mobile.css';

type Song={id:number;title:string;lyrics_hindi:string;lyrics_latin:string};
type Item={id:number;position:number;song_id:number;bhakti_songs:Song};
type Program={id:number;title:string;created_by:string|null;created_at:string};
export function useBhaktiAccess(userId:string){
 const [allowed,setAllowed]=useState(false);
 useEffect(()=>{let live=true;supabase.from('bhakti_members').select('user_id').eq('user_id',userId).maybeSingle().then(({data})=>{if(live)setAllowed(!!data)});return()=>{live=false}},[userId]);
 return allowed;
}
export function BhaktiAccessAdmin(){
 const[email,setEmail]=useState('');const[msg,setMsg]=useState('');const[busy,setBusy]=useState(false);
 const[members,setMembers]=useState<any[]>([]);
 async function refresh(){const{data}=await supabase.from('bhakti_members').select('user_id,created_at');setMembers(data||[])}
 useEffect(()=>{refresh()},[]);
 async function change(grant:boolean,target=email){if(!target.trim())return;setBusy(true);const{data,error}=await supabase.rpc('bhakti_grant_by_email',{p_email:target.trim(),p_grant:grant});setMsg(error?.message||data||'Saved');setBusy(false);if(!error){setEmail('');refresh()}}
 return <section className="card"><h2>🔐 Bhakti Sangam — Manage Access</h2><p>Only registered users whose email is approved can see Bhakti Sangam. Admins always have access.</p><label>Registered user email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="member@example.com"/></label><div style={{display:'flex',gap:8,flexWrap:'wrap'}}><button disabled={busy||!email.trim()} onClick={()=>change(true)}>Grant access</button><button className="outline" disabled={busy||!email.trim()} onClick={()=>change(false)}>Revoke access</button></div>{msg&&<p role="status">{msg}</p>}<p className="muted">{members.length} authorized member(s). To revoke access, enter the registered email above.</p></section>
}
export default function BhaktiSangam(){
 const[mode,setMode]=useState<'view'|'play'|'add'|'library'|'edit'|'remove'>('view');
 const[section,setSection]=useState<'program'|'ramayana'>('program');
 const[manageProgramsOpen,setManageProgramsOpen]=useState(false);
 const[items,setItems]=useState<Item[]>([]);const[songs,setSongs]=useState<Song[]>([]);const[programs,setPrograms]=useState<Program[]>([]);const[programId,setProgramId]=useState<number|null>(null);const[programTitle,setProgramTitle]=useState('');const[newProgramTitle,setNewProgramTitle]=useState('');const[programBusy,setProgramBusy]=useState(false);
 const[expanded,setExpanded]=useState<number[]>([]);
 const[testItemId,setTestItemId]=useState('');
 const[script,setScript]=useState<'hindi'|'latin'>('latin');
 const[speed,setSpeed]=useState(2);const[playing,setPlaying]=useState(false);const[playItemIndex,setPlayItemIndex]=useState(0);const[itemFinished,setItemFinished]=useState(false);
 const[title,setTitle]=useState('');const[hindi,setHindi]=useState('');const[latin,setLatin]=useState('');
 const[chosen,setChosen]=useState('');const[librarySearch,setLibrarySearch]=useState('');const[msg,setMsg]=useState('');const[editingId,setEditingId]=useState('');const[saving,setSaving]=useState(false);
 const[sundarkandFrom,setSundarkandFrom]=useState(1);const[sundarkandTo,setSundarkandTo]=useState(10);const[sundarkandOnly,setSundarkandOnly]=useState(false);
 // Recorded sea-shell horn by Anton Platonov, CC BY 2.5.
 // https://commons.wikimedia.org/wiki/File:Dunkar_Sea_shell_horn_sound.ogg
 const shankAudio=useRef<HTMLAudioElement|null>(null);
 const[shankPlaying,setShankPlaying]=useState(false);
 function stopShank(){
   const audio=shankAudio.current;
   shankAudio.current=null;
   if(audio){audio.pause();audio.onended=null;audio.onerror=null;audio.removeAttribute('src');audio.load()}
   setShankPlaying(false);
 }
 function playShank(){
   stopShank();
   const source='https://commons.wikimedia.org/wiki/Special:Redirect/file/Dunkar_Sea_shell_horn_sound.ogg';
   // Each blow uses a fresh media element, rather than seeking an already
   // finished element back to zero. This avoids stale decoder state on
   // the third replay on some mobile browsers.
   const startBlow=(number:number)=>{
     const audio=new Audio(source);
     audio.preload='auto';
     audio.volume=0.85;
     shankAudio.current=audio;
     audio.onended=()=>{
       if(shankAudio.current!==audio)return;
       audio.onended=null;
       audio.onerror=null;
       if(number===3){stopShank();return}
       startBlow(number+1);
     };
     audio.onerror=()=>{if(shankAudio.current===audio){stopShank();setMsg('The recorded Shankh sound could not load. Check your connection and try playing the Aarti again.')}};
     void audio.play().then(()=>setShankPlaying(true)).catch(()=>{if(shankAudio.current===audio){stopShank();setMsg('Audio playback was blocked. Tap Play Program to allow sound.')}});
   };
   startBlow(1);
 }
 useEffect(()=>()=>{const audio=shankAudio.current;if(audio){audio.pause();audio.onended=null;shankAudio.current=null}},[]);
 // Public-domain struck-gong sample by Stephan, via Wikimedia Commons.
 // This is a recorded gong approximation, not a verified traditional ghariyal.
 const ghariyalAudio=useRef<HTMLAudioElement|null>(null);
 function stopGhariyal(){
   const audio=ghariyalAudio.current;
   ghariyalAudio.current=null;
   if(audio){audio.pause();audio.loop=false;audio.removeAttribute('src');audio.load()}
 }
 function playGhariyal(){
   stopGhariyal();
   const audio=new Audio('https://commons.wikimedia.org/wiki/Special:Redirect/file/Gong_or_bell_vibrant_(short).ogg');
   audio.preload='auto';
   audio.loop=true;
   audio.volume=0.28;
   ghariyalAudio.current=audio;
   void audio.play().catch(()=>{if(ghariyalAudio.current===audio){stopGhariyal();setMsg('Ghariyal audio could not start. Please retry Play Program.')}});
 }
 useEffect(()=>()=>{const audio=ghariyalAudio.current;if(audio){audio.pause();ghariyalAudio.current=null}},[]);
 const viewer=useRef<HTMLDivElement>(null);
 async function refresh(targetProgramId?:number){const[p,b]=await Promise.all([supabase.from('bhakti_programs').select('id,title,created_by,created_at').order('id'),supabase.from('bhakti_songs').select('*').order('title')]);if(p.error)setMsg(p.error.message);const loaded=(p.data||[]) as Program[];setPrograms(loaded);if(b.error)setMsg(b.error.message);else setSongs((b.data||[]) as Song[]);const selectedId=targetProgramId??programId??loaded[0]?.id??null;if(selectedId!==null){setProgramId(selectedId);const{data,error}=await supabase.from('bhakti_program_items').select('id,position,song_id,program_id,bhakti_songs(id,title,lyrics_hindi,lyrics_latin)').eq('program_id',selectedId).order('position').order('id');if(error)setMsg(error.message);else setItems((data||[]) as unknown as Item[])}else setItems([])}
 useEffect(()=>{setProgramTitle(programs.find(p=>p.id===programId)?.title||'')},[programs,programId]);
 useEffect(()=>{refresh()},[]);
 useEffect(()=>{if(!playing||mode!=='play')return;let frame=0,last=0,shortStarted=0;function finishItem(){setPlaying(false);setItemFinished(true)}function tick(t:number){if(!last)last=t;const el=viewer.current;if(el){const maxScroll=el.scrollHeight-el.clientHeight;if(maxScroll<=2){if(!shortStarted)shortStarted=t;if(t-shortStarted>=6000){finishItem();return}}else{el.scrollTop=Math.min(maxScroll,el.scrollTop+(t-last)*speed*0.014);if(el.scrollTop>=maxScroll-2){el.scrollTop=maxScroll;finishItem();return}}}last=t;frame=requestAnimationFrame(tick)}frame=requestAnimationFrame(tick);return()=>cancelAnimationFrame(frame)},[playing,speed,mode,playItemIndex]);
 useEffect(()=>{if(mode==='play'&&viewer.current)viewer.current.scrollTop=0},[mode,playItemIndex]);
 async function addSong(){if(!title.trim())return;const{error}=await supabase.from('bhakti_songs').insert({title:title.trim(),lyrics_hindi:hindi,lyrics_latin:latin});if(error){setMsg(error.message);return}setMsg('Saved to Bhajan Library. Add it to a program from the Library tab.');setTitle('');setHindi('');setLatin('');await refresh();setMode('library')}
 function beginEdit(song:Song){setEditingId(String(song.id));setTitle(song.title);setHindi(song.lyrics_hindi||'');setLatin(song.lyrics_latin||'');setMsg('');setMode('edit');setPlaying(false)}
 async function saveEdit(){if(!editingId||!title.trim())return;setSaving(true);const{error}=await supabase.from('bhakti_songs').update({title:title.trim(),lyrics_hindi:hindi,lyrics_latin:latin}).eq('id',Number(editingId));setSaving(false);if(error){setMsg(error.message);return}setMsg('Lyrics updated successfully');await refresh()}
 async function deleteSong(song:Song){if(!confirm('Permanently delete "'+song.title+'" and remove it from every program? This cannot be undone.'))return;setSaving(true);const{error:linkError}=await supabase.from('bhakti_program_items').delete().eq('song_id',song.id);if(linkError){setSaving(false);setMsg(linkError.message);return}const{error}=await supabase.from('bhakti_songs').delete().eq('id',song.id);setSaving(false);setMsg(error?.message||'Lyrics permanently deleted');if(!error){setEditingId('');setTitle('');setHindi('');setLatin('');setMode('view')}await refresh()}
 async function addToProgram(songId:number){if(programId===null){setMsg('Create or select a program first.');return}const{error}=await supabase.from('bhakti_program_items').insert({program_id:programId,song_id:songId,position:items.length+1});setMsg(error?.message||'Added to program');if(!error)await refresh(programId??undefined)}
 async function addExisting(){if(!chosen)return;await addToProgram(Number(chosen))}
 async function createProgram(){const label=newProgramTitle.trim();if(!label)return;setProgramBusy(true);setMsg('');const{data:userData,error:userError}=await supabase.auth.getUser();if(userError||!userData.user){setMsg(userError?.message||'Sign in before creating a program.');setProgramBusy(false);return}const{data,error}=await supabase.from('bhakti_programs').insert({title:label,created_by:userData.user.id}).select('id').single();setProgramBusy(false);if(error){setMsg(error.message);return}setNewProgramTitle('');setMsg('Program created.');setMode('view');setPlaying(false);await refresh(Number(data.id))}
 async function renameProgram(){if(programId===null||!programTitle.trim())return;setProgramBusy(true);const{error}=await supabase.from('bhakti_programs').update({title:programTitle.trim()}).eq('id',programId);setProgramBusy(false);setMsg(error?.message||'Program label updated.');if(!error)await refresh(programId??undefined)}
 async function remove(id:number){if(!confirm('Remove this item from the program? The lyrics will remain saved.'))return;const{error}=await supabase.from('bhakti_program_items').delete().eq('id',id);setMsg(error?.message||'Removed');refresh()}
 async function move(index:number,dir:number){
  const other=items[index+dir],current=items[index];
  if(!other||!current||programBusy)return;
  setProgramBusy(true);
  setMsg('');
  // Positions can be duplicated after imports. Rewrite the complete ordering using
  // fresh, noncolliding positions before normalizing to 1..N.
  const reordered=[...items];
  [reordered[index],reordered[index+dir]]=[reordered[index+dir],reordered[index]];
  const maxPosition=Math.max(0,...items.map(item=>Number(item.position)||0));
  const temporaryStart=maxPosition+items.length+1;
  for(let i=0;i<reordered.length;i++){
    const {error}=await supabase.from('bhakti_program_items').update({position:temporaryStart+i}).eq('id',reordered[i].id);
    if(error){setMsg('Could not reorder songs: '+error.message);setProgramBusy(false);await refresh(programId??undefined);return}
  }
  for(let i=0;i<reordered.length;i++){
    const {error}=await supabase.from('bhakti_program_items').update({position:i+1}).eq('id',reordered[i].id);
    if(error){setMsg('Could not finalize song order: '+error.message);setProgramBusy(false);await refresh(programId??undefined);return}
  }
  setItems(reordered.map((item,i)=>({...item,position:i+1})));
  setMsg('Order updated');
  setProgramBusy(false);
  await refresh(programId??undefined);
}
 function lines(s:Song){const full=(script==='hindi'?s.lyrics_hindi:s.lyrics_latin)||'';if(!full)return 'Lyrics not added yet.';if(!/sundarkand/i.test(s.title))return full;const sections=full.split(/(?=^\[DOHA\s+\d+\])/gmi);if(sections.length<2)return full;const head=sections[0];const chunks=sections.slice(1).filter(chunk=>{const n=Number(chunk.match(/^\[DOHA\s+(\d+)\]/i)?.[1]);return n>=sundarkandFrom&&n<=sundarkandTo});return (sundarkandFrom===1?head:'')+chunks.join('');}
 const playItems=items.filter(it=>!sundarkandOnly||/sundarkand/i.test(it.bhakti_songs?.title||''));
 function testSelectedItem(){
  const index=playItems.findIndex(it=>String(it.id)===testItemId);
  if(index<0){setMsg('Please select an item to test.');return}
  setPlayItemIndex(index);setItemFinished(false);setPlaying(false);setMode('play');
  setMsg('Test mode: selected item ready. Press Play to check scrolling.');
  if(viewer.current)viewer.current.scrollTop=0;
 }
 const testItemPicker=<div style={{display:'flex',gap:8,alignItems:'center',flexWrap:'wrap',margin:'12px 0'}}><label htmlFor="bhakti-test-item">Test an item</label><select id="bhakti-test-item" value={testItemId} onChange={e=>setTestItemId(e.target.value)}><option value="">Choose a bhajan or Aarti</option>{playItems.map((it,i)=><option key={it.id} value={it.id}>{i+1}. {it.bhakti_songs?.title}</option>)}</select><button className="outline" disabled={!testItemId} onClick={testSelectedItem}>▶ Test selected item</button></div>;
 useEffect(()=>{
   const isAarti=/om jai jagdish/i.test(playItems[playItemIndex]?.bhakti_songs?.title||'');
   if(mode==='play'&&playing&&isAarti){
     // The sound begins with the Aarti; no separate Shankh control is required.
     playShank();
     // Ghariyal recording disabled: listeners reported a watery sound.
     // Restore only after confirming a clean, authentic struck-metal recording.
   }else{
     stopShank();
     stopGhariyal();
   }
   return ()=>{stopShank();stopGhariyal()};
 // Audio is triggered on playback start or item change, not on each render.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[mode,playing,playItemIndex,programId]);
 function playProgram(){if(playing)return;if(itemFinished){setPlayItemIndex(index=>index+1<playItems.length?index+1:0);setItemFinished(false)}setPlaying(true)}
 const sundarkandControls=<div className="bhakti-sundarkand-controls" style={{display:'flex',alignItems:'center',gap:10,flexWrap:'wrap',margin:'12px 0'}}><strong>📖 Sundarkand reading</strong><label>From Doha <input type="number" min={1} max={60} value={sundarkandFrom} onChange={e=>setSundarkandFrom(Math.max(1,Math.min(60,Number(e.target.value)||1)))} style={{width:75}}/></label><label>Through Doha <input type="number" min={sundarkandFrom} max={60} value={sundarkandTo} onChange={e=>setSundarkandTo(Math.max(sundarkandFrom,Math.min(60,Number(e.target.value)||1)))} style={{width:75}}/></label><label style={{display:'flex',alignItems:'center',gap:5}}><input type="checkbox" checked={sundarkandOnly} onChange={e=>{setSundarkandOnly(e.target.checked);setPlaying(false);setPlayItemIndex(0);setItemFinished(false);if(viewer.current)viewer.current.scrollTop=0}}/> Sundarkand only</label><span className="muted">Includes chaupais and chhands between selected dohas</span></div>;
 return <section className="card bhakti-mobile"><h2>🪷 Bhakti Sangam</h2><div className="tabs bhakti-section-tabs" style={{flexWrap:'wrap'}}><button className={section==='program'&&mode!=='library'&&mode!=='add'&&mode!=='edit'?'active':''} onClick={()=>{setSection('program');setMode('view');setPlaying(false)}}>Program</button><button className={section==='program'&&['library','add','edit'].includes(mode)?'active':''} onClick={()=>{setSection('program');setMode('library');setPlaying(false)}}>Library</button><button className={section==='ramayana'?'active':''} onClick={()=>{setSection('ramayana');setPlaying(false)}}>Ramayana Tunes</button></div>{section==='ramayana'?<RamayanaTunes/>:<div>
<div className="bhakti-program-selector"><label style={{flex:'1 1 180px'}}>Current program<select value={programId??''} onChange={e=>{if(!e.target.value)return;const id=Number(e.target.value);setProgramId(id);setMode('view');setPlaying(false);setPlayItemIndex(0);setItemFinished(false);setExpanded([]);refresh(id)}}><option value="">Select a program</option>{programs.map(p=><option key={p.id} value={p.id}>{p.title}</option>)}</select></label></div><details className="bhakti-manage"><summary>⚙ Manage programs</summary><div className="bhakti-manage-content"><div style={{display:'flex',alignItems:'end',gap:8,flexWrap:'wrap'}}><label style={{flex:'1 1 180px'}}>Program label<input value={programTitle} maxLength={120} onChange={e=>setProgramTitle(e.target.value)} placeholder="Program name"/></label><button disabled={programBusy||programId===null||!programTitle.trim()} onClick={renameProgram}>Save label</button></div><div style={{display:'flex',alignItems:'end',gap:8,flexWrap:'wrap',marginTop:8}}><label style={{flex:'1 1 180px'}}>New program label<input value={newProgramTitle} maxLength={120} onChange={e=>setNewProgramTitle(e.target.value)} placeholder="For example: Sunday Kirtan"/></label><button disabled={programBusy||!newProgramTitle.trim()} onClick={createProgram}>＋ Create program</button></div></div></details><div className="tabs bhakti-actions">{(mode==='library'||mode==='add'||mode==='edit'?[['library','Browse Library'],['add','New Bhajan'],['edit','Edit Bhajan']]:[['view','View Program'],['play','Play Program'],['remove','Manage Items']]).map(([k,v])=><button key={k} className={mode===k?'active':''} onClick={()=>{setMode(k as typeof mode);setPlaying(false)}}>{v}</button>)}</div><details className="bhakti-manage" open={mode==='play'}><summary>Language and reading settings</summary><div className="tabs bhakti-language"><button className={script==='hindi'?'active':''} onClick={()=>setScript('hindi')}>हिन्दी</button><button className={script==='latin'?'active':''} onClick={()=>setScript('latin')}>Latin ABC</button></div></details>{msg&&<p role="status">{msg}</p>}
 {mode==='view'&&<>{items.some(it=>/sundarkand/i.test(it.bhakti_songs?.title||''))&&sundarkandControls}<h3>{programs.find(p=>p.id===programId)?.title||'Program'} ({items.length} items)</h3>{items.map((it,i)=><div key={it.id} style={{border:'1px solid #d1d5db',borderRadius:10,marginBottom:8,padding:12}}><div style={{display:'flex',alignItems:'center',gap:6}}><button className="outline" style={{flex:1,textAlign:'left'}} onClick={()=>setExpanded(a=>a.includes(it.id)?a.filter(x=>x!==it.id):[...a,it.id])}>{i+1}. {it.bhakti_songs?.title} {expanded.includes(it.id)?'▲':'▼'}</button><button className="outline" aria-label={'Move '+it.bhakti_songs?.title+' up'} title="Move up" disabled={i===0} onClick={()=>move(i,-1)}>↑</button><button className="outline" aria-label={'Move '+it.bhakti_songs?.title+' down'} title="Move down" disabled={i===items.length-1} onClick={()=>move(i,1)}>↓</button></div>{expanded.includes(it.id)&&<><p style={{whiteSpace:'pre-wrap',lineHeight:1.9}}>{lines(it.bhakti_songs)}</p><button className="outline" onClick={()=>beginEdit(it.bhakti_songs)}>✎ Edit lyrics</button></>}</div>)}{testItemPicker}<button onClick={()=>{setPlayItemIndex(0);setItemFinished(false);setMode('play');setPlaying(true)}}>▶ Play Program</button></>}
 {mode==='play'&&<>{/om jai jagdish/i.test(playItems[playItemIndex]?.bhakti_songs?.title||'')&&<p role="status">🐚 Shankh plays automatically when this Aarti begins{shankPlaying?' · sounding now':''}.</p>}<div style={{padding:12,border:'2px solid #b45309',borderRadius:12,background:'#fff7ed',color:'#111827',marginBottom:16}}><strong>🎵 Choose a song to play or test</strong>{testItemPicker}<small>Select any item, then tap Test selected item. This does not change the program order.</small></div><h3>{programs.find(p=>p.id===programId)?.title||'Program'}</h3>{items.some(it=>/sundarkand/i.test(it.bhakti_songs?.title||''))&&sundarkandControls}<div style={{display:'flex',gap:8,alignItems:'center',flexWrap:'wrap',marginBottom:12}}><button disabled={!playItems.length||playing} onClick={playProgram}>{itemFinished?(playItemIndex+1<playItems.length?'▶ Play next item':'↺ Replay Program'):'▶ Play'}</button><button className="outline" disabled={!playing} onClick={()=>setPlaying(false)}>⏸ Pause</button><button className="outline" disabled={!playItems.length} onClick={()=>{setPlaying(false);setItemFinished(false);if(viewer.current)viewer.current.scrollTop=0;setPlaying(true)}}>↺ Restart item</button><button className="outline" onClick={()=>setSpeed(s=>Math.max(1,s-1))} aria-label="Slow down">−</button><strong>Speed {speed}</strong><button className="outline" onClick={()=>setSpeed(s=>Math.min(10,s+1))} aria-label="Speed up">+</button><button className="outline" onClick={()=>viewer.current?.requestFullscreen?.()}>⛶ Full screen</button></div>{itemFinished&&<p role="status">{playItemIndex+1<playItems.length?'Item finished. Playback paused. Press Play to continue to the next item.':'Program finished. Playback paused. Press Play to start again.'}</p>}<div ref={viewer} style={{height:'65vh',overflowY:'auto',background:'#101827',color:'#fff',borderRadius:12,padding:'32px 20px',textAlign:'center',scrollBehavior:'auto'}}>{playItems.length===0?<p>No items in this program.</p>:<article key={playItems[playItemIndex]?.id} style={{marginBottom:70}}><h2 style={{color:'#fff'}}>{playItemIndex+1}. {playItems[playItemIndex]?.bhakti_songs?.title}</h2><div style={{whiteSpace:'pre-wrap',fontSize:'clamp(23px,4vw,36px)',lineHeight:2.1}}>{playItems[playItemIndex]&&lines(playItems[playItemIndex].bhakti_songs)}</div></article>}</div></>}

 {mode==='library'&&<><h3>Bhajan Library ({songs.length} saved)</h3><p className="muted">Saved bhajans stay here until you add them to a program. Use Add to Program whenever you need them.</p><label>Search the library<input type="search" value={librarySearch} onChange={e=>setLibrarySearch(e.target.value)} placeholder="Search by title"/></label>{songs.filter(song=>song.title.toLocaleLowerCase().includes(librarySearch.trim().toLocaleLowerCase())).map(song=>{const count=items.filter(it=>it.song_id===song.id).length;const text=(script==='hindi'?song.lyrics_hindi:song.lyrics_latin)||'Lyrics not added yet.';return <article key={song.id} style={{border:'1px solid #d1d5db',borderRadius:10,marginBottom:10,padding:12}}><div style={{display:'flex',alignItems:'center',justifyContent:'space-between',gap:10,flexWrap:'wrap'}}><strong>{song.title}</strong><div style={{display:'flex',alignItems:'center',gap:8,flexWrap:'wrap'}}><span className="muted">{count?('In program '+count+' time'+(count===1?'':'s')):'Library only'}</span><button onClick={()=>addToProgram(song.id)}>{count?'Add again':'Add to Program'}</button><button className="outline" onClick={()=>beginEdit(song)}>Edit lyrics</button></div></div><p style={{whiteSpace:'pre-wrap',lineHeight:1.7,marginBottom:0}}>{text.length>220?text.slice(0,220)+'…':text}</p></article>})}{songs.length===0&&<p className="muted">No bhajans in the library yet. Use Add Item to save the first one.</p>}</>}

 {mode==='add'&&<><h3>Save a new bhajan to the library</h3><label>Title<input value={title} onChange={e=>setTitle(e.target.value)}/></label><label>Hindi (Devanagari) lyrics<textarea rows={6} value={hindi} onChange={e=>setHindi(e.target.value)}/></label><label>Latin alphabet lyrics<textarea rows={6} value={latin} onChange={e=>setLatin(e.target.value)}/></label><button disabled={!title.trim()} onClick={addSong}>Save to library</button><h3>Or add a saved bhajan</h3><select value={chosen} onChange={e=>setChosen(e.target.value)}><option value="">Choose saved bhajan</option>{songs.map(s=><option key={s.id} value={s.id}>{s.title}</option>)}</select> <button disabled={!chosen} onClick={addExisting}>Add existing</button></>}
 {mode==='edit'&&<><h3>Edit or delete saved lyrics</h3><label>Choose bhajan<select value={editingId} onChange={e=>{const song=songs.find(x=>String(x.id)===e.target.value);if(song)beginEdit(song);else setEditingId('')}}><option value="">Select a bhajan</option>{songs.map(song=><option key={song.id} value={song.id}>{song.title}</option>)}</select></label>{editingId&&<><label>Title<input value={title} onChange={e=>setTitle(e.target.value)}/></label><label>Hindi (Devanagari) lyrics<textarea rows={12} value={hindi} onChange={e=>setHindi(e.target.value)}/></label><label>Latin ABC lyrics<textarea rows={12} value={latin} onChange={e=>setLatin(e.target.value)}/></label><div style={{display:'flex',gap:8,flexWrap:'wrap'}}><button disabled={saving||!title.trim()} onClick={saveEdit}>Save changes</button><button className="outline" disabled={saving} onClick={()=>{const song=songs.find(x=>String(x.id)===editingId);if(song)deleteSong(song)}}>Delete lyrics permanently</button></div><p className="muted">Changes to lyrics appear in all programs using this bhajan. Permanent deletion also removes it from programs.</p></>}</>}
 {mode==='remove'&&<><h3>Manage program items</h3>{items.map((it,i)=><div key={it.id} style={{display:'flex',alignItems:'center',gap:8,flexWrap:'wrap',marginBottom:8}}><span style={{flex:1}}>{i+1}. {it.bhakti_songs?.title}</span><button className="outline" disabled={i===0} onClick={()=>move(i,-1)}>↑</button><button className="outline" disabled={i===items.length-1} onClick={()=>move(i,1)}>↓</button><button className="outline" onClick={()=>remove(it.id)}>Remove</button></div>)}</>}
 </div>}
 </section>
}
