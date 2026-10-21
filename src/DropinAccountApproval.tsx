import {useEffect,useState,type ReactNode} from 'react';
import {supabase} from './lib/supabase';

export function useDropinAccountApproval(profile:any){
 const [status,setStatus]=useState('loading'),[error,setError]=useState('');
 const exempt=profile.player_type==='permanent'&&profile.player_type_status==='approved';
 async function refresh(){
  if(exempt){setStatus('approved');return}
  try{
   const {data,error}=await supabase.from('dropin_account_approvals').select('status').eq('user_id',profile.id).maybeSingle();
   setError(error?.message||'');setStatus(error?'error':data?.status||'none');
  }catch(e:any){setError(e.message||'Unable to check approval. Please try again.');setStatus('error')}
 }
 useEffect(()=>{setStatus('loading');refresh();const timer=setInterval(refresh,30000);return()=>clearInterval(timer)},[profile.id,exempt]);
 return {status,error,refresh,approved:exempt||status==='approved'};
}

export function DropinApprovalGate({userId,approval,children}:{userId:string;approval:ReturnType<typeof useDropinAccountApproval>;children:ReactNode}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 async function request(){
  setBusy(true);setError('');
  const result=await supabase.from('dropin_account_approvals').insert({user_id:userId});
  if(result.error&&result.error.code!=='23505')setError(result.error.message);
  await approval.refresh();setBusy(false);
 }
 if(approval.approved)return <>{children}</>;
 return <section className="card form"><h2>Drop-in account approval</h2>
  <p>Admin must recognize and approve you before you can join games, waitlists or request group spots. Approval is needed once for this account, across all sports and locations.</p>
  {approval.status==='loading'?<p role="status">Checking approval…</p>:approval.status==='pending'?<p role="status">⏳ Pending Admin approval. Please wait while Admin checks your name and email.</p>:approval.status==='rejected'?<p role="status">Your Drop-in request was not approved. Use Messages to contact Admin.</p>:approval.status==='none'?<button disabled={busy} onClick={request}>{busy?'Submitting…':'Request Admin approval'}</button>:null}
  {(error||approval.error)&&<p className="error" role="alert">{error||approval.error}</p>}
  <button className="outline" disabled={busy} onClick={approval.refresh}>Check approval</button>
  <p className="muted">Your existing bookings remain available above for payments and cancellations.</p>
 </section>;
}

export function AdminDropinAccountApprovals(){
 const [rows,setRows]=useState<any[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(''),[showReviewed,setShowReviewed]=useState(false),[message,setMessage]=useState('');
 async function load(){
  const {data,error}=await supabase.from('dropin_account_approvals').select('user_id,status,created_at,profiles!dropin_account_approvals_user_id_fkey(full_name,email)').order('created_at',{ascending:false});
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
 return <section className="card"><div className="sectionhead"><h2>Drop-in account approvals ({rows.filter(r=>r.status==='pending').length} pending)</h2><button className="outline" onClick={load}>Refresh approvals</button></div>
  <p>Approve only players you recognize. Check both the name and email, including possible duplicate accounts. This grants booking access; existing account bans still apply.</p>
  <label><input type="checkbox" checked={showReviewed} onChange={e=>setShowReviewed(e.target.checked)}/> Show approved and rejected accounts</label>
  {error&&<p className="error" role="alert">{error}</p>}{message&&<p role="status">{message}</p>}
  {visible.map(r=><div className="playerrow" key={r.user_id}><div><strong>{r.profiles?.full_name||'Player'}</strong><div>{r.profiles?.email}</div><div className="muted">{r.status} · Requested {new Date(r.created_at).toLocaleString('en-CA',{timeZone:'America/Toronto'})}</div></div><div className="rowactions">{r.status!=='approved'&&<button disabled={!!busy} onClick={()=>review(r.user_id,'approved')}>Approve Drop-in</button>}{r.status!=='rejected'&&<button className="outline danger" disabled={!!busy} onClick={()=>review(r.user_id,'rejected')}>{r.status==='approved'?'Revoke access':'Reject Drop-in'}</button>}</div></div>)}
  {!visible.length&&!error&&<p className="muted">No pending Drop-in account requests.</p>}
 </section>;
}
