import {useEffect,useState,type ReactNode} from 'react';
import {sendConversationMessage} from './MessageTools';
import {supabase} from './lib/supabase';

export function useDropinAccountApproval(profile:any){
 const [status,setStatus]=useState('loading'),[error,setError]=useState('');
 const [preferences,setPreferences]=useState<{preferred_sport:string|null;preferred_location:string|null}|null>(null);
 const exempt=false;
 async function refresh(){
  if(exempt){setStatus('approved');return}
  try{
   const {data,error}=await supabase.from('dropin_account_approvals').select('status,preferred_sport,preferred_location').eq('user_id',profile.id).maybeSingle();
   setError(error?.message||'');setPreferences(data||null);
   // Honour explicit account decisions first. Existing players approved under the
   // earlier player-access workflow must not be asked for a second approval.
   const previouslyApproved=profile.player_type_status==='approved'||profile.status==='approved';
   setStatus(error?'error':data?.status||(previouslyApproved?'approved':'none'));
  }catch(e:any){setError(e.message||'Unable to check approval. Please try again.');setStatus('error')}
 }
 useEffect(()=>{setStatus('loading');refresh();const timer=setInterval(refresh,5000);return()=>clearInterval(timer)},[profile.id,exempt]);
 return {status,error,refresh,preferences,approved:status==='approved'};
}

export function DropinApprovalGate({userId,approval,children}:{userId:string;approval:ReturnType<typeof useDropinAccountApproval>;children:ReactNode}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const [sport,setSport]=useState(''),[location,setLocation]=useState('');
 const needsDetails=approval.status==='none'||approval.status==='rejected'||(approval.status==='pending'&&(!approval.preferences?.preferred_sport||!approval.preferences?.preferred_location));
 async function request(city:string,game:string){
  if(!city||!game||busy)return;
  setBusy(true);setError('');
  try{
   const details={preferred_sport:game,preferred_location:city};
   const result=(approval.status==='pending'||approval.status==='rejected')?await supabase.from('dropin_account_approvals').update({...details,status:'pending',reviewed_at:null,reviewed_by:null}).eq('user_id',userId).eq('status',approval.status).select('user_id').single():await supabase.from('dropin_account_approvals').insert({user_id:userId,...details});
   if(result.error&&result.error.code!=='23505')throw result.error;
   await approval.refresh();
  }catch(e:any){setError(e.message||'Unable to submit request. Please retry.')}finally{setBusy(false)}
 }
 if(approval.approved)return <>{children}</>;
 const tile={aspectRatio:'1 / 1',minWidth:0,display:'flex',flexDirection:'column' as const,justifyContent:'center',alignItems:'center',gap:12,border:'1px solid #cbd5e1',borderRadius:16,padding:12,background:'var(--card, #fff)',color:'#172554'};
 return <section className="card form" style={{maxWidth:480,margin:'24px auto',textAlign:'center'}}>
 <style>{'@keyframes kestrelApprovalBounce{0%,100%{transform:translateY(0)}50%{transform:translateY(-28px)}} @media(prefers-reduced-motion:reduce){.kestrel-approval-ball{animation:none!important}}'}</style>
 {approval.status==='loading'?<p role="status">Checking approval…</p>:busy||(approval.status==='pending'&&!needsDetails)?<div role="status" style={{padding:'36px 8px'}}><div className="kestrel-approval-ball" aria-hidden="true" style={{fontSize:48,animation:'kestrelApprovalBounce 1s ease-in-out infinite'}}>🏐</div><h2>{busy?'Submitting your request…':'Your request will be approved shortly.'}</h2><p>{busy?'Please wait.':'Waiting for admin approval. This screen will update automatically.'}</p></div>:needsDetails?<><h2>Join Kestrel Sports</h2>{approval.status==='rejected'&&<p>Your previous request was not approved. You may submit a new request.</p>}<div style={{display:'grid',gridTemplateColumns:'repeat(2,minmax(0,1fr))',gap:12}}><label style={tile}><span aria-hidden="true" style={{fontSize:32}}>📍</span><strong>Choose city</strong><select aria-label="Choose city" value={location} onChange={e=>{const v=e.target.value;setLocation(v);if(v&&sport)void request(v,sport)}} style={{width:'100%',minWidth:0}}><option value="">Select city</option>{['Ajax','Brampton','Etobicoke','Hamilton','Kitchener','London','Mississauga','Niagara Falls','Oakville','Toronto'].map(v=><option key={v}>{v}</option>)}</select></label><label style={tile}><span aria-hidden="true" style={{fontSize:32}}>🏸</span><strong>Choose sport</strong><select aria-label="Choose sport" value={sport} onChange={e=>{const v=e.target.value;setSport(v);if(v&&location)void request(location,v)}} style={{width:'100%',minWidth:0}}><option value="">Select sport</option>{['Badminton','Volleyball','Soccer','Basketball','Pickleball'].map(v=><option key={v}>{v}</option>)}</select></label></div>{error&&sport&&location&&<button onClick={()=>request(location,sport)}>Retry request</button>}</>:<button onClick={approval.refresh}>Retry approval check</button>}
 {(error||approval.error)&&<p className="error" role="alert">{error||approval.error}</p>}
 </section>;
}

export function AdminDropinAccountApprovals(){
 const [target,setTarget]=useState(''),[draft,setDraft]=useState('');
 async function send(){if(!target||!draft.trim())return;setBusy(target);setError('');try{const {data:u}=await supabase.auth.getUser();if(!u.user)throw new Error('Sign in again');const {data:s,error:e}=await supabase.from('suggestions').insert({user_id:target,note:draft.trim(),category:'Admin Message',status:'in_progress'}).select('id').single();if(e)throw e;const {error:m}=await sendConversationMessage(s.id,u.user.id,draft.trim(),null);if(m)throw m;setTarget('');setDraft('');setMessage('Private message sent.')}catch(e:any){setError(e.message)}finally{setBusy('')}}
 const [rows,setRows]=useState<any[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(''),[showReviewed,setShowReviewed]=useState(false),[message,setMessage]=useState('');
 async function load(){
  const fields='user_id,status,created_at,preferred_sport,preferred_location,profiles!dropin_account_approvals_user_id_fkey(full_name,email)';
  const pending=await supabase.from('dropin_account_approvals').select(fields).eq('status','pending').order('created_at',{ascending:false});
  let data=pending.data,error=pending.error;
  if(showReviewed&&!error){
   const reviewed:any[]=[];
   for(let offset=0;;offset+=500){
    const page=await supabase.from('dropin_account_approvals').select(fields).neq('status','pending').order('created_at',{ascending:false}).order('user_id').range(offset,offset+499);
    if(page.error){error=page.error;break}
    reviewed.push(...(page.data||[]));if((page.data||[]).length<500)break;
   }
   data=[...(data||[]),...reviewed];
  }
  if(error)setError(error.message);else{setRows(data||[]);setError('')}
 }
 useEffect(()=>{load();const timer=setInterval(load,5000);return()=>clearInterval(timer)},[showReviewed]);
 async function review(userId:string,status:string){
  setBusy(userId);setError('');setMessage('');
  const {data,error}=await supabase.from('dropin_account_approvals').update({status}).eq('user_id',userId).select('user_id');
  if(error||!data?.length)setError(error?.message||'Approval was not saved. Refresh and try again.');
  else{setMessage(status==='approved'?'Player approved for Drop-in bookings.':'Drop-in access rejected.');await load()}
  setBusy('');
 }
 const visible=rows.filter(r=>showReviewed||r.status==='pending');
 return <section className="card"><div className="sectionhead"><h2>Player account approvals ({rows.filter(r=>r.status==='pending').length} pending)</h2><button className="outline" onClick={load}>Refresh approvals</button></div>
  <p>Approve only players you recognize. Check both the name and email, including possible duplicate accounts. This grants booking access; existing account bans still apply.</p>
  <label><input type="checkbox" checked={showReviewed} onChange={e=>setShowReviewed(e.target.checked)}/> Show approved and rejected accounts</label>
  {error&&<p className="error" role="alert">{error}</p>}{message&&<p role="status">{message}</p>}
  {target&&<div className="notice"><label>Private message<textarea value={draft} onChange={e=>setDraft(e.target.value)}/></label><button disabled={!!busy||!draft.trim()} onClick={send}>Send private message</button><button className="outline" onClick={()=>setTarget('')}>Cancel</button></div>}{visible.map(r=><div className="playerrow" key={r.user_id}><div><strong>{r.profiles?.full_name||'Player'}</strong><div>{r.profiles?.email}</div><div><strong>Sport:</strong> {r.preferred_sport||'Not provided'}</div><div><strong>Location:</strong> {r.preferred_location||'Not provided'}</div><div className="muted">{r.status} · Requested {new Date(r.created_at).toLocaleString('en-CA',{timeZone:'America/Toronto'})}</div></div><div className="rowactions"><button className="outline" onClick={()=>{setTarget(r.user_id);setDraft('')}}>Send Message</button>{r.status!=='approved'&&<button disabled={!!busy} onClick={()=>review(r.user_id,'approved')}>Approve Player</button>}{r.status!=='rejected'&&<button className="outline danger" disabled={!!busy} onClick={()=>review(r.user_id,'rejected')}>{r.status==='approved'?'Revoke access':'Reject Player'}</button>}</div></div>)}
  {!visible.length&&!error&&<p className="muted">No pending Drop-in account requests.</p>}
 </section>;
}
