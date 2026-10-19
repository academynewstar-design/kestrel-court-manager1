export type ExclusiveCourtBooking={id:number;session_id:number;lead_name:string;guest_count:number};
export function exclusiveCourtText(b:ExclusiveCourtBooking,court:string){return court+' · '+b.lead_name+(b.guest_count?' + '+b.guest_count+' guests':'')+' · Entire court reserved'}
export function ExclusiveCourtList({bookings,sessionCourts}:{bookings:ExclusiveCourtBooking[];sessionCourts:Record<string,string>}){
 if(!bookings.length)return null;
 return <div className="notice"><h3>Full-court group bookings ({bookings.length})</h3>{bookings.map(b=><p key={b.id}><strong>{exclusiveCourtText(b,sessionCourts[String(b.session_id)]||'Court')}</strong></p>)}</div>;
}
export function RosterCourtControl({name,courts,value,busy,changed,onChange,onSave}:{name:string;courts:string[];value:string;busy:boolean;changed:boolean;onChange:(court:string)=>void;onSave:()=>void}){
 return <div className="rowactions"><select aria-label={'Court for '+name} value={value} onChange={e=>onChange(e.target.value)}>{courts.map(c=><option key={c} value={c}>{c}</option>)}</select><button disabled={!changed||busy} onClick={onSave}>{busy?'Saving…':'Save court'}</button></div>;
}
