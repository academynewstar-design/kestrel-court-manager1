import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';

type Game={id:string;session_date:string;start_time:string;end_time:string;capacity:number|null;status:string;dropin_enabled:boolean;locations:{name:string;city:string}|null;sports:{name:string}|null};
type Player={player_name:string;is_me:boolean;party_size:number};
export default function SavemaxSoccerRoster(){
 const [games,setGames]=useState<Game[]>([]);
 const [selected,setSelected]=useState('');
 const [players,setPlayers]=useState<Player[]>([]);
 const [error,setError]=useState('');
 const [loading,setLoading]=useState(true);
 useEffect(()=>{let active=true;(async()=>{
  const {data,error}=await supabase.from('sessions').select('id,session_date,start_time,end_time,capacity,status,dropin_enabled,locations(name,city),sports(name)').eq('sport_id',4).eq('location_id',18).eq('status','open').eq('dropin_enabled',true).gt('capacity',0).gte('session_date',new Intl.DateTimeFormat('en-CA',{timeZone:'America/Toronto',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())).lte('session_date','2027-03-31').order('session_date',{ascending:true}).limit(100);
  if(!active)return;
  if(error){setError(error.message);setLoading(false);return}
  const normalized:Game[]=(data||[]).map(s=>({...s,locations:Array.isArray(s.locations)?s.locations[0]??null:s.locations,sports:Array.isArray(s.sports)?s.sports[0]??null:s.sports}));
  const matching=normalized.filter(s=>s.sports?.name?.toLowerCase()==='soccer'&&/savemax|save max/i.test(s.locations?.name||'')&&s.status==='open'&&s.dropin_enabled&&Number(s.capacity)>0).sort((a,b)=>a.session_date.localeCompare(b.session_date));
  setGames(matching);
  setSelected(prev=>matching.some(g=>g.id===prev)?prev:matching[0]?.id||'');
  setLoading(false);
 })();return()=>{active=false}},[]);
 useEffect(()=>{if(!selected)return;let active=true;setLoading(true);setError('');supabase.rpc('get_grouped_dropin_roster',{p_session_id:selected}).then(({data,error}:any)=>{if(!active)return;setPlayers(data||[]);setError(error?.message||'');setLoading(false)});return()=>{active=false}},[selected]);
 const game=games.find(g=>g.id===selected);
 const count=players.reduce((n,p)=>n+Number(p.party_size||1),0);
 return <section className="card"><h2>⚽ Savemax Soccer Roster</h2><p className="muted">Select a game date to see the registered players. The list updates from live bookings.</p>
 {error&&<p className="error" role="alert">{error}</p>}
 {games.length>0?<><label htmlFor="savemax-roster-date">Game date</label><select id="savemax-roster-date" value={selected} onChange={e=>setSelected(e.target.value)}>{games.map(g=><option key={g.id} value={g.id}>{g.session_date} · {g.start_time}–{g.end_time}</option>)}</select>
 {game&&<p><strong>{game.session_date}</strong> · {game.start_time}–{game.end_time} · {count} listed{game.capacity!=null?' · Capacity '+game.capacity:''}</p>}
 {loading?<p role="status">Loading roster…</p>:players.length?<div>{players.map((p,i)=><div className="playerrow" key={i}><span>{p.player_name}{p.is_me?' (You)':''}{Number(p.party_size||1)>1?' · '+p.party_size+' people':''}</span></div>)}</div>:!error&&<p>No registered players listed for this date.</p>}</>:!loading&&!error&&<p>No Savemax soccer sessions found.</p>}
 </section>;
}
