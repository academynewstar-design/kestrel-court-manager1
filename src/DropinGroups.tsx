import {useEffect,useRef,useState} from 'react';
import {supabase} from './lib/supabase';

export type DropinGroup={id:number;owner_id:string;owner_name:string;session_id:number;guest_names:string[];total_people:number;status:string;expires_at:string;review_note:string|null;unit_price:number;total_price:number;credit_paid:number;amount_due:number;session_date:string;start_time:string;end_time:string;sport:string;location:string;court:string;member_ids:string[]};
const money=(n:number)=>'$'+Number(n||0).toFixed(2);
const when=(g:DropinGroup)=>g.session_date+' · '+g.start_time.slice(0,5)+'–'+g.end_time.slice(0,5);
const expiry=(g:DropinGroup)=>new Date(g.expires_at).toLocaleString('en-CA',{timeZone:'America/Toronto',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'});
const changed=()=>window.dispatchEvent(new Event('kestrel-group-bookings-changed'));

export function GroupRequestButton({session,availability,registered,level,requests,onSaved,disabled=false}:{session:any;availability?:{occupied:number;total_capacity:number};registered:boolean;level:string;requests:DropinGroup[];onSaved:()=>void;disabled?:boolean}){
 const[open,setOpen]=useState(false),[quantity,setQuantity]=useState('2'),[names,setNames]=useState<string[]>(['']),[eligible,setEligible]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const dialog=useRef<HTMLDialogElement>(null);
 const active=requests.some(g=>String(g.session_id)===String(session.id)&&['pending','approved'].includes(g.status));
 const max=availability?Math.max(0,availability.total_capacity-availability.occupied+(registered?1:0)):0;
 const count=Number(quantity);
 useEffect(()=>{if(open&&!dialog.current?.open)dialog.current?.showModal()},[open]);
 function editQuantity(value:string){setQuantity(value);const n=Number(value);if(Number.isInteger(n)&&n>=2&&n<=max)setNames(old=>Array.from({length:n-1},(_,i)=>old[i]||''))}
 function close(){if(busy)return;dialog.current?.close();setOpen(false)}
 async function submit(){
  if(busy)return;setBusy(true);setError('');
  try{
   const{error}=await supabase.rpc('request_dropin_group',{p_session_id:session.id,p_guest_names:names.map(n=>n.trim()),p_level:level,p_eligible:eligible});
   if(error)throw error;setMessage('Group request sent. Your guests will appear only after Admin approval. Do not pay for the guests until approval.');
   dialog.current?.close();setOpen(false);setEligible(false);onSaved();changed();
  }catch(e:any){setError(e.message||'Unable to request group spots.')}finally{setBusy(false)}
 }
 return <>{!active&&<button className="outline" disabled={disabled||max<2} onClick={()=>{setOpen(true);setError('');setMessage('')}}>{registered?'Add guests — Admin approval':'Book for a group'}</button>}{message&&<p role="status" className="success">{message}</p>}{open&&<dialog ref={dialog} aria-labelledby={'group-request-title-'+session.id} onCancel={e=>{e.preventDefault();close()}} style={{width:'min(94vw,540px)',maxHeight:'85dvh',overflowY:'auto',border:0,borderRadius:16,padding:24}}>
 <h2 id={'group-request-title-'+session.id}>Book Drop-in spots for your group</h2>
 <p>{session.sports?.name} · {session.locations?.name}<br/>{session.session_date} · {session.start_time.slice(0,5)}–{session.end_time.slice(0,5)}</p>
 <p>{max} total places available for your group{registered?' (including your existing spot)':''}. Every person uses one spot.</p>
 <form onSubmit={e=>{e.preventDefault();submit()}}>
 <label>Total people, including you<input required type="number" min={2} max={max} step={1} value={quantity} onChange={e=>editQuantity(e.target.value)}/></label>
 {names.map((name,i)=><label key={i}>Guest {i+1}: real name<input required maxLength={80} autoComplete="off" value={name} onChange={e=>setNames(old=>old.map((n,k)=>k===i?e.target.value:n))}/></label>)}
 <p><strong>{Number.isInteger(count)&&count>=2?money(count*Number(session.price||0)):'—'} for the whole group</strong> · {money(Number(session.price||0))} per person.</p>
 <p className="muted">Admin must approve the request before the guests appear in the Going List. Requested spots are held for up to 24 hours, ending at least 1 hour before the game. Your roster label will show your name + {Math.max(1,count-1)}.</p>
 {registered&&<p className="muted">Your existing spot stays unchanged while guests await approval. An existing payment will be credited after approval.</p>}
 <label style={{display:'flex',alignItems:'flex-start',gap:8}}><input type="checkbox" style={{width:'auto'}} checked={eligible} onChange={e=>setEligible(e.target.checked)}/>I have permission to register these guests and confirm they meet this activity's age and participation requirements.</label>
 <p>After approval, the organiser manages payment and attendance for the whole group. Send the amount due, then tap Mark Paid. Not Going cancels every group member.</p>
 {error&&<p className="error" role="alert">{error}</p>}
 <div className="rowactions"><button disabled={busy||!eligible||!Number.isInteger(count)||count<2||count>max||names.length!==count-1||names.some(n=>!n.trim())}>{busy?'Sending…':'Request '+count+' spots'}</button><button type="button" className="outline" disabled={busy} onClick={close}>Cancel</button></div>
 </form></dialog>}</>;
}

export function MyGroupRequests({requests,onChanged}:{requests:DropinGroup[];onChanged:()=>void}){
 const[busy,setBusy]=useState<number|null>(null),[error,setError]=useState('');
 const rows=requests.filter(g=>g.status!=='approved').slice(0,10);
 async function cancel(g:DropinGroup){setBusy(g.id);setError('');const{error}=await supabase.rpc('cancel_dropin_group',{p_request_id:g.id});if(error)setError(error.message);else{onChanged();changed()}setBusy(null)}
 if(!rows.length)return null;
 return <section className="card"><h2>My group Drop-in requests</h2>{error&&<p className="error" role="alert">{error}</p>}{rows.map(g=><article className="notice" key={g.id}><strong>{g.owner_name} + {g.total_people-1} · {g.total_people} people</strong><p>{g.sport} · {g.location} · {g.court}<br/>{when(g)}</p><p><strong>{g.status==='pending'?'Awaiting Admin approval':g.status==='rejected'?'Not approved':g.status==='expired'?'Request expired':'Group cancelled'}</strong></p>{g.status==='pending'&&<><p className="muted">Guests are not on the Going List yet. Spots held until {expiry(g)} Toronto time. Do not pay for guests until approval.</p><button className="outline" disabled={busy!==null} onClick={()=>cancel(g)}>{busy===g.id?'Withdrawing…':'Withdraw group request'}</button></>}{g.review_note&&<p>Admin: {g.review_note}</p>}</article>)}</section>;
}

export function AdminGroupApprovals(){
 const[requests,setRequests]=useState<DropinGroup[]>([]),[notes,setNotes]=useState<Record<string,string>>({}),[checked,setChecked]=useState<Record<string,boolean>>({}),[busy,setBusy]=useState<number|null>(null),[error,setError]=useState(''),[message,setMessage]=useState('');
 async function load(){const{data,error}=await supabase.rpc('list_dropin_groups');if(error)setError(error.message);else setRequests((data||[]).filter((g:DropinGroup)=>g.status==='pending'))}
 useEffect(()=>{load();const t=setInterval(load,30000);window.addEventListener('kestrel-group-bookings-changed',load);return()=>{clearInterval(t);window.removeEventListener('kestrel-group-bookings-changed',load)}},[]);
 async function review(g:DropinGroup,approve:boolean){setBusy(g.id);setError('');setMessage('');const{error}=await supabase.rpc('review_dropin_group',{p_request_id:g.id,p_approve:approve,p_note:notes[String(g.id)]||null});if(error)setError(error.message);else{setMessage(approve?g.owner_name+' + '+(g.total_people-1)+' approved. All '+g.total_people+' places are now on the roster.':'Group request rejected; held spots released.');await load();changed()}setBusy(null)}
 if(!requests.length&&!error&&!message)return null;
 return <section className="card"><div className="sectionhead"><h2>Group Drop-in approvals ({requests.length})</h2><button className="outline" onClick={load}>Refresh</button></div>{error&&<p className="error" role="alert">{error}</p>}{message&&<p className="success" role="status">{message}</p>}{requests.map(g=><article className="notice" key={g.id}><h3>{g.owner_name} + {g.total_people-1} · {g.total_people} people</h3><p>{g.sport} · {g.location} · {g.court}<br/>{when(g)}</p><p>Guests: {g.guest_names.join(', ')}</p><p>{money(g.total_price)} total · hold expires {expiry(g)} Toronto time</p><label>Optional reply / review note<input maxLength={500} value={notes[String(g.id)]||''} onChange={e=>setNotes(old=>({...old,[g.id]:e.target.value}))}/></label><label style={{display:'flex',alignItems:'flex-start',gap:8}}><input type="checkbox" style={{width:'auto'}} checked={!!checked[String(g.id)]} onChange={e=>setChecked(old=>({...old,[g.id]:e.target.checked}))}/>I checked the guest names and activity eligibility. Capacity will be checked again on approval.</label><div className="rowactions"><button disabled={busy!==null||!checked[String(g.id)]} onClick={()=>review(g,true)}>{busy===g.id?'Saving…':'Approve '+g.total_people+' people'}</button><button className="outline" disabled={busy!==null} onClick={()=>review(g,false)}>Reject</button></div></article>)}</section>;
}

export function collapseGroupRoster(rows:any[],groups:DropinGroup[]){
 const memberToGroup=new Map<string,DropinGroup>();
 groups.filter(g=>g.status==='approved').forEach(g=>g.member_ids.forEach(id=>memberToGroup.set(String(g.session_id)+'|'+id,g)));
 const result:any[]=[];const emitted=new Set<number>();
 for(const row of rows){
  const group=memberToGroup.get(String(row.session_id)+'|'+String(row.user_id));
  if(!group){result.push({...row,party_size:1});continue}
  if(emitted.has(group.id))continue;emitted.add(group.id);
  const members=rows.filter(r=>String(r.session_id)===String(group.session_id)&&group.member_ids.includes(String(r.user_id)));
  const lead=members.find(r=>String(r.user_id)===group.owner_id)||row;
  result.push({...lead,party_size:members.length,profiles:{...lead.profiles,full_name:group.owner_name+(members.length>1?' + '+(members.length-1):'')},group_booking:group});
 }
 return result;
}
