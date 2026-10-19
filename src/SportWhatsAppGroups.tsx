const groups=[{sport:'volleyball',city:'Mississauga',url:'https://chat.whatsapp.com/CAjGbTJIE5cKQ7G5Dsj9Jt?s=cl&p=a&mlu=4&ilr=4'}];
const normalized=(value?:string)=>String(value||'').trim().toLowerCase();
export default function SportWhatsAppGroups({sessions,sport,city,directory=false}:{sessions?:any[];sport?:string;city?:string;directory?:boolean}){
 const visible=groups.filter(g=>directory||sessions?.some(s=>normalized(s.sports?.name)===g.sport&&normalized(s.locations?.city)===normalized(g.city))||normalized(sport)===g.sport&&normalized(city)===normalized(g.city));
 if(!visible.length)return null;
 return <div className="sport-whatsapp-groups" style={{margin:'12px 0'}}>{visible.map(g=><p key={g.sport+'-'+g.city} style={{margin:'6px 0'}}><a className="button outline" href={g.url} target="_blank" rel="noopener noreferrer" style={{padding:'9px 14px',fontSize:'0.9rem'}}>💬 Join {g.city} Volleyball WhatsApp group</a></p>)}</div>;
}
