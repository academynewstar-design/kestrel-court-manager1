import {useRef,useState} from 'react';
import {supabase} from './lib/supabase';
export default function RemoveSeasonSession({scheduleId,label,disabled,onRemoved}:{scheduleId:number;label:string;disabled?:boolean;onRemoved:()=>void|Promise<void>}){
 const[busy,setBusy]=useState(false),[error,setError]=useState('');const working=useRef(false);
 async function remove(){
  if(working.current||!window.confirm('Remove '+label+' from your Season sessions? This releases your Season place for all upcoming games in this schedule. Returning requires Admin approval. To miss only one date, use Not Going instead.'))return;
  working.current=true;setBusy(true);setError('');
  try{const{error}=await supabase.rpc('remove_my_season_choice',{p_recurring_schedule_id:scheduleId});if(error)throw error;await onRemoved()}
  catch(e:any){setError(e?.message||'Could not remove your Season session. Please try again.')}
  finally{working.current=false;setBusy(false)}
 }
 return <><button className="outline danger" disabled={disabled||busy} onClick={remove}>{busy?'Removing…':'Remove Season session'}</button>{error&&<p className="error" role="alert">{error}</p>}</>;
}
