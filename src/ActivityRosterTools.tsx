import type {ReactNode} from 'react';
export type ExclusiveCourtBooking={id:number;session_id:number;lead_name:string;guest_count:number};
export function exclusiveCourtText(b:ExclusiveCourtBooking,court:string){return court+' · '+b.lead_name+(b.guest_count?' + '+b.guest_count+' guests':'')+' · Entire court reserved'}
export function ExclusiveCourtList({bookings,sessionCourts}:{bookings:ExclusiveCourtBooking[];sessionCourts:Record<string,string>}){
 if(!bookings.length)return null;
 return <div className="notice"><h3>Full-court group bookings ({bookings.length})</h3>{bookings.map(b=><p key={b.id}><strong>{exclusiveCourtText(b,sessionCourts[String(b.session_id)]||'Court')}</strong></p>)}</div>;
}
export function RosterCourtControl({name,courts,value,busy,changed,onChange,onSave}:{name:string;courts:string[];value:string;busy:boolean;changed:boolean;onChange:(court:string)=>void;onSave:()=>void}){
 return <div className="rowactions"><select aria-label={'Court for '+name} value={value} onChange={e=>onChange(e.target.value)}>{courts.map(c=><option key={c} value={c}>{c}</option>)}</select><button disabled={!changed||busy} onClick={onSave}>{busy?'Saving…':'Save court'}</button></div>;
}

export const compareCourts=(a:string,b:string)=>{const num=(s:string)=>{const m=s.match(/(?:court|courtroom|terrain)\s*(\d+)/i);return m?Number(m[1]):Number.POSITIVE_INFINITY;};const diff=num(a)-num(b);return Number.isNaN(diff)?a.localeCompare(b,undefined,{numeric:true,sensitivity:'base'}):diff||a.localeCompare(b,undefined,{numeric:true,sensitivity:'base'});};
export function groupRosterByCourt<T>(players:T[],courtFor:(player:T)=>string){
 const groups=new Map<string,T[]>();
 for(const player of players){const court=courtFor(player)||'General';groups.set(court,[...(groups.get(court)||[]),player]);}
 return Array.from(groups,([court,players])=>({court,players:players.slice().sort((a,b)=>String((a as {full_name?:string;name?:string;player_name?:string}).full_name||(a as {name?:string}).name||(a as {player_name?:string}).player_name||'').localeCompare(String((b as {full_name?:string;name?:string;player_name?:string}).full_name||(b as {name?:string}).name||(b as {player_name?:string}).player_name||''),undefined,{sensitivity:'base'}))})).sort((a,b)=>compareCourts(a.court,b.court));
}
export function CourtRoster<T>({players,courtFor,renderPlayer}:{players:T[];courtFor:(player:T)=>string;renderPlayer:(player:T,index:number)=>ReactNode}){
 return <>{groupRosterByCourt(players,courtFor).map(({court,players})=><section key={court} aria-label={court+' roster'}><h4>{court} · {players.reduce((n,p)=>n+Number((p as {party_size?:number}).party_size||1),0)} going</h4>{players.map(renderPlayer)}</section>)}</>;
}
