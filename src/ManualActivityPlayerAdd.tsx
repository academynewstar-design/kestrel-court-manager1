import {useState} from 'react';
import {supabase} from './lib/supabase';

type Player={id:string;full_name?:string;email?:string};
type Court={id:number;name:string;reserved:boolean};
export default function ManualActivityPlayerAdd({activitySessionId,players,courts,allowFullCourt,onSaved}:{activitySessionId:number;players:Player[];courts:Court[];allowFullCourt:boolean;onSaved:()=>Promise<void>}){
 const[search,setSearch]=useState('');
 const[playerId,setPlayerId]=useState('');
 const[entireCourt,setEntireCourt]=useState(false);
 const[courtId,setCourtId]=useState('');
 const[guests,setGuests]=useState('4');
 const[busy,setBusy]=useState(false);
 const[feedback,setFeedback]=useState('');
 const player=players.find(p=>p.id===playerId);
 const court=courts.find(c=>String(c.id)===courtId&&!c.reserved);
 const guestCount=Number(guests);
 const validGuests=guests.trim()!==''&&Number.isInteger(guestCount)&&guestCount>=0&&guestCount<=30;
 async function add(){
  if(busy||!player||(entireCourt&&(!allowFullCourt||!court||!validGuests)))return;
  setBusy(true);setFeedback('');
  try{
   const{data,error}=entireCourt
    ?await supabase.rpc('admin_manage_exclusive_court_booking',{p_session_id:court!.id,p_lead_name:player.full_name||player.email,p_guest_count:guestCount,p_action:'book'})
    :await supabase.rpc('admin_add_player_to_activity',{p_session_id:activitySessionId,p_user_id:playerId});
   if(error){setFeedback(error.message);return;}
   setFeedback(entireCourt?`${court!.name} reserved for ${player.full_name||player.email}${guestCount?' + '+guestCount+' guests':''}.`:data==='waitlist'?'Activity full: player added to waitlist.':'Player added to activity roster.');
   setSearch('');setPlayerId('');setCourtId('');
   await onSaved();
  }catch(error){setFeedback(error instanceof Error?error.message:'Could not save. Please try again.');}
  finally{setBusy(false);}
 }
 return <div className="notice"><h3>Add player manually</h3>
  <p className="muted">Add an approved player, or reserve an entire court for the player and their guests.</p>
  <fieldset disabled={busy} style={{border:0,padding:0,margin:0,minWidth:0}}>
   <input aria-label="Search player name or email" placeholder="Search player name or email" value={search} onChange={e=>{setSearch(e.target.value);setPlayerId('')}}/>
   <select aria-label="Select player to add" value={playerId} onChange={e=>setPlayerId(e.target.value)}><option value="">Choose player</option>{players.filter(p=>search.trim().length>=2&&((p.full_name||'').toLowerCase().includes(search.trim().toLowerCase())||(p.email||'').toLowerCase().includes(search.trim().toLowerCase()))).slice(0,30).map(p=><option key={p.id} value={p.id}>{p.full_name||p.email}{p.full_name&&p.email?' · '+p.email:''}</option>)}</select>
   {allowFullCourt&&<label>Booking type<select value={entireCourt?'court':'player'} onChange={e=>{setEntireCourt(e.target.value==='court');setFeedback('')}}><option value="player">Individual player</option><option value="court">Entire court — player + guests</option></select></label>}
   {entireCourt&&allowFullCourt?<>
    <label>Court to reserve<select value={courtId} onChange={e=>setCourtId(e.target.value)}><option value="">Choose court</option>{courts.map(c=><option key={c.id} value={c.id} disabled={c.reserved}>{c.name}{c.reserved?' — already reserved':''}</option>)}</select></label>
    <label>Number of guests (excluding the player)<input type="number" min="0" max="30" step="1" value={guests} onChange={e=>setGuests(e.target.value)}/></label>
    <p className="muted">Reserves the whole court for this activity. The group appears under Full-court group bookings. Move any existing players off the court before reserving it.</p>
   </>:<p className="muted">If the activity is full, the player joins the waitlist.</p>}
   <button disabled={!player||busy||(entireCourt&&(!court||!validGuests))} onClick={add}>{busy?'Saving…':entireCourt?'Reserve entire court':'Add Player to Activity'}</button>
  </fieldset>
  {feedback&&<p role="status">{feedback}</p>}
 </div>;
}
