import {useState} from 'react';
import {supabase} from './lib/supabase';

const torontoDate=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Toronto',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export default function ReportAbsence({profile,sessions}:{profile:any;sessions:any[]}){
 const [player,setPlayer]=useState(''),[location,setLocation]=useState(''),[court,setCourt]=useState(''),[date,setDate]=useState(torontoDate),[session,setSession]=useState(''),[notes,setNotes]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const locations=Array.from(new Set(sessions.map(s=>s.locations?.name).filter(Boolean))).sort() as string[];
 const matching=sessions.filter(s=>s.locations?.name===location&&s.session_date===date);
 const times=Array.from(new Set(matching.map(s=>s.start_time.slice(0,5)+'–'+s.end_time.slice(0,5))));
 const courts=Array.from(new Set(matching.map(s=>s.court).filter(Boolean))) as string[];
 const valid=!!player.trim()&&!!location.trim()&&!!court.trim()&&!!date&&!!session.trim();
 async function submit(e:React.FormEvent){
  e.preventDefault();if(!valid||busy)return;setBusy(true);setError('');setMessage('');
  try{
   const {error}=await supabase.from('absence_reports').insert({reporter_id:profile.id,player_name:player.trim(),location:location.trim(),court:court.trim(),session_date:date,session_label:session.trim(),notes:notes.trim()||null});
   if(error){setError(error.code==='23505'?'You have already reported this player for this session.':error.message);return}
   setMessage('Absence report submitted. An email has been queued to academynewstar@gmail.com for Admin review.');setPlayer('');setNotes('');
  }catch(e:any){setError(e.message||'Could not submit the report. Please try again.')}finally{setBusy(false)}
 }
 return <section className="card form"><h2>Report Absence</h2><p>Let Admin know when another player is not attending and has not marked Not Going.</p><p className="muted">Include the player and game details below. Admin receives the report and your name and email for follow-up.</p>
 <form onSubmit={submit}>
  <label>Absent player’s name<input required maxLength={120} value={player} onChange={e=>setPlayer(e.target.value)} placeholder="Player’s full name"/></label>
  <label>Location / school<input required list="absence-locations" maxLength={180} value={location} onChange={e=>{setLocation(e.target.value);setSession('');setCourt('')}} placeholder="Choose or enter the school / venue"/></label><datalist id="absence-locations">{locations.map(v=><option key={v} value={v}/>)}</datalist>
  <label>Session date<input required type="date" value={date} onChange={e=>{setDate(e.target.value);setSession('')}}/></label>
  <label>Session / time<input required list="absence-times" maxLength={120} value={session} onChange={e=>setSession(e.target.value)} placeholder="For example: Badminton 6:00–7:45 PM"/></label><datalist id="absence-times">{times.map(v=><option key={v} value={v}/>)}</datalist>
  <label>Court / team<input required list="absence-courts" maxLength={80} value={court} onChange={e=>setCourt(e.target.value)} placeholder="For example: Court 3, Team 2, or General"/></label><datalist id="absence-courts">{Array.from(new Set([...courts,'Court 1','Court 2','Court 3','Court 4','Court 5','Court 6','General / no court'])).map(v=><option key={v} value={v}/>)}</datalist>
  <label>Additional details (optional)<textarea maxLength={1500} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Anything Admin should know"/></label>
  {error&&<p className="error" role="alert">{error}</p>}{message&&<p className="success" role="status">{message}</p>}
  <button disabled={!valid||busy} type="submit">{busy?'Submitting…':'Send absence report'}</button>
 </form></section>;
}
