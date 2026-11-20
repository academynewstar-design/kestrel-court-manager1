import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';

type TrafficRow = { day: string | null; page_name: string; page_views: number; visits: number; unique_visitors: number; guest_page_views: number };
export default function WebsiteTrafficReport({start,end,refresh}:{start:string;end:string;refresh:number}) {
 const [rows,setRows]=useState<TrafficRow[]>([]);
 const [identified,setIdentified]=useState<{visited_at:string;visitor_name:string;visitor_email:string;page_name:string}[]>([]);
 const [error,setError]=useState('');
 const [loading,setLoading]=useState(true);
 useEffect(()=>{
  let active=true;
  async function load(){
   if(start>end){setError('Invalid date range');setRows([]);setLoading(false);return;}
   setLoading(true);
   const {data,error}=await supabase.rpc('admin_website_traffic_report',{p_start_date:start,p_end_date:end});
   if(!active)return;
   setRows((data||[]) as TrafficRow[]);setError(error?.message||'');const people=await supabase.rpc('admin_website_identified_visits',{p_start_date:start,p_end_date:end});if(!active)return;setIdentified(people.data||[]);if(people.error)setError(people.error.message);setLoading(false);
  }
  void load();const timer=setInterval(()=>void load(),60000);
  return()=>{active=false;clearInterval(timer)};
 },[start,end,refresh]);
 const uniquePeople=Object.values(identified.reduce<Record<string,{name:string;email:string;first:string;last:string;views:number}>>((acc,visit)=>{
  const email=(visit.visitor_email||'').trim().toLowerCase();
  const key=email||visit.visitor_name.trim().toLowerCase();
  if(!key)return acc;
  const existing=acc[key];
  if(!existing){acc[key]={name:visit.visitor_name,email:visit.visitor_email,first:visit.visited_at,last:visit.visited_at,views:1};}
  else{existing.views++;if(visit.visited_at<existing.first)existing.first=visit.visited_at;if(visit.visited_at>existing.last)existing.last=visit.visited_at;}
  return acc;
 },{})).sort((a,b)=>b.last.localeCompare(a.last));
 const localTime=(value:string)=>new Date(value).toLocaleString('en-CA',{timeZone:'America/Toronto'});
 const total=rows.find(r=>r.page_name==='ALL');
 const details=rows.filter(r=>r.page_name!=='ALL');
 const csv=()=>{
  const lines=[['Date','Page','Page views','Visits','Unique visitors','Guest page views'],...rows.map(r=>[r.day||'TOTAL',r.page_name,r.page_views,r.visits,r.unique_visitors,r.guest_page_views])];
  const blob=new Blob([lines.map(row=>row.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(',')).join('\r\n')],{type:'text/csv'});
  const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='kestrel-website-traffic.csv';a.click();URL.revokeObjectURL(url);
 };
 return <section style={{marginTop:24}}>
  <div className="sectionhead"><h3>Website Visitors</h3><button className="outline" disabled={!rows.length} onClick={csv}>Export CSV</button></div>
  <p className="muted">Includes anonymous visitors. Counts start when tracking was installed; unique visitors are approximate and do not identify individuals. Toronto local dates.</p>
  {error&&<p className="error">{error}</p>}
  {loading?<p>Loading website traffic…</p>:<><div className="grid2">
   <p><strong>{Number(total?.page_views||0).toLocaleString()}</strong> page views</p>
   <p><strong>{Number(total?.visits||0).toLocaleString()}</strong> visits</p>
   <p><strong>{Number(total?.unique_visitors||0).toLocaleString()}</strong> unique visitors</p>
   <p><strong>{Number(total?.guest_page_views||0).toLocaleString()}</strong> anonymous page views</p>
  </div><div style={{overflowX:'auto'}}><table><thead><tr><th>Date</th><th>Page</th><th>Views</th><th>Visits</th><th>Unique</th><th>Guest views</th></tr></thead><tbody>{details.map((r,i)=><tr key={i}><td>{r.day}</td><td>{r.page_name}</td><td>{r.page_views}</td><td>{r.visits}</td><td>{r.unique_visitors}</td><td>{r.guest_page_views}</td></tr>)}</tbody></table></div>
  {!details.length&&<p className="muted">No tracked visits for these dates.</p>}<h4>Unique signed-in visitors ({uniquePeople.length})</h4><p className="muted">One row per signed-in person, whether or not they RSVP or join a season. Visits and first/last seen reflect the latest 5,000 tracked signed-in page views in the selected date range; older activity may not be included. Anonymous visitors are counted above but cannot be identified.</p><div style={{overflowX:'auto'}}><table><thead><tr><th>Name</th><th>Email</th><th>First seen (Toronto)</th><th>Last seen (Toronto)</th><th>Page views</th></tr></thead><tbody>{uniquePeople.map(p=><tr key={p.email||p.name}><td>{p.name||'—'}</td><td>{p.email||'—'}</td><td>{localTime(p.first)}</td><td>{localTime(p.last)}</td><td>{p.views}</td></tr>)}</tbody></table></div>{!uniquePeople.length&&<p className="muted">No signed-in visits recorded in this date range.</p>}</>}
 </section>;
}
