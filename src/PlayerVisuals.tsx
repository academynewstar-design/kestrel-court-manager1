/** Decorative court artwork shared by registration and the player dashboard. */
export function SportsArtwork(){
 return <svg className="sports-artwork" viewBox="0 0 240 160" aria-hidden="true" focusable="false">
  <path d="M30 160 115 0M115 160 200 0M0 100H240" fill="none" stroke="currentColor" strokeWidth="1" opacity=".15"/>
  <circle cx="155" cy="62" r="52" fill="#ffad32"/>
  <g fill="none" stroke="#7c3509" strokeWidth="2.5"><circle cx="155" cy="62" r="48"/><path d="m121 25 68 74M107 66l94-9M149 14q-35 49 27 91M179 18q-3 49-54 80"/></g>
  <g className="art-shuttle" transform="translate(65 40) rotate(-26)"><path d="m0 32-20-45h40Z" fill="#fff"/><path d="M0 32V-13M0 32-12-13M0 32 12-13M-15-1h30M-10 12h20" stroke="#74c7ef" strokeWidth="2"/><ellipse cy="34" rx="10" ry="11" fill="#c4f23c"/></g>
  <g transform="translate(72 121)"><circle r="30" fill="#fff"/><path d="m0-14-13 9 5 16H8L13-5ZM-27-12l10-9 3 9-8 9Zm54 0-10-9-3 9 8 9ZM-17 25l-1-12 10 5 1 12Zm34 0 1-12-10 5-1 12Z" fill="#103368"/><path d="m0-14-3-15M-13-5-27-1M13-5 27-1M-8 11l-9 14M8 11l9 14" fill="none" stroke="#103368" strokeWidth="1.5"/></g>
  <path d="m200 123 4-10 4 10 10 4-10 4-4 10-4-10-10-4Z" fill="#c4f23c"/>
  <circle cx="25" cy="85" r="5" fill="#5de7d9"/><circle cx="220" cy="34" r="3" fill="#fff"/>
 </svg>;
}

export function PlayBanner(){
 return <section className="play-banner" aria-label="Welcome to Kestrel Sports">
  <div><span className="eyebrow">GOOD GAMES. GREAT COMPANY.</span><h1>Ready to play?</h1><p>Your community. Your next game.</p></div><SportsArtwork/><div className="banner-bird" aria-hidden="true"><img src="/kestrel-flying.svg" alt=""/></div>
 </section>;
}
