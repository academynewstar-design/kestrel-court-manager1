import {useEffect,useState} from 'react';
import {supabase} from './supabase';
type Category='Volleyball'|'Badminton'|'Soccer'|'Pickleball'|'Basketball';
type Media={id:number;category:Category;title:string;url:string;created_at:string};
const categories:Category[]=['Volleyball','Badminton','Soccer','Pickleball','Basketball'];
export default function SportsMediaLinks({isAdmin=false}:{isAdmin?:boolean}){
 const[items,setItems]=useState<Media[]>([]);
 const[category,setCategory]=useState<Category>('Volleyball');
 const[title,setTitle]=useState('');
 const[url,setUrl]=useState('');
 const[editing,setEditing]=useState<number|null>(null);
 const[busy,setBusy]=useState(false);
 const[message,setMessage]=useState('');
 async function load(){const{data,error}=await supabase.from('sports_media_links').select('id,category,title,url,created_at').order('created_at',{ascending:false});if(error)setMessage(error.message);else setItems((data||[]) as Media[])}
 useEffect(()=>{void load()},[]);
 function validYoutube(value:string){try{const u=new URL(value);return u.protocol==='https:'&&['youtube.com','www.youtube.com','m.youtube.com','youtu.be'].includes(u.hostname)}catch{return false}}
 async function save(e:React.FormEvent){e.preventDefault();if(!validYoutube(url)){setMessage('Enter a valid HTTPS YouTube link.');return}setBusy(true);setMessage('');const{data:auth}=await supabase.auth.getUser();if(!auth.user){setBusy(false);setMessage('Please sign in first.');return}const payload={category,title:title.trim(),url:url.trim()};const{error}=editing===null?await supabase.from('sports_media_links').insert({...payload,created_by:auth.user.id}):await supabase.from('sports_media_links').update(payload).eq('id',editing);setBusy(false);if(error){setMessage(error.message);return}setEditing(null);setTitle('');setUrl('');setMessage('Media link saved.');await load()}
 async function remove(item:Media){if(!confirm('Delete media link "'+item.title+'"?'))return;const{error}=await supabase.from('sports_media_links').delete().eq('id',item.id);setMessage(error?.message||'Media link deleted.');if(!error)await load()}
 return <section className="card"><h2>🎬 Media Links</h2><p className="muted">Watch our sports videos and highlights on YouTube.</p><div className="tabs" style={{display:'flex',gap:8,flexWrap:'wrap'}}>{categories.map(c=><button key={c} className={category===c?'active':'outline'} onClick={()=>setCategory(c)}>{c}</button>)}</div>
 {isAdmin&&<form onSubmit={save} style={{border:'1px solid #d1d5db',padding:12,borderRadius:10,margin:'16px 0',display:'grid',gap:10}}><h3>{editing===null?'Add media link':'Edit media link'}</h3><label>Video title<input required maxLength={180} value={title} onChange={e=>setTitle(e.target.value)} placeholder="e.g. Tuesday volleyball highlights"/></label><label>YouTube URL<input required type="url" value={url} onChange={e=>setUrl(e.target.value)} placeholder="https://www.youtube.com/watch?v=..."/></label><div><button disabled={busy||!title.trim()||!url.trim()} type="submit">{busy?'Saving...':editing===null?'Add video':'Save changes'}</button>{editing!==null&&<button type="button" className="outline" onClick={()=>{setEditing(null);setTitle('');setUrl('')}}>Cancel</button>}</div></form>}
 {message&&<p role="status">{message}</p>}
 <div style={{display:'grid',gap:12,marginTop:16}}>{items.filter(item=>item.category===category).map(item=><article key={item.id} style={{border:'1px solid #d1d5db',padding:14,borderRadius:10}}><strong>{item.title}</strong><p><a href={item.url} target="_blank" rel="noopener noreferrer">▶ Watch on YouTube</a></p>{isAdmin&&<div style={{display:'flex',gap:8}}><button className="outline" onClick={()=>{setCategory(item.category);setEditing(item.id);setTitle(item.title);setUrl(item.url)}}>Edit</button><button className="outline" onClick={()=>void remove(item)}>Delete</button></div>}</article>)}{!items.some(item=>item.category===category)&&<p className="muted">No videos added in this category yet.</p>}</div></section>
}