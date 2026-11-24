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
 useEffect(()=>{setStatus('loading');refresh();const timer=setInterval(refresh,30000);return()=>clearInterval(timer)},[profile.id,exempt]);
 return {status,error,refresh,preferences,approved:status==='approved'};
}

export function DropinApprovalGate({userId,approval,children}:{userId:string;approval:ReturnType<typeof useDropinAccountApproval>;children:ReactNode}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 const [sport,setSport]=useState(''),[location,setLocation]=useState('');
 const needsDetails=approval.status==='none'||approval.status==='rejected'||(approval.status==='pending'&&(!approval.preferences?.preferred_sport||!approval.preferences?.preferred_location));
 async function request(){
  if(!sport||!location)return;
  setBusy(true);setError('');
  const details={preferred_sport:sport,preferred_location:location};
  const result=(approval.status==='pending'||approval.status==='rejected')?await supabase.from('dropin_account_approvals').update({...details,status:'pending',reviewed_at:null,reviewed_by:null}).eq('user_id',userId).eq('status',approval.status).select('user_id').single():await supabase.from('dropin_account_approvals').insert({user_id:userId,...details});
  if(result.error&&result.error.code!=='23505')setError(result.error.message);
  await approval.refresh();setBusy(false);
 }
 if(approval.approved)return <>{children}</>;
 return <section className="card form"><h2>Player account approval</h2>
  <p>Admin must recognize and approve you before you can join games, waitlists or request group spots. Approval is needed once for this account, across all sports and locations.</p>
  {approval.status==='loading'?<p role="status">Checking approval…</p>:approval.status==='pending'&&!needsDetails?<p role="status">⏳ Pending Admin approval. Please wait while Admin checks your name and email.</p>:needsDetails?<>{approval.status==='rejected'&&<p>Your previous request was not approved. You may submit a new request or contact Admin below.</p>}<label>Sport<select required value={sport} onChange={e=>setSport(e.target.value)}><option value="">Choose sport</option>{['Badminton','Volleyball','Soccer','Basketball','Pickleball'].map(v=><option key={v}>{v}</option>)}</select></label><label>Preferred location<select required value={location} onChange={e=>setLocation(e.target.value)}><option value="">Choose location</option>{['Ajax','Brampton','Etobicoke','Hamilton','Kitchener','London','Mississauga','Niagara Falls','Oakville','Toronto'].map(v=><option key={v}>{v}</option>)}</select></label><button disabled={busy||!sport||!location} onClick={request}>{busy?'Submitting…':approval.status==='pending'?'Complete approval request':approval.status==='rejected'?'Submit new approval request':'Request Admin approval'}</button></>:null}
  {(error||approval.error)&&<p className="error" role="alert">{error||approval.error}</p>}
  <button className="outline" disabled={busy} onClick={approval.refresh}>Check approval</button>
  <p className="muted">Your existing bookings remain available above for payments and cancellations.</p>
 </section>;
}

export function AdminDropinAccountApprovals(){
 const [target,setTarget]=useState(''),[draft,setDraft]=useState('');
 async function send(){if(!target||!draft.trim())return;setBusy(target);setError('');try{const {data:u}=await supabase.auth.getUser();if(!u.user)throw new Error('Sign in again');const {data:s,error:e}=await supabase.from('suggestions').insert({user_id:target,note:draft.trim(),category:'Admin Message',status:'in_progress'}).select('id').single();if(e)throw e;const {error:m}=await sendConversationMessage(s.id,u.user.id,draft.trim(),null);if(m)throw m;setTarget('');setDraft('');setMessage('Private message sent.')}catch(e:any){setError(e.message)}finally{setBusy('')}}
 const [rows,setRows]=useState<any[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(''),[showReviewed,setShowReviewed]=useState(false),[message,setMessage]=useState('');
 async function load(){
  const {data,error}=await supabase.from('dropin_account_approvals').select('user_id,status,created_at,preferred_sport,preferred_location,profiles!dropin_account_approvals_user_id_fkey(full_name,email)').order('created_at',{ascending:false});
  if(error)setError(error.message);else{setRows(data||[]);setError('')}
 }
 useEffect(()=>{load();const timer=setInterval(load,30000);return()=>clearInterval(timer)},[]);
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
