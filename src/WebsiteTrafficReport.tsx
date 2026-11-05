import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';

type TrafficRow = { day: string | null; page_name: string; page_views: number; visits: number; unique_visitors: number; guest_page_views: number };
export default function WebsiteTrafficReport({start,end,refresh}:{start:string;end:string;refresh:number}) {
 const [rows,setRows]=useState<TrafficRow[]>([]);
 const [error,setError]=useState('');
 const [loading,setLoading]=useState(true);
 useEffect(()=>{
  let active=true;
  async function load(){
   if(start>end){setError('Invalid date range');setRows([]);setLoading(false);return;}
   setLoading(true);
   const {data,error}=await supabase.rpc('admin_website_traffic_report',{p_start_date:start,p_end_date:end});
   if(!active)return;
   setRows((data||[]) as TrafficRow[]);setError(error?.message||'');setLoading(false);
  }
  void load();const timer=setInterval(()=>void load(),60000);
  return()=>{active=false;clearInterval(timer)};
 },[start,end,refresh]);
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
  {!details.length&&<p className="muted">No tracked visits for these dates.</p>}</>}
 </section>;
}
