import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';

type Event={id:number;title:string;city:string;starts_at:string;individual_fee:number;team_fee:number;minimum_age:number;location_details:string;payment_email:string|null;status:string;sports:{name:string}};
type Entry={id:number;event_id:number;user_id:string;entry_kind:'individual'|'team';team_name:string|null;player_names:string[];status:string;payment_status:string;profiles?:{full_name:string;email:string}};
const eventSelect='id,title,city,starts_at,individual_fee,team_fee,minimum_age,location_details,payment_email,status,sports(name)';
const currency=(v:number)=>new Intl.NumberFormat('en-CA',{style:'currency',currency:'CAD',maximumFractionDigits:0}).format(v);
const eventTime=(v:string)=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Toronto',weekday:'long',year:'numeric',month:'long',day:'numeric',hour:'numeric',minute:'2-digit'}).format(new Date(v))+' (Toronto time)';
export const entryFee=(event:Pick<Event,'individual_fee'|'team_fee'>,kind:Entry['entry_kind'])=>kind==='team'?event.team_fee:event.individual_fee;

export default function Tournaments({profile}:{profile:{id:string;full_name:string}}){
 const[events,setEvents]=useState<Event[]>([]),[entries,setEntries]=useState<Entry[]>([]);
 const[loading,setLoading]=useState(true),[error,setError]=useState(''),[message,setMessage]=useState('');
 async function load(){
  const[a,b]=await Promise.all([supabase.from('tournament_events').select(eventSelect).order('starts_at'),supabase.from('tournament_entries').select('*').eq('user_id',profile.id)]);
  setError(a.error?.message||b.error?.message||'');setEvents((a.data||[]) as unknown as Event[]);setEntries(b.data||[]);setLoading(false);
 }
 useEffect(()=>{load()},[profile.id]);
 return <details className="card upcoming-games" id="tournaments"><summary><strong>🏀 Basketball / Tournaments</strong><span className="muted">Expand for details &amp; registration</span></summary><p>Register individually or enter your team. Season and Drop-in players can use their existing account.</p>
  <button className="outline" onClick={load}>Refresh tournaments</button>
  {loading&&<p role="status">Loading tournaments…</p>}{error&&<p role="alert" className="error">Unable to load tournaments: {error}</p>}{message&&<p role="status">{message}</p>}
  {!loading&&!error&&events.length===0&&<p>No tournaments are listed yet.</p>}
  {events.map(event=><TournamentCard key={event.id} event={event} profile={profile} entry={entries.find(e=>e.event_id===event.id)} onSaved={async(text)=>{setMessage(text);await load()}}/>)}
 </details>;
}
function TournamentCard({event,entry,profile,onSaved}:{event:Event;entry?:Entry;profile:{id:string;full_name:string};onSaved:(text:string)=>Promise<void>}){
 const[kind,setKind]=useState<'individual'|'team'>('individual'),[teamName,setTeamName]=useState(''),[names,setNames]=useState(''),[eligible,setEligible]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const[clock,setClock]=useState(Date.now());useEffect(()=>{const timer=setInterval(()=>setClock(Date.now()),30000);return()=>clearInterval(timer)},[]);
 const open=event.status==='open'&&new Date(event.starts_at).getTime()>clock;
 const registered=entry?.status==='registered';
 async function save(){
  const players=kind==='team'?names.split('\n').map(n=>n.trim()).filter(Boolean):[profile.full_name.trim()];
  if(!eligible||players.length===0||players.some(n=>n.length<2)||kind==='team'&&!teamName.trim()){setError('Complete the name fields and eligibility confirmation.');return}
  setBusy(true);setError('');
  const payload={event_id:event.id,user_id:profile.id,entry_kind:kind,team_name:kind==='team'?teamName.trim():null,player_names:players,eligibility_confirmed:true,status:'registered'};
  const result=await supabase.from('tournament_entries').insert(payload).select('id').single();
  if(result.error)setError(result.error.code==='23505'?'You already have an entry. Refresh tournaments to view it.':result.error.message);
  else await onSaved('Tournament entry saved. Payment is pending.');
  setBusy(false);
 }
 async function update(values:Partial<Entry>,text:string){
  if(!entry)return;setBusy(true);setError('');
  const{error}=await supabase.from('tournament_entries').update(values).eq('id',entry.id).eq('user_id',profile.id).select('id').single();
  if(error)setError(error.message);else await onSaved(text);setBusy(false);
 }
 return <article className="notice"><h3>{event.title}</h3><p><strong>{event.city} · {event.sports?.name}</strong></p><p>{eventTime(event.starts_at)}</p><p><strong>{currency(event.individual_fee)} per player or {currency(event.team_fee)} per team · Ages {event.minimum_age}+</strong></p><p>{event.location_details}</p>
  {event.status==='cancelled'?<p className="error">This tournament is cancelled.</p>:!open&&<p>Registration closed.</p>}
  {entry&&<div className="notice"><h4>My tournament entry</h4><p>{entry.entry_kind==='team'?'Team: '+entry.team_name:'Individual entry'} · {entry.status==='cancelled'?'Cancelled':'Registered'}</p><p>{entry.player_names.join(', ')}</p><p><strong>{currency(entryFee(event,entry.entry_kind))} {entry.entry_kind==='team'?'for the whole team':'for your entry'}</strong> · {entry.payment_status==='paid'?'Marked paid':'Payment pending'}</p>
   {registered&&entry.payment_status!=='paid'&&<p>{event.payment_email?<>Send {currency(entryFee(event,entry.entry_kind))} to <strong>{event.payment_email}</strong>. Include your name{entry.entry_kind==='team'?' and team name':''}.</>:<>Use <strong>Messages</strong> to ask Admin for tournament payment instructions.</>}</p>}
   {entry.status==='cancelled'&&<p>For payment or refund questions, contact Admin through Messages.</p>}
   {open&&registered&&<div className="rowactions"><button disabled={busy||entry.payment_status==='paid'} onClick={()=>{if(window.confirm('Only mark Paid after sending your tournament payment. False payment claims may result in account suspension. Have you sent the payment?'))update({payment_status:'paid'},'Tournament entry marked paid.')}}>{entry.payment_status==='paid'?'Paid ✓':'Mark tournament Paid'}</button><button className="outline" disabled={busy} onClick={()=>{if(window.confirm('Cancel your tournament entry? Contact Admin for any refund request.'))update({status:'cancelled'},'Tournament entry cancelled.')}}>Cancel tournament entry</button></div>}
   {open&&entry.status==='cancelled'&&<button disabled={busy} onClick={()=>update({status:'registered'},'Tournament entry restored with its previous payment status.')}>Rejoin tournament</button>}
  </div>}
  {!entry&&open&&<div className="form"><label>Entry type<select value={kind} onChange={e=>{setKind(e.target.value as 'individual'|'team');setEligible(false)}}><option value="individual">Individual — {currency(event.individual_fee)}</option><option value="team">Team — {currency(event.team_fee)} total</option></select></label>
   {kind==='individual'?<p>Player: <strong>{profile.full_name}</strong></p>:<><label>Team name<input value={teamName} maxLength={100} onChange={e=>setTeamName(e.target.value)}/></label><label>Player names (one per line, including yourself if playing)<textarea value={names} maxLength={10000} rows={5} onChange={e=>setNames(e.target.value)}/></label><p>You are the team contact. Team members included here do not need to register individually for the same team.</p></>}
   <label style={{display:'flex',alignItems:'flex-start',gap:8}}><input type="checkbox" checked={eligible} onChange={e=>setEligible(e.target.checked)} style={{width:'auto'}}/>{kind==='team'?`I confirm all listed players are ${event.minimum_age}+ and I have permission to register this team.`:`I confirm I am ${event.minimum_age} or older.`}</label>
   <p><strong>Total: {currency(entryFee(event,kind))}</strong>{kind==='team'?' for the whole team':''}</p><button disabled={busy||!eligible||kind==='team'&&(!teamName.trim()||!names.trim())} onClick={save}>{busy?'Saving…':kind==='team'?'Register team':'Register individually'}</button>
  </div>}
  {error&&<p role="alert" className="error">{error}</p>}
 </article>;
}

export function AdminTournaments(){
 const[events,setEvents]=useState<Event[]>([]),[entries,setEntries]=useState<Entry[]>([]),[selected,setSelected]=useState(''),[email,setEmail]=useState(''),[status,setStatus]=useState('open'),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true);
 async function load(){const[a,b]=await Promise.all([supabase.from('tournament_events').select(eventSelect).order('starts_at'),supabase.from('tournament_entries').select('*,profiles(full_name,email)').order('created_at')]);setMessage(a.error?.message||b.error?.message||'');setEvents((a.data||[]) as unknown as Event[]);setEntries(b.data||[]);setLoading(false)}
 useEffect(()=>{load()},[]);
 const event=events.find(e=>String(e.id)===selected),list=entries.filter(e=>String(e.event_id)===selected);
 async function updateEntry(entry:Entry,values:Partial<Entry>){setBusy(true);const{error}=await supabase.from('tournament_entries').update(values).eq('id',entry.id).select('id').single();if(error)setMessage(error.message);else{await load();setMessage('Tournament entry updated.')}setBusy(false)}
 async function saveSettings(){if(!event)return;setBusy(true);const{error}=await supabase.from('tournament_events').update({payment_email:email.trim()||null,status}).eq('id',event.id).select('id').single();if(error)setMessage(error.message);else{await load();setMessage('Tournament settings saved.')}setBusy(false)}
 return <section className="card"><h2>🏀 Tournament registrations</h2><button className="outline" onClick={load}>Refresh tournament entries</button>{loading&&<p>Loading tournaments…</p>}{message&&<p role="status">{message}</p>}
  <label>Tournament<select value={selected} onChange={e=>{setSelected(e.target.value);const event=events.find(x=>String(x.id)===e.target.value);setEmail(event?.payment_email||'');setStatus(event?.status||'open')}}><option value="">Choose tournament</option>{events.map(e=><option key={e.id} value={e.id}>{e.title} · {eventTime(e.starts_at)}</option>)}</select></label>
  {event&&<><form onSubmit={e=>{e.preventDefault();saveSettings()}}><label>Tournament payment email<input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="Payment recipient"/></label><label>Registration status<select value={status} onChange={e=>setStatus(e.target.value)}><option value="open">Open</option><option value="closed">Closed</option><option value="cancelled">Tournament cancelled</option></select></label><button disabled={busy}>Save tournament settings</button></form>
   <p>{list.filter(e=>e.status==='registered'&&e.entry_kind==='team').length} team entries · {list.filter(e=>e.status==='registered'&&e.entry_kind==='individual').length} individual entries · {list.filter(e=>e.status==='registered'&&e.payment_status==='unpaid').length} unpaid entries</p>
   {list.map(entry=><article className="notice" key={entry.id}><h3>{entry.entry_kind==='team'?entry.team_name:'Individual: '+entry.player_names[0]}</h3><p>Contact: {entry.profiles?.full_name} · {entry.profiles?.email}</p><p>Players: {entry.player_names.join(', ')}</p><p>{entry.status} · {currency(entryFee(event,entry.entry_kind))} · {entry.payment_status}</p><div className="rowactions"><button disabled={busy||entry.status!=='registered'} onClick={()=>updateEntry(entry,{payment_status:entry.payment_status==='paid'?'unpaid':'paid'})}>{entry.payment_status==='paid'?'Change to Unpaid':'Mark Paid'}</button><button className="outline" disabled={busy} onClick={()=>{if(window.confirm('Change this tournament entry status?'))updateEntry(entry,{status:entry.status==='registered'?'cancelled':'registered'})}}>{entry.status==='registered'?'Cancel entry':'Restore entry'}</button></div></article>)}
   {list.length===0&&<p>No tournament registrations yet.</p>}
  </>}
 </section>;
}
