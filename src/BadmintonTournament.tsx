import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import type {TournamentEvent,TournamentEntry} from './Tournaments';

type SeasonPlayer={id:string;full_name:string;can_register:boolean};
const levelName=(level?:string)=>level==='low_intermediate'?'Low Intermediate':'Intermediate';
const money=(value:number)=>new Intl.NumberFormat('en-CA',{style:'currency',currency:'CAD',maximumFractionDigits:0}).format(value);
const dateTime=(value:string)=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Toronto',weekday:'long',year:'numeric',month:'long',day:'numeric',hour:'numeric',minute:'2-digit'}).format(new Date(value));

export default function BadmintonTournamentCard({event,entry,profile,onSaved}:{
 event:TournamentEvent;entry?:TournamentEntry;profile:{id:string;full_name:string};onSaved:(text:string)=>Promise<void>;
}){
 const[players,setPlayers]=useState<SeasonPlayer[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const[allocation,setAllocation]=useState<{entry_id:number;allocation_status:string}[]>([]),[allocationLoading,setAllocationLoading]=useState(true);
 const[playerId,setPlayerId]=useState(''),[partnerId,setPartnerId]=useState(''),[level,setLevel]=useState(''),[partnerLevel,setPartnerLevel]=useState('');
 const[consent,setConsent]=useState(false),[busy,setBusy]=useState(false),[clock,setClock]=useState(Date.now());
 const open=event.status==='open'&&new Date(event.starts_at).getTime()>clock;
 const own=players.filter(p=>p.can_register),owner=entry?.user_id===profile.id;
 useEffect(()=>{let active=true;setLoading(true);supabase.rpc('get_tournament_season_players').then(({data,error})=>{if(!active)return;setPlayers(data||[]);setError(error?.message||'');setLoading(false)});return()=>{active=false}},[event.id,profile.id]);
 useEffect(()=>{let active=true;async function refresh(){const{data,error}=await supabase.rpc('get_badminton_tournament_status',{p_event_id:event.id});if(!active)return;if(error)setError(error.message);else{setAllocation(data?.entries||[]);setAllocationLoading(false)}}setAllocationLoading(true);refresh();const timer=setInterval(()=>{setClock(Date.now());refresh()},30000);return()=>{active=false;clearInterval(timer)}},[event.id,entry?.id,entry?.status,entry?.payment_status]);
 const allocationStatus=allocation.find(a=>a.entry_id===entry?.id)?.allocation_status;
 async function save(){
  if(busy||!open||!consent||!playerId||!partnerId||playerId===partnerId||!level||!partnerLevel)return;
  const player=own.find(p=>p.id===playerId),partner=players.find(p=>p.id===partnerId);
  if(!player||!partner){setError('Choose eligible Season players from the lists.');return}
  setBusy(true);setError('');
  try{
   const{error}=await supabase.from('tournament_entries').insert({event_id:event.id,user_id:profile.id,entry_kind:'team',
    team_name:(player.full_name+' / '+partner.full_name).slice(0,100),player_names:[player.full_name,partner.full_name],
    player_id:playerId,partner_id:partnerId,player_level:level,partner_level:partnerLevel,eligibility_confirmed:true,status:'registered'}).select('id').single();
   if(error)throw error;
   await onSaved('Pair added to the waitlist. Mark Paid after sending '+money(event.team_fee)+' for both players to confirm if space is available.');
  }catch(e:any){setError(e.code==='23505'?'You already have an entry. Refresh tournaments to view it.':e.message||'Unable to register. Please retry.')}finally{setBusy(false)}
 }
 async function update(values:Partial<TournamentEntry>,message:string){
  if(!entry||!owner||busy)return;setBusy(true);setError('');
  try{const{error}=await supabase.from('tournament_entries').update(values).eq('id',entry.id).eq('user_id',profile.id).select('id').single();if(error)throw error;await onSaved(message)}
  catch(e:any){setError(e.message||'Unable to update your entry. Please retry.')}finally{setBusy(false)}
 }
 return <article className="notice"><h3>{event.title}</h3><p><strong>{dateTime(event.starts_at)} (Toronto time)</strong></p>
  <p>{event.location_details}</p><p><strong>{money(event.individual_fee)} per player · {money(event.team_fee)} per pair</strong></p>
  <p><strong>Maximum 20 Intermediate players and 20 Low Intermediate players.</strong></p><p>Unpaid entries stay on the waitlist. A paid pair is confirmed when space is available for both players. Paid waitlisted pairs move up automatically when space opens.</p>
  <p>Kestrel Season players only. Doubles for Low Intermediate and Intermediate players. Both partners must be eligible Season players.</p>
  {event.status==='cancelled'?<p className="error">This tournament is cancelled.</p>:!open&&<p>Registration closed.</p>}
  {error&&<p className="error" role="alert">{error}</p>}
  {entry?<div className="notice"><h4>My badminton tournament entry</h4><p><strong>{entry.status==='cancelled'?'Cancelled':allocationLoading?'Checking spot status…':allocationStatus==='confirmed'?'Confirmed — paid':'Waitlisted'}</strong></p>
   <p>{entry.player_names[0]} · {levelName(entry.player_level)}<br/>{entry.player_names[1]} · {levelName(entry.partner_level)}</p>
   <p>{money(event.individual_fee)} each · {money(event.team_fee)} for the pair · {entry.payment_status==='paid'?'Marked paid':'Payment pending'}</p>
   {!owner&&<p>Your partner registered this pair and can manage the entry.</p>}
   {entry.status==='registered'&&entry.payment_status!=='paid'&&<p>{event.payment_email?<>Send the pair’s total of {money(event.team_fee)} to <strong>{event.payment_email}</strong>. Include both player names.</>:<>Contact Admin through Messages for payment instructions.</>}</p>}
   {open&&owner&&entry.status==='registered'&&<div className="rowactions"><button disabled={busy||entry.payment_status==='paid'} onClick={()=>{if(window.confirm('Have you sent the full '+money(event.team_fee)+' payment for both players?'))update({payment_status:'paid'},'Payment recorded. Your spot status is shown below; paid pairs are confirmed only when space is available.')}}>{entry.payment_status==='paid'?'Paid ✓':'Mark pair Paid'}</button><button className="outline" disabled={busy} onClick={()=>{if(window.confirm('Cancel the entry for both players? Contact Admin for refund questions.'))update({status:'cancelled'},'Badminton pair entry cancelled.')}}>Cancel pair entry</button></div>}
   {open&&owner&&entry.status==='cancelled'&&<button disabled={busy} onClick={()=>update({status:'registered'},'Badminton pair entry restored. Check the spot status below.')}>Rejoin tournament</button>}
  </div>:open&&<>{loading?<p role="status">Loading Season player names…</p>:!own.length?<p>Registration is reserved for approved Kestrel Season players. Contact Admin if your Season membership is missing.</p>:<div className="form">
   <label>Your name<select value={playerId} disabled={busy} onChange={e=>{setPlayerId(e.target.value);if(partnerId===e.target.value)setPartnerId('');setConsent(false)}}><option value="">Find your name</option>{own.map(p=><option key={p.id} value={p.id}>{p.full_name}</option>)}</select></label>
   <label>Your level<select value={level} disabled={busy} onChange={e=>{setLevel(e.target.value);setConsent(false)}}><option value="">Choose your level</option><option value="low_intermediate">Low Intermediate</option><option value="intermediate">Intermediate</option></select></label>
   <label>Partner name<select value={partnerId} disabled={busy||!playerId} onChange={e=>{setPartnerId(e.target.value);setConsent(false)}}><option value="">Choose your partner</option>{players.filter(p=>p.id!==playerId).map(p=><option key={p.id} value={p.id}>{p.full_name}</option>)}</select></label>
   <label>Partner level<select value={partnerLevel} disabled={busy} onChange={e=>{setPartnerLevel(e.target.value);setConsent(false)}}><option value="">Choose partner level</option><option value="low_intermediate">Low Intermediate</option><option value="intermediate">Intermediate</option></select></label>
   <label style={{display:'flex',alignItems:'flex-start',gap:8}}><input type="checkbox" checked={consent} disabled={busy} onChange={e=>setConsent(e.target.checked)} style={{width:'auto'}}/>I confirm both players are Low Intermediate or Intermediate, and my partner agrees to this entry.</label>
   <p>One registration covers both players. Each player can enter with one partner. Your pair starts on the waitlist until payment is marked and both places are available.</p><button disabled={busy||!consent||!playerId||!partnerId||!level||!partnerLevel||playerId===partnerId} onClick={save}>{busy?'Saving…':'Register badminton pair'}</button>
  </div>}</>}
 </article>;
}
