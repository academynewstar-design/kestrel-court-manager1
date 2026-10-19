import {useEffect,useRef,type ReactNode} from 'react';

export type GameSelection={sport:string;city:string;location:string};
type Props={
 selection:GameSelection;
 sports:string[];
 cities:string[];
 locations:string[];
 onChange:(selection:GameSelection)=>void;
 children:ReactNode;
};

const sportIcon=(sport:string)=>({volleyball:'🏐',badminton:'🏸',soccer:'⚽',basketball:'🏀',pickleball:'🏓'}[sport]||'🎯');

/** Show one choice at a time; the dashboard owns the selected session filters. */
export default function GamePicker({selection,sports,cities,locations,onChange,children}:Props){
 const{sport,city,location}=selection;
 const step=!sport?1:!city?2:!location?3:4;
 const title=['Choose your sport','Choose your city','Choose your location','Available sessions'][step-1];
 const heading=useRef<HTMLHeadingElement>(null);
 const previousStep=useRef(step);
 useEffect(()=>{
  if(previousStep.current===step)return;
  previousStep.current=step;
  heading.current?.focus({preventScroll:true});
  heading.current?.closest('.game-picker')?.scrollIntoView({block:'start',behavior:'instant'});
 },[step]);
 function home(){onChange({sport:'',city:'',location:''})}
 function back(){
  if(location)onChange({...selection,location:''});
  else if(city)onChange({...selection,city:'',location:''});
  else home();
 }
 return <section className={'card game-picker picker-'+(sport||'home')} aria-label="Find your next game">
  {step>1&&<div className="picker-navigation"><button className="outline" onClick={back}>← Back</button><button className="outline" onClick={home}>⌂ All Sports</button></div>}
  <div className={step>1?'picker-heading colourful':'picker-heading'}>
  <span className="eyebrow">{step===1?'PICK A SPORT. MAKE YOUR MOVE.':`STEP ${step} OF 4`}</span>
  <h2 ref={heading} tabIndex={-1}>{title}</h2>
  {step===1?<p className="muted">Find your next game. Start with a sport, then choose where to play.</p>:<p className="picker-selection" aria-label="Your selection"><span>{sport}</span>{city&&<> · {city}</>}{location&&<> · {location}</>}</p>}
  {step>1&&<div className="picker-progress" aria-hidden="true">{[1,2,3,4].map(n=><span key={n} className={n<=step?'complete':''}/>)}</div>}
  </div>
  {step===1&&<>{sports.length?<div className="sport-choices">{sports.map(name=><button key={name} className={'sport-choice sport-'+name} onClick={()=>onChange({sport:name,city:'',location:''})}><span className="sport-icon" aria-hidden="true">{sportIcon(name)}</span><span>{name}</span></button>)}</div>:<p>No Drop-in sports are currently available. Check back soon.</p>}</>}
  {step===2&&<>{cities.length?<div className="picker-choices">{cities.map(name=><button className="outline" key={name} onClick={()=>onChange({...selection,city:name,location:''})}><span className="picker-place-icon" aria-hidden="true">📍</span><span className="picker-choice-label">{name}</span><span className="picker-choice-arrow" aria-hidden="true">→</span></button>)}</div>:<p>No cities are currently available for this sport. Choose All Sports to try another.</p>}</>}
  {step===3&&<>{locations.length?<div className="picker-choices picker-locations">{locations.map(name=><button className="outline" key={name} onClick={()=>onChange({...selection,location:name})}><span className="picker-place-icon" aria-hidden="true">📍</span><span className="picker-choice-label">{name}</span><span className="picker-choice-arrow" aria-hidden="true">→</span></button>)}</div>:<p>No locations are currently available in this city. Choose Back to try another city.</p>}</>}
  {step===4&&<><p className="muted picker-session-help">Individual spots join immediately; groups need Admin approval.</p><div className="picker-session-list">{children}</div></>}
 </section>;
}
