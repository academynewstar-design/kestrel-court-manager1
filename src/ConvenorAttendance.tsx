import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import './ConvenorAttendance.css';

type Player={user_id:string;player_name:string;court:string;kind:string;not_going:boolean};
type Sheet={session_id:number;players:Player[];roster_token:string;marks:Record<string,boolean>;revision:number;confirmed_at:string|null;no_show_count:number|null;report_queued:boolean;can_save:boolean;can_confirm:boolean};
type Activity={session_id:number;location:string;city:string;sport:string;session_date:string;start_time:string;end_time:string;confirmed_at:string|null};
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Toronto',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const label=(a:Activity)=>`${a.session_date} · ${a.start_time.slice(0,5)}–${a.end_time.slice(0,5)} · ${a.location} · ${a.sport}`;

export function useConvenorAccess(userId:string){
 const[allowed,setAllowed]=useState(false);
 useEffect(()=>{let active=true;setAllowed(false);supabase.rpc('get_my_convenor_locations').then(({data,error})=>{if(active)setAllowed(!error&&!!data?.length)});return()=>{active=false}},[userId]);
 return allowed;
}

export default function ConvenorAttendance(){
 const[activities,setActivities]=useState<Activity[]>([]);const[selected,setSelected]=useState('');
 const[dirty,setDirty]=useState(false);
 const[loading,setLoading]=useState(true);const[error,setError]=useState('');const[attempt,setAttempt]=useState(0);
 useEffect(()=>{let active=true;setLoading(true);setError('');supabase.rpc('get_convenor_activities').then(({data,error})=>{
  if(!active)return;setLoading(false);if(error){setError(error.message);return}
  const rows:Activity[]=data||[];setActivities(rows);setSelected(old=>rows.some(a=>String(a.session_id)===old)?old:String((rows.find(a=>a.session_date>=today())||rows.at(-1))?.session_id||''));
 });return()=>{active=false}},[attempt]);
 const activity=activities.find(a=>String(a.session_id)===selected);
 return <section className="card convenor-attendance" aria-label="Convenor attendance"><h2>✓ Confirm attendance</h2>
  <p>Tick the players who attended, court by court. Save during play, then confirm the full list after the session ends. Players who marked Not Going will not be reported as unexcused absences.</p>
  {loading&&<p role="status">Loading location sessions…</p>}
  {error&&<p role="alert" className="error">Unable to load attendance: {error}</p>}
  {!loading&&<button className="outline" onClick={()=>{if(!dirty||window.confirm('Discard unsaved attendance ticks and refresh?'))setAttempt(n=>n+1)}}>Refresh sessions</button>}
  {!loading&&!error&&!activities.length&&<p>No available sessions for your convenor locations in the last or next seven days.</p>}
  {!!activities.length&&<label>Location session<select value={selected} onChange={e=>{if(!dirty||window.confirm('Discard unsaved attendance ticks and change session?'))setSelected(e.target.value)}}>{activities.map(a=><option value={a.session_id} key={a.session_id}>{label(a)}{a.confirmed_at?' · Confirmed':''}</option>)}</select></label>}
  {activity&&<AttendanceSheet key={`${selected}:${attempt}`} activity={activity} onDirtyChange={setDirty}/>}
 </section>;
}

export function AttendanceSheet({activity,onDirtyChange}:{activity:Activity;onDirtyChange?:(dirty:boolean)=>void}){
 const[sheet,setSheet]=useState<Sheet|null>(null);const[marks,setMarks]=useState<Record<string,boolean>>({});
 const[busy,setBusy]=useState(false);const[loading,setLoading]=useState(true);const[error,setError]=useState('');const[message,setMessage]=useState('');
 const[reviewing,setReviewing]=useState(false);const[acknowledged,setAcknowledged]=useState(false);
 const dirty=!!sheet&&!sheet.confirmed_at&&JSON.stringify(marks)!==JSON.stringify(sheet.marks);
 useEffect(()=>{onDirtyChange?.(dirty);return()=>onDirtyChange?.(false)},[dirty,onDirtyChange]);
 useEffect(()=>{if(!dirty)return;const warn=(e:BeforeUnloadEvent)=>{e.preventDefault();e.returnValue=''};window.addEventListener('beforeunload',warn);return()=>window.removeEventListener('beforeunload',warn)},[dirty]);
 async function load(){setLoading(true);setError('');const{data,error}=await supabase.rpc('get_convenor_attendance',{p_session_id:activity.session_id});setLoading(false);
  if(error){setError(error.message);return}setSheet(data);setMarks(data.marks||{});setReviewing(false);setAcknowledged(false);
 }
 useEffect(()=>{let active=true;setLoading(true);supabase.rpc('get_convenor_attendance',{p_session_id:activity.session_id}).then(({data,error})=>{
  if(!active)return;setLoading(false);if(error){setError(error.message);return}setSheet(data);setMarks(data.marks||{});
 });return()=>{active=false}},[activity.session_id]);
 // Refresh only timing permissions. Never replace a convenor's unsaved ticks.
 useEffect(()=>{if(!sheet||sheet.confirmed_at)return;let active=true;const timer=setInterval(async()=>{
  const{data,error}=await supabase.rpc('get_convenor_attendance',{p_session_id:activity.session_id});
  if(active&&!error&&data)setSheet(old=>old?{...old,can_save:data.can_save,can_confirm:data.can_confirm}:old);
 },60000);return()=>{active=false;clearInterval(timer)}},[activity.session_id,!!sheet,sheet?.confirmed_at]);
 if(loading)return <p role="status">Loading players…</p>;
 if(!sheet)return <><p role="alert" className="error">Unable to load player list: {error}</p><button className="outline" onClick={load}>Retry player list</button></>;
 const players=sheet.players;const courts=[...new Set(players.map(p=>p.court))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
 const absent=players.filter(p=>!marks[p.user_id]&&!p.not_going);const attended=players.filter(p=>marks[p.user_id]).length;
 async function save(confirm:boolean){
  if(busy||!sheet)return;setBusy(true);setError('');setMessage('');
  const completeMarks=Object.fromEntries(players.map(p=>[p.user_id,!!marks[p.user_id]]));
  const{data,error}=await supabase.rpc('save_convenor_attendance',{p_session_id:sheet.session_id,p_marks:completeMarks,p_roster_token:sheet.roster_token,p_revision:sheet.revision,p_confirm:confirm});
  setBusy(false);if(error){setError(error.message);return}setSheet(data);setMarks(data.marks||{});setReviewing(false);setAcknowledged(false);
  setMessage(confirm?(data.report_queued?`Attendance confirmed. ${data.no_show_count} absent without Not Going; report queued for academynewstar@gmail.com.`:'Attendance confirmed. No unexcused absences to report.'):'Attendance saved. No absence report has been sent.');
 }
 return <div className="attendance-sheet"><h3>{activity.location} · {activity.session_date}</h3><p>{activity.sport} · {activity.start_time.slice(0,5)}–{activity.end_time.slice(0,5)} · Toronto time</p>
  {sheet.confirmed_at&&<><p className="success">Attendance confirmed · {new Date(sheet.confirmed_at).toLocaleString('en-CA',{timeZone:'America/Toronto'})} Toronto. {sheet.no_show_count||0} absent without Not Going.</p><p className="muted">For a correction, contact Admin through Messages.</p></>}
  {!sheet.confirmed_at&&!sheet.can_save&&<p className="muted">Attendance opens one hour before play. Lists can be confirmed for up to seven days after the session.</p>}
  {!sheet.confirmed_at&&sheet.can_save&&!sheet.can_confirm&&<p className="muted">Save your ticks during play. Final confirmation opens after the session ends.</p>}
  <p><strong>{attended} attended</strong> / {players.length} players</p>
  {courts.map(court=><fieldset key={court} disabled={busy||!!sheet.confirmed_at||!sheet.can_save||reviewing}><legend>{court}</legend>{players.filter(p=>p.court===court).map(p=><label className="attendance-player" key={p.user_id}>
   <input type="checkbox" checked={!!marks[p.user_id]} onChange={e=>{setMarks(old=>({...old,[p.user_id]:e.target.checked}));setMessage('')}}/>
   <span><strong>{p.player_name}</strong><small>{p.kind}{p.not_going?' · Not Going (excused)':''}</small></span><span className="attendance-status">{marks[p.user_id]?'Attended':p.not_going?'Excused':'Not ticked'}</span>
  </label>)}</fieldset>)}
  {!players.length&&<p>No players on this session’s roster.</p>}
  {error&&<div role="alert" className="error"><p>Attendance was not saved: {error}</p><button className="outline" disabled={busy} onClick={load}>Reload player list</button><p>Reloading discards unsaved ticks.</p></div>}
  {message&&<p role="status" className="success">{message}</p>}
  {!sheet.confirmed_at&&<>{!reviewing?<div className="rowactions"><button disabled={busy||!sheet.can_save||!players.length} onClick={()=>save(false)}>{busy?'Saving…':'Save attendance'}</button><button className="outline" disabled={busy||!sheet.can_confirm||!players.length} onClick={()=>{setReviewing(true);setAcknowledged(false);setMessage('')}}>Review &amp; confirm attendance</button></div>:<div className="attendance-confirm"><h4>Review absences before confirming</h4>
   <p>{attended} attended. {players.filter(p=>!marks[p.user_id]&&p.not_going).length} marked Not Going. {absent.length} absent without Not Going.</p>
   {absent.length>0?<><p>The following players will be reported to academynewstar@gmail.com:</p><ul>{absent.map(p=><li key={p.user_id}>{p.player_name} · {p.court}</li>)}</ul></>:<p>No absence email is needed.</p>}
   <label className="attendance-ack"><input type="checkbox" checked={acknowledged} onChange={e=>setAcknowledged(e.target.checked)}/>I reviewed every court. Unticked players were absent. I understand the confirmed list is final.</label>
   <div className="rowactions"><button disabled={busy||!acknowledged} onClick={()=>save(true)}>{busy?'Confirming…':'Confirm attendance'}</button><button className="outline" disabled={busy} onClick={()=>setReviewing(false)}>Back to ticks</button></div>
  </div>}</>}
 </div>;
}
