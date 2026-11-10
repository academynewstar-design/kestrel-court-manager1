import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';

type YoutubeTune={id:number;title:string;youtube_url:string;youtube_video_id:string;uploaded_by:string;created_at:string};
type Tune={id:number;title:string;storage_path:string;uploaded_by:string;created_at:string};
const BUCKET='bhakti-ramayana-tunes';
const MAX_BYTES=50*1024*1024;
const ALLOWED_TYPES=new Set(['audio/mpeg','audio/mp4','audio/x-m4a','audio/aac','audio/wav','audio/x-wav','audio/ogg','audio/opus','audio/webm']);
const EXTENSION_TYPES:Record<string,string>={mp3:'audio/mpeg',m4a:'audio/mp4',mp4:'audio/mp4',aac:'audio/aac',wav:'audio/wav',ogg:'audio/ogg',opus:'audio/opus',webm:'audio/webm'};

export default function RamayanaTunes(){
 const [tunes,setTunes]=useState<Tune[]>([]);
 const [youtubeTunes,setYoutubeTunes]=useState<YoutubeTune[]>([]);
 const [youtubeUrl,setYoutubeUrl]=useState('');
 const [youtubeTitle,setYoutubeTitle]=useState('');
 const [youtubeActive,setYoutubeActive]=useState<number|null>(null);
 const [userId,setUserId]=useState('');
 const [title,setTitle]=useState('');
 const [file,setFile]=useState<File|null>(null);
 const [active,setActive]=useState<{id:number;url:string}|null>(null);
 const [busy,setBusy]=useState(false);
 const [loading,setLoading]=useState(true);
 const [message,setMessage]=useState('');

 async function refresh(){
  setLoading(true);
  const {data,error}=await supabase.from('bhakti_ramayana_tunes').select('id,title,storage_path,uploaded_by,created_at').order('created_at',{ascending:false});
  if(error)setMessage(error.message);else setTunes((data||[]) as Tune[]);
  const {data:links,error:linksError}=await supabase.from('bhakti_youtube_tunes').select('id,title,youtube_url,youtube_video_id,uploaded_by,created_at').order('created_at',{ascending:false});
  if(linksError)setMessage(linksError.message);else setYoutubeTunes((links||[]) as YoutubeTune[]);
  setLoading(false);
 }
 useEffect(()=>{
  let live=true;
  supabase.auth.getUser().then(({data})=>{if(live)setUserId(data.user?.id||'')});
  refresh();
  return()=>{live=false};
 },[]);

 function youtubeId(value:string){
  try{
   const url=new URL(value.trim());
   const host=url.hostname.toLowerCase().replace(/^www\./,'').replace(/^m\./,'');
   let id='';
   if(host==='youtu.be')id=url.pathname.split('/')[1]||'';
   else if(host==='youtube.com'||host==='youtube-nocookie.com'){
    const parts=url.pathname.split('/').filter(Boolean);
    id=parts[0]==='watch'?url.searchParams.get('v')||'':['shorts','live','embed'].includes(parts[0])?parts[1]||'':'';
   }
   return /^[A-Za-z0-9_-]{11}$/.test(id)?id:null;
  }catch{return null}
 }
 async function addYoutube(){
  const id=youtubeId(youtubeUrl);
  if(!id||!youtubeTitle.trim()||!userId){setMessage('Enter a title and a valid YouTube video link.');return}
  setBusy(true);setMessage('');
  const {error}=await supabase.from('bhakti_youtube_tunes').insert({title:youtubeTitle.trim(),youtube_url:'https://www.youtube.com/watch?v='+id,youtube_video_id:id,uploaded_by:userId});
  if(error)setMessage(error.message);
  else{setYoutubeTitle('');setYoutubeUrl('');setMessage('YouTube tune added.');await refresh()}
  setBusy(false);
 }
 async function removeYoutube(tune:YoutubeTune){
  if(!confirm('Remove “'+tune.title+'” from Tunes?'))return;
  setBusy(true);
  const {error}=await supabase.from('bhakti_youtube_tunes').delete().eq('id',tune.id);
  if(error)setMessage(error.message);
  else{setYoutubeActive(null);setMessage('YouTube link removed.');await refresh()}
  setBusy(false);
 }
 async function upload(){
  if(!title.trim()||!file||!userId)return;
  if(file.size>MAX_BYTES){setMessage('Please choose an audio file smaller than 50 MB.');return}
  const ext=file.name.split('.').pop()?.toLowerCase()||'';
  const type=file.type||EXTENSION_TYPES[ext]||'';
  if(!ALLOWED_TYPES.has(type)){setMessage('Choose an MP3, M4A, AAC, WAV, OGG, OPUS, or WebM audio file.');return}
  setBusy(true);setMessage('');
  const path=userId+'/'+crypto.randomUUID()+'.'+ext;
  const {error:uploadError}=await supabase.storage.from(BUCKET).upload(path,file,{contentType:type,upsert:false});
  if(uploadError){setMessage(uploadError.message);setBusy(false);return}
  const {error}=await supabase.from('bhakti_ramayana_tunes').insert({title:title.trim(),storage_path:path,uploaded_by:userId});
  if(error){
   await supabase.storage.from(BUCKET).remove([path]);
   setMessage(error.message);
  }else{
   setTitle('');setFile(null);
   const input=document.getElementById('ramayana-tune-file') as HTMLInputElement|null;
   if(input)input.value='';
   setMessage('Ramayana tune uploaded.');
   await refresh();
  }
  setBusy(false);
 }
 async function play(tune:Tune){
  setMessage('');
  if(active?.id===tune.id){setActive(null);return}
  const {data,error}=await supabase.storage.from(BUCKET).createSignedUrl(tune.storage_path,3600);
  if(error){setMessage(error.message);return}
  setActive({id:tune.id,url:data.signedUrl});
 }
 async function remove(tune:Tune){
  if(!confirm('Remove “'+tune.title+'” from Ramayana Tunes?'))return;
  setBusy(true);setMessage('');
  const {error:storageError}=await supabase.storage.from(BUCKET).remove([tune.storage_path]);
  if(storageError){setMessage(storageError.message);setBusy(false);return}
  const {error}=await supabase.from('bhakti_ramayana_tunes').delete().eq('id',tune.id);
  if(error)setMessage(error.message);
  else{if(active?.id===tune.id)setActive(null);setMessage('Tune removed.');await refresh()}
  setBusy(false);
 }

 return <section aria-labelledby="ramayana-tunes-heading">
  <h3 id="ramayana-tunes-heading">🎵 Ramayana Tunes</h3>
  <p className="muted">Listen to tunes shared by Bhakti Sangam members, or upload a new audio recording with its title. Accepted audio files can be up to 50 MB.</p>
  <div style={{border:'1px solid #d1d5db',borderRadius:10,padding:14,marginBottom:18}}>
   <h4>Share a Ramayana tune</h4>
   <label> Tune title
    <input value={title} maxLength={160} onChange={e=>setTitle(e.target.value)} placeholder="Enter the tune title"/>
   </label>
   <label> Audio file
    <input id="ramayana-tune-file" type="file" accept="audio/mpeg,audio/mp4,audio/x-m4a,audio/aac,audio/wav,audio/x-wav,audio/ogg,audio/opus,audio/webm" onChange={e=>setFile(e.target.files?.[0]||null)}/>
   </label>
   <button disabled={busy||!userId||!title.trim()||!file} onClick={upload}>{busy?'Please wait…':'Upload tune'}</button>
  </div>
  <div style={{border:'1px solid #d1d5db',borderRadius:10,padding:14,marginBottom:18}}>
   <h4>▶ Add YouTube link</h4>
   <label>Video title<input value={youtubeTitle} maxLength={160} onChange={e=>setYoutubeTitle(e.target.value)} placeholder="Name of the tune"/></label>
   <label>YouTube URL<input type="url" value={youtubeUrl} onChange={e=>setYoutubeUrl(e.target.value)} placeholder="https://www.youtube.com/watch?v=..."/></label>
   <button disabled={busy||!userId||!youtubeTitle.trim()||!youtubeId(youtubeUrl)} onClick={addYoutube}>Add YouTube tune</button>
  </div>
  {message&&<p role="status">{message}</p>}
  <h4>Shared tunes ({tunes.length+youtubeTunes.length})</h4>
  {loading?<p>Loading tunes…</p>:tunes.length===0&&youtubeTunes.length===0?<p className="muted">No tunes uploaded yet. You can add the first one above.</p>:<div>
   {youtubeTunes.map((tune,index)=><article key={'yt-'+tune.id} style={{border:'1px solid #d1d5db',borderRadius:10,marginBottom:10,padding:12}}>
    <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',gap:10,flexWrap:'wrap'}}>
     <strong>{index+1}. ▶ {tune.title} · YouTube</strong>
     <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
      <button className="outline" onClick={()=>{setActive(null);setYoutubeActive(youtubeActive===tune.id?null:tune.id)}}>{youtubeActive===tune.id?'Hide player':'▶ Play'}</button>
      {tune.uploaded_by===userId&&<button className="outline" disabled={busy} onClick={()=>removeYoutube(tune)}>Delete my link</button>}
     </div>
    </div>
    {youtubeActive===tune.id&&<div style={{marginTop:10}}><iframe title={tune.title} src={'https://www.youtube-nocookie.com/embed/'+tune.youtube_video_id} allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowFullScreen style={{width:'100%',aspectRatio:'16 / 9',border:0,borderRadius:8}}/><p><a href={tune.youtube_url} target="_blank" rel="noopener noreferrer">Open on YouTube if embedding is unavailable</a></p></div>}
    <small className="muted">Added {new Date(tune.created_at).toLocaleDateString()}</small>
   </article>)}
   {tunes.map((tune,index)=><article key={tune.id} style={{border:'1px solid #d1d5db',borderRadius:10,marginBottom:10,padding:12}}>
    <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',gap:10,flexWrap:'wrap'}}>
     <strong>{youtubeTunes.length+index+1}. {tune.title} · Audio</strong>
     <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
      <button className="outline" onClick={()=>play(tune)}>{active?.id===tune.id?'⏸ Hide player':'▶ Play'}</button>
      {(tune.uploaded_by===userId)&&<button className="outline" disabled={busy} onClick={()=>remove(tune)}>Delete my upload</button>}
     </div>
    </div>
    {active?.id===tune.id&&<audio controls autoPlay src={active.url} style={{width:'100%',marginTop:10}}>Your browser does not support audio playback.</audio>}
    <small className="muted">Added {new Date(tune.created_at).toLocaleDateString()}</small>
   </article>)}
  </div>}
 </section>
}
