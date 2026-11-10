import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
type Session={id:number;session_date:string;start_time:string};
type Result={session_id:number;blue_score:number;red_score:number};
type Goal={session_id:number;player_id:string;team:'Blue'|'Red';goals:number};
type Player={id:string;full_name:string};
export default function SavemaxSoccerStats(){
 const [sessions,setSessions]=useState<Session[]>([]);
 const [results,setResults]=useState<Result[]>([]);
 const [goals,setGoals]=useState<Goal[]>([]);
 const [players,setPlayers]=useState<Player[]>([]);
 const [selected,setSelected]=useState('');
 const [blue,setBlue]=useState(0),[red,setRed]=useState(0);
 const [player,setPlayer]=useState(''),[team,setTeam]=useState<'Blue'|'Red'>('Blue'),[count,setCount]=useState(1);
 const [editable,setEditable]=useState(false),[busy,setBusy]=useState(false),[msg,setMsg]=useState('');
 const [tab,setTab]=useState<'results'|'strikers'>('results');
 async function load(){
  const [s,r,g,p,u]=await Promise.all([
   supabase.from('sessions').select('id,session_date,start_time').eq('sport_id',4).eq('location_id',18).order('session_date',{ascending:false}).limit(120),
   supabase.from('savemax_match_results').select('session_id,blue_score,red_score'),
   supabase.from('savemax_match_goals').select('session_id,player_id,team,goals'),
   supabase.from('profiles').select('id,full_name').order('full_name').limit(1000),
   supabase.auth.getUser()
  ]);
  if(s.error||r.error||g.error||p.error){setMsg(s.error?.message||r.error?.message||g.error?.message||p.error?.message||'Unable to load scores');return}
  setSessions((s.data||[]) as Session[]);setResults((r.data||[]) as Result[]);setGoals((g.data||[]) as Goal[]);setPlayers((p.data||[]) as Player[]);
  setSelected(prev=>prev||String(s.data?.[0]?.id||''));
  const uid=u.data.user?.id;
  const profile=(p.data||[]).find(x=>x.id===uid);
  // The database enforces this permission again for every write.
  const {data:role}=await supabase.from('profiles').select('is_admin').eq('id',uid||'00000000-0000-0000-0000-000000000000').maybeSingle();
  setEditable(!!role?.is_admin||uid==='fb86161a-203b-4638-ab7d-265b7f75b954'||uid==='bd4e9abe-ef78-4917-92b1-f63060b37256');
  void profile;
 }
 useEffect(()=>{void load()},[]);
 useEffect(()=>{const r=results.find(x=>String(x.session_id)===selected);setBlue(r?.blue_score??0);setRed(r?.red_score??0)},[selected,results]);
 const sessionGoals=goals.filter(g=>String(g.session_id)===selected);
 const sums=goals.reduce((acc,g)=>{const entry=acc.get(g.player_id)||{goals:0,matches:0};entry.goals+=g.goals;entry.matches++;acc.set(g.player_id,entry);return acc},new Map<string,{goals:number;matches:number}>());
 const leaders=[...sums.entries()].map(([id,stats])=>({name:players.find(p=>p.id===id)?.full_name||'Player',...stats})).sort((a,b)=>b.goals-a.goals);
 async function saveScore(){
  if(!selected)return;setBusy(true);setMsg('');
  const {data:u}=await supabase.auth.getUser();
  const {error}=await supabase.from('savemax_match_results').upsert({session_id:Number(selected),blue_score:blue,red_score:red,updated_by:u.user?.id},{onConflict:'session_id'});
  setMsg(error?.message||'Match score saved');setBusy(false);if(!error)await load();
 }
 async function saveGoals(){
  if(!selected||!player)return;setBusy(true);setMsg('');
  const {error}=await supabase.from('savemax_match_goals').upsert({session_id:Number(selected),player_id:player,team,goals:count},{onConflict:'session_id,player_id'});
  setMsg(error?.message||'Goals saved');setBusy(false);if(!error)await load();
 }
 async function removeGoals(g:Goal){
  setBusy(true);const {error}=await supabase.from('savemax_match_goals').delete().eq('session_id',g.session_id).eq('player_id',g.player_id);
  setMsg(error?.message||'Goals removed');setBusy(false);if(!error)await load();
 }
 return <section className="card"><h2>⚽ Savemax Soccer — Scores & Statistics</h2>
 <div className="tabs"><button className={tab==='results'?'active':''} onClick={()=>setTab('results')}>Match Results</button><button className={tab==='strikers'?'active':''} onClick={()=>setTab('strikers')}>🏆 Top Scorers</button></div>
 {msg&&<p role="status">{msg}</p>}
 {tab==='strikers'?<><h3>Best Striker Leaderboard</h3><p className="muted">Goals recorded across Savemax sessions.</p><table><thead><tr><th>Rank</th><th>Player</th><th>Goals</th><th>Scoring sessions</th></tr></thead><tbody>{leaders.map((p,i)=><tr key={p.name+i}><td>{i+1}</td><td>{p.name}</td><td>{p.goals}</td><td>{p.matches}</td></tr>)}</tbody></table>{!leaders.length&&<p>No goals recorded yet.</p>}</>:<>
 <label>Session date<select value={selected} onChange={e=>setSelected(e.target.value)}>{sessions.map(s=><option key={s.id} value={s.id}>{s.session_date} · {s.start_time}</option>)}</select></label>
 <div style={{display:'flex',gap:12,flexWrap:'wrap'}}><strong>🔵 Blue: {results.find(r=>String(r.session_id)===selected)?.blue_score??'—'}</strong><strong>🔴 Red: {results.find(r=>String(r.session_id)===selected)?.red_score??'—'}</strong></div>
 <h3>Goalscorers</h3>{sessionGoals.map(g=><div key={g.player_id} style={{display:'flex',justifyContent:'space-between',gap:8,marginBottom:8}}><span>{players.find(p=>p.id===g.player_id)?.full_name||'Player'} · {g.team} · {g.goals} goal(s)</span>{editable&&<button className="outline" disabled={busy} onClick={()=>removeGoals(g)}>Remove</button>}</div>)}
 {!sessionGoals.length&&<p className="muted">No goals recorded for this session.</p>}
 {editable&&<><h3>Captain / Admin Score Entry</h3><p className="muted">Team Blue: Peter v · Team Red: Johnny Licta</p><div style={{display:'flex',gap:12,flexWrap:'wrap'}}><label>Blue score<input type="number" min="0" max="99" value={blue} onChange={e=>setBlue(Math.max(0,Math.min(99,Number(e.target.value)||0)))}/></label><label>Red score<input type="number" min="0" max="99" value={red} onChange={e=>setRed(Math.max(0,Math.min(99,Number(e.target.value)||0)))}/></label></div><button disabled={busy||!selected} onClick={saveScore}>Save match score</button>
 <h4>Record player goals</h4><label>Player<select value={player} onChange={e=>setPlayer(e.target.value)}><option value="">Select player</option>{players.map(p=><option key={p.id} value={p.id}>{p.full_name}</option>)}</select></label><label>Team<select value={team} onChange={e=>setTeam(e.target.value as 'Blue'|'Red')}><option>Blue</option><option>Red</option></select></label><label>Goals<input type="number" min="1" max="99" value={count} onChange={e=>setCount(Math.max(1,Math.min(99,Number(e.target.value)||1)))}/></label><button disabled={busy||!selected||!player} onClick={saveGoals}>Save player goals</button></>}
 {!editable&&<p className="muted">Only captains Peter v and Johnny Licta, and administrators, can enter or edit scores.</p>}
 </>}
 </section>
}