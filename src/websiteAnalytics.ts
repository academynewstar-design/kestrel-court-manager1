import { supabase } from './lib/supabase';

const VISITOR_KEY = 'kestrel_visitor_id_v1';
const SESSION_KEY = 'kestrel_session_id_v1';
const validUuid = (value: string | null) => !!value && /^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(value);
function getId(store: Storage, key: string) {
  let id = store.getItem(key);
  if (!validUuid(id)) { id = crypto.randomUUID(); store.setItem(key, id); }
  return id!;
}
function pageName() {
  // Never send URL hashes or query strings: auth tokens may be present there.
  const route = /(?:access_token|refresh_token|id_token|code)=/i.test(location.hash) ? '' : location.hash.replace(/^#\/?/, '').split(/[?&]/)[0];
  const safe = route.replace(/[^a-zA-Z0-9 _/-]/g, '').slice(0, 80);
  return safe || 'Home';
}
export function startWebsiteAnalytics() {
  if (typeof window === 'undefined' || !crypto.randomUUID) return;
  let visitorId: string, sessionId: string;
  try { visitorId = getId(localStorage, VISITOR_KEY); sessionId = getId(sessionStorage, SESSION_KEY); }
  catch { return; }
  let lastKey = '';
  let lastSent = 0;
  let authenticated = false;
  const track = async (force = false) => {
    const page = pageName();
    const key = page + ':' + authenticated;
    if (!force && key === lastKey && Date.now() - lastSent < 60000) return;
    const { error } = await supabase.rpc('record_website_page_view', {
      p_visitor_id: visitorId, p_session_id: sessionId, p_page_name: page
    });
    if (!error) { lastKey = key; lastSent = Date.now(); }
    else console.warn('Kestrel visitor analytics unavailable:', error.message);
  };
  void supabase.auth.getUser().then(({data}) => {
    authenticated = !!data.user;
    void track(true);
  });
  supabase.auth.onAuthStateChange((_event, session) => {
    const next = !!session?.user;
    if (next !== authenticated) { authenticated = next; void track(true); }
  });
  window.addEventListener('hashchange', () => void track());
  window.addEventListener('popstate', () => void track());
  window.addEventListener('pageshow', () => void track());
  window.addEventListener('focus', () => void track());
}
