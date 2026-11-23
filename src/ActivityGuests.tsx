import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';

type Guest={id:number;registration_id:number;guest_name:string;payment_status:string};
export default function ActivityGuests({registrationId,onChanged,compact=false}:{registrationId:number;onChanged?:()=>void|Promise<void>;compact?:boolean}){
 const [guests,setGuests]=useState<Guest[]>([]);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [name,setName]=useState('');
 const [expanded,setExpanded]=useState(false);
 async function load(){const {data,error}=await supabase.from('activity_registration_guests').select('id,registration_id,guest_name,payment_status').eq('registration_id',registrationId).order('id');if(error)setError(error.message);else setGuests(data||[])}
 useEffect(()=>{void load()},[registrationId]);
 async function act(action:'add'|'remove'|'paid'|'unpaid',guestId?:number){
  if(busy)return;setBusy(true);setError('');
  const {error}=await supabase.rpc('manage_activity_guest',{p_registration_id:registrationId,p_action:action,p_guest_id:guestId??null,p_guest_name:action==='add'?name.trim()||'Guest':null});
  if(error)setError(error.message);else{setName('');await load();await onChanged?.();setExpanded(true)}
  setBusy(false);
 }
 return <div className="activity-guests" style={{marginTop:6,fontSize:compact?12:14}}>
  <div style={{display:'flex',flexWrap:'wrap',gap:5,alignItems:'center'}}>
   <button type="button" className="outline" aria-expanded={expanded} onClick={()=>setExpanded(v=>!v)}>+ Add Guest{guests.length?' ('+guests.length+')':''}</button>
   {expanded&&<><input aria-label="Guest name" placeholder="Guest name (optional)" style={{width:compact?125:155,padding:5}} value={name} disabled={busy} onChange={e=>setName(e.target.value)}/>
   <button type="button" disabled={busy} onClick={()=>act('add')}>Save Guest</button></>}
  </div>
  {guests.map((g,i)=><div key={g.id} style={{display:'flex',flexWrap:'wrap',gap:5,alignItems:'center',marginTop:5}}>
   <span>↳ {g.guest_name==='Guest'?'Guest '+(i+1):g.guest_name}</span>
   <button type="button" disabled={busy} className={g.payment_status==='paid'?'success':'outline'} onClick={()=>act(g.payment_status==='paid'?'unpaid':'paid',g.id)}>{g.payment_status==='paid'?'Paid ✓':'Unpaid'}</button>
   <button type="button" className="outline" disabled={busy} onClick={()=>act('remove',g.id)}>− Remove</button>
  </div>)}
  {error&&<small role="alert" style={{color:'#b42318'}}>{error}</small>}
 </div>;
}
