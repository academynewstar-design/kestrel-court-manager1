import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';

type FamilyChoice={id:number,schedule_id:number,court:string,level:string,status:string,weekday:string,label:string,sport:string,location:string,city:string};
type FamilySession={id:number,date:string,start_time:string,end_time:string,court:string,sport:string,location:string,city:string,status:string,payment_status:string,not_coming:boolean};
type FamilyMember={id:string,full_name:string,relationship:string,age_years:number,name_status:string,account_status:string,choices:FamilyChoice[],sessions:FamilySession[]};
const levelName=(level:string)=>({low_intermediate:'Low Intermediate',intermediate:'Intermediate',advanced:'Advanced'}[level]||level);
const courtOptions=(schedule:any)=>schedule.sports?.name!=='badminton'?['General']:/pommeraie/i.test(schedule.locations?.name||'')&&schedule.locations?.city==='London'?['Court 2','Court 3']:['Court 1','Court 2','Court 3','Court 4','Court 5','Court 6'];

export default function FamilyManager(){
 const[members,setMembers]=useState<FamilyMember[]>([]),[selected,setSelected]=useState(''),[schedules,setSchedules]=useState<any[]>([]);
 const[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const[editing,setEditing]=useState<string|null|false>(false),[name,setName]=useState(''),[relationship,setRelationship]=useState('child'),[age,setAge]=useState(''),[consent,setConsent]=useState(false);
 const[choices,setChoices]=useState<Record<string,{court:string,player_level:string}>>({}),[paid,setPaid]=useState(false),[sport,setSport]=useState(''),[city,setCity]=useState(''),[location,setLocation]=useState('');
 async function load(){
  const {data,error}=await supabase.rpc('get_my_family');
  if(error){setError(error.message);setLoading(false);return;}
  setMembers(data||[]);setLoading(false);
 }
 useEffect(()=>{load();supabase.from('recurring_schedules').select('id,weekday,schedule_label,sports(name),locations(name,city)').eq('active',true).order('schedule_label').then(({data,error})=>{if(error)setError(error.message);else setSchedules(data||[])});},[]);
 const member=members.find(m=>m.id===selected);
 function selectMember(id:string){setSelected(id);setChoices({});setPaid(false);setMessage('');setError('');setSport('');setCity('');setLocation('');setEditing(false);}
 function editMember(m?:FamilyMember){setEditing(m?.id||null);setName(m?.full_name||'');setRelationship(m?.relationship||'child');setAge(m?String(m.age_years):'');setConsent(false);setError('');setMessage('');}
 async function saveMember(){
  if(busy)return;setBusy(true);setError('');setMessage('');
  try{
   const {data,error}=await supabase.rpc('save_my_family_member',{p_member_id:editing||null,p_name:name.trim(),p_relationship:relationship,p_age:Number(age),p_consent:consent});
   if(error)throw error;
   await load();selectMember(String(data));setMessage('Family member saved. Choose their own Season sessions below.');
  }catch(e:any){setError(e.message||'Unable to save family member. Please try again.');}finally{setBusy(false);}
 }
 async function submitChoices(){
  if(!member||busy)return;setBusy(true);setError('');setMessage('');
  try{
   const {error}=await supabase.rpc('save_my_family_season_choices',{p_member_id:member.id,p_choices:Object.entries(choices).map(([id,c])=>({recurring_schedule_id:Number(id),...c,season_paid:paid}))});
   if(error)throw error;
   setChoices({});setPaid(false);setMessage('Season request sent for Admin approval. This family member will appear on the roster after approval.');await load();
  }catch(e:any){setError(e.message||'Unable to submit. Please try again.');}finally{setBusy(false);}
 }
 async function attendance(s:FamilySession){
  if(!member||busy)return;
  const away=s.not_coming||['cancelled','removed','not_going'].includes(s.status);
  if(!away&&!window.confirm('Mark '+member.full_name+' as Not attending on '+s.date+'? Their spot may go to the waitlist.'))return;
  setBusy(true);setError('');setMessage('');
  try{
   const{data,error}=await supabase.rpc('set_my_family_attendance',{p_member_id:member.id,p_session_id:s.id,p_not_coming:!away});
   if(error)throw error;
   setMessage(data==='full'?'This session is now full. Their spot could not be restored.':data==='not_attending'?member.full_name+' is marked Not attending.':member.full_name+' is attending again.');await load();
  }catch(e:any){setError(e.message||'Unable to update attendance.');}finally{setBusy(false);}
 }
 async function withdraw(c:FamilyChoice){
  if(!member||busy||!window.confirm('Withdraw this pending request for '+member.full_name+'?'))return;
  setBusy(true);setError('');setMessage('');
  try{const{error}=await supabase.rpc('withdraw_my_family_choice',{p_member_id:member.id,p_request_id:c.id});if(error)throw error;setMessage('Pending request withdrawn. You can choose another session.');await load();}catch(e:any){setError(e.message);}finally{setBusy(false);}
 }
 const sports=[...new Set(schedules.map(s=>s.sports?.name).filter(Boolean))].sort() as string[];
 const bySport=schedules.filter(s=>!sport||s.sports?.name===sport);
 const cities=[...new Set(bySport.map(s=>s.locations?.city).filter(Boolean))].sort() as string[];
 const byCity=bySport.filter(s=>!city||s.locations?.city===city);
 const locations=[...new Set(byCity.map(s=>s.locations?.name).filter(Boolean))].sort() as string[];
 const visible=byCity.filter(s=>(!location||s.locations?.name===location)&&!member?.choices.some(c=>c.schedule_id===s.id&&c.status==='approved'));
 return <section className="card family-manager">
  <div className="sectionhead"><div><h2>My Family</h2><p>Register children or other family members using your account. Each person has their own sessions, court, attendance and roster spot.</p></div><div className="rowactions"><button disabled={busy} onClick={()=>editMember()}>Add family member</button><button className="outline" disabled={busy} onClick={load}>Refresh family</button></div></div>
  {loading&&<p role="status">Loading family…</p>}
  {error&&<p className="error" role="alert">{error}</p>}{message&&<p className="success" role="status">{message}</p>}
  {editing!==false&&<form className="family-form" onSubmit={e=>{e.preventDefault();saveMember();}}>
   <h3>{editing?'Edit family member':'Add a family member'}</h3>
   <div className="grid"><label>Real first and last name<input required maxLength={80} autoComplete="off" value={name} onChange={e=>setName(e.target.value)}/></label>
   <label>Relationship<select value={relationship} onChange={e=>setRelationship(e.target.value)}><option value="child">Child</option><option value="spouse">Spouse / Partner</option><option value="other">Other family member</option></select></label>
   <label>Age in years<input required type="number" min={1} max={120} step={1} value={age} onChange={e=>setAge(e.target.value)}/></label></div>
   <label className="family-check"><input type="checkbox" checked={consent} onChange={e=>setConsent(e.target.checked)}/> I am this child's parent/legal guardian, or I have this family member's permission to register and manage their participation.</label>
   <p className="muted">No separate email or Google account is needed. Admin will check age eligibility before approving a session.</p>
   <div className="rowactions"><button disabled={busy||!name.trim()||!consent||!Number.isInteger(Number(age))||Number(age)<1||Number(age)>120}>{busy?'Saving…':'Save family member'}</button><button type="button" className="outline" disabled={busy} onClick={()=>setEditing(false)}>Cancel</button></div>
  </form>}
  {!loading&&!members.length&&editing===false&&<p className="muted">No family members added yet. Tap Add family member to get started.</p>}
  {members.length>0&&<label>Manage family member<select value={selected} disabled={busy} onChange={e=>selectMember(e.target.value)}><option value="">Choose a family member</option>{members.map(m=><option key={m.id} value={m.id}>{m.full_name}</option>)}</select></label>}
  {member&&<>
   <div className="notice"><h3>{member.full_name}</h3><p>{member.relationship==='child'?'Child':member.relationship==='spouse'?'Spouse / Partner':'Family member'} · Age {member.age_years}</p><button className="outline" disabled={busy} onClick={()=>editMember(member)}>Edit details</button>
   {member.account_status!=='approved'&&<p className="error">This family profile is inactive. Please contact Admin.</p>}
   {member.name_status!=='approved'&&<p className="notice">{member.name_status==='pending'?'This name needs Admin review. You can submit session choices while you wait.':'Please correct the real name, or contact Admin for help.'}</p>}</div>
   <h3>{member.full_name}'s Season requests</h3>
   {member.choices.map(c=><article className="session" key={c.id}><div><strong>{c.sport} · {c.location}</strong><div>{c.city} · {c.weekday} · {c.label} · {c.court}</div><div>{levelName(c.level)} · <strong>{c.status==='rejected'?'Withdrawn / Not approved':c.status==='approved'?'Approved':'Pending Admin approval'}</strong></div></div>{c.status==='pending'&&<button className="outline" disabled={busy} onClick={()=>withdraw(c)}>Withdraw request</button>}</article>)}
   {!member.choices.length&&<p className="muted">No Season requests yet. Choose their sessions below.</p>}
   <h3>Choose Season sessions for {member.full_name}</h3><p className="muted">Choose this person's own sport, location, day/time, court and level. You can select several sessions. Each request needs Admin approval.</p>
   <div className="grid"><label>Sport<select value={sport} onChange={e=>{setSport(e.target.value);setCity('');setLocation('');}}><option value="">All sports</option>{sports.map(s=><option key={s}>{s}</option>)}</select></label><label>City<select value={city} onChange={e=>{setCity(e.target.value);setLocation('');}}><option value="">All cities</option>{cities.map(s=><option key={s}>{s}</option>)}</select></label><label>Location<select value={location} onChange={e=>setLocation(e.target.value)}><option value="">All locations</option>{locations.map(s=><option key={s}>{s}</option>)}</select></label></div>
   <p className="muted">{Object.keys(choices).length} selected (including any hidden by filters).</p>
   {visible.map(s=>{const id=String(s.id),choice=choices[id];return <article className="session" key={id}><div><strong>{s.weekday} · {s.sports?.name}</strong><div>{s.locations?.city} · {s.locations?.name}</div><div>{s.schedule_label}</div></div><div className="rowactions">{choice&&<><label>Court<select value={choice.court} disabled={busy} onChange={e=>setChoices(v=>({...v,[id]:{...v[id],court:e.target.value}}))}>{courtOptions(s).map(c=><option key={c}>{c}</option>)}</select></label><label>Player level<select value={choice.player_level} disabled={busy} onChange={e=>setChoices(v=>({...v,[id]:{...v[id],player_level:e.target.value}}))}><option value="">Choose level</option><option value="low_intermediate">Low Intermediate</option><option value="intermediate">Intermediate</option><option value="advanced">Advanced</option></select></label></>}<button className={choice?'outline':''} disabled={busy||member.account_status!=='approved'} onClick={()=>setChoices(v=>{const n={...v};if(n[id])delete n[id];else n[id]={court:courtOptions(s)[0],player_level:''};return n;})}>{choice?'Remove':'Choose'}</button></div></article>;})}
   {!visible.length&&<p className="muted">No additional active schedules match these filters.</p>}
   <label className="family-check"><input type="checkbox" checked={paid} onChange={e=>setPaid(e.target.checked)}/> I confirm Season payment has been made for {member.full_name} for these sessions.</label>
   <button disabled={busy||!paid||!Object.keys(choices).length||Object.values(choices).some(c=>!c.player_level)||member.account_status!=='approved'} onClick={submitChoices}>{busy?'Submitting…':'Submit family Season request'}</button>
   <h3>{member.full_name}'s upcoming games</h3><p className="muted">Attendance changes apply only to this family member. A released spot is subject to availability when rejoining.</p>
   {member.sessions.map(s=>{const away=s.not_coming||['cancelled','removed','not_going'].includes(s.status);return <article className="session" key={s.id}><div><strong>{s.date} · {s.sport} · {s.location}</strong><div>{s.start_time.slice(0,5)}–{s.end_time.slice(0,5)} · {s.court}</div><div className={away?'muted':'success'}>{away?'Not attending':'Attending'} · Season payment: {s.payment_status==='paid'?'Recorded':s.payment_status||'Contact Admin'}</div></div><button className="outline" disabled={busy||member.account_status!=='approved'} onClick={()=>attendance(s)}>{away?'Going again':'Not attending'}</button></article>;})}
   {!member.sessions.length&&<p className="muted">Upcoming games appear after Admin approves their Season request.</p>}
  </>}
 </section>;
}

export function AdminFamilyApprovals({onReviewed}:{onReviewed:()=>void}){
 const[requests,setRequests]=useState<any[]>([]),[eligible,setEligible]=useState<Record<string,boolean>>({}),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 async function load(){const{data,error}=await supabase.rpc('get_pending_family_season_requests');if(error)setError(error.message);else setRequests(data||[]);}
 useEffect(()=>{load();const timer=setInterval(load,60000);return()=>clearInterval(timer);},[]);
 async function review(id:number,approve:boolean){if(busy)return;setBusy(true);setError('');setMessage('');try{const{error}=await supabase.rpc('admin_review_family_season_request',{p_request_id:id,p_approve:approve,p_eligible:!!eligible[id]});if(error)throw error;setMessage(approve?'Family Season request approved. Their own roster spots have been created.':'Family Season request rejected.');await load();onReviewed();}catch(e:any){setError(e.message);}finally{setBusy(false);}}
 if(!requests.length&&!error&&!message)return null;
 return <section className="card"><div className="sectionhead"><h2>Family Season approvals ({requests.length})</h2><button className="outline" disabled={busy} onClick={load}>Refresh</button></div>{error&&<p className="error" role="alert">{error}</p>}{message&&<p className="success" role="status">{message}</p>}{requests.map(r=><article className="notice" key={r.id}><h3>{r.member_name} · Age {r.age_years}</h3><p>Managed by {r.owner_name} · {r.owner_email}</p><p>{r.sport} · {r.city} · {r.location}<br/>{r.weekday} · {r.label} · {r.court} · {levelName(r.level)}</p>{r.name_status!=='approved'&&<p className="error">Real-name review required. Use Names awaiting review before approving this request.</p>}<label className="family-check"><input type="checkbox" checked={!!eligible[r.id]} disabled={busy} onChange={e=>setEligible(v=>({...v,[r.id]:e.target.checked}))}/> I checked that this person meets this activity's age/participation rules and verified their Season payment.</label><div className="rowactions"><button disabled={busy||!eligible[r.id]||r.name_status!=='approved'} onClick={()=>review(r.id,true)}>Approve family request</button><button className="outline" disabled={busy} onClick={()=>review(r.id,false)}>Reject family request</button></div></article>)}</section>;
}
