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
  const route = location.hash.replace(/^#\/?/, '').split(/[?&]/)[0];
  const safe = route.replace(/[^a-zA-Z0-9 _/-]/g, '').slice(0, 80);
  return safe || 'Home';
}
export function startWebsiteAnalytics() {
  if (typeof window === 'undefined' || !crypto.randomUUID) return;
  let visitorId: string, sessionId: string;
  try { visitorId = getId(localStorage, VISITOR_KEY); sessionId = getId(sessionStorage, SESSION_KEY); }
  catch { return; }
  let lastPage = '';
  const track = () => {
    const page = pageName();
    if (page === lastPage) return;
    lastPage = page;
    void supabase.rpc('record_website_page_view', { p_visitor_id: visitorId, p_session_id: sessionId, p_page_name: page });
  };
  track();
  window.addEventListener('hashchange', track);
  window.addEventListener('popstate', track);
}
