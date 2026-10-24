import {useEffect, useRef, useState, type ReactNode} from 'react';
import {supabase} from './lib/supabase';
import './admin-calendar.css';

type Location = {id: number; name: string; city?: string};
type Sport = {id: number; name: string};
export type CalendarSession = {
  id: number; location_id: number; sport_id: number; session_date: string;
  start_time: string; end_time: string; court?: string; availability_status?: string;
  status?: string; sports?: {name: string}; locations?: {name: string; city?: string};
  [key: string]: any;
};
export const torontoDate = () => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Toronto', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date());
const normalize = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const longDate = (date: string) => new Date(date + 'T12:00:00').toLocaleDateString('en-CA', {
  weekday: 'long', month: 'long', day: 'numeric', year: 'numeric',
});
const time = (value: string) => new Date('2000-01-01T' + value).toLocaleTimeString('en-CA', {hour: 'numeric', minute: '2-digit'});

export function schoolCalendarDay(sessions: CalendarSession[], locations: Location[], date: string, sport = '', query = '') {
  const day = sessions.filter(s => s.session_date === date);
  return locations.filter(l => normalize(l.name + ' ' + (l.city || '')).includes(normalize(query.trim())))
    .map(location => {
      const all = day.filter(s => s.location_id === location.id);
      const matching = all.filter(s => !sport || String(s.sport_id) === sport);
      // A school closure always applies across its sports and courts.
      const closed = all.some(s => s.availability_status === 'unavailable');
      const status = closed ? 'unavailable' : matching.length ? 'available' : 'no-session';
      return {location, sessions: matching, all, status};
    }).sort((a, b) => a.location.name.localeCompare(b.location.name));
}

// Supabase limits each response. A selected month can still contain >1,000 court rows.
export async function loadCalendarMonth(month: string) {
  const [year, number] = month.split('-').map(Number);
  const last = new Date(year, number, 0).getDate();
  const rows: CalendarSession[] = [];
  for (let offset = 0; ; offset += 500) {
    const {data, error} = await supabase.from('sessions')
      .select('id,sport_id,location_id,session_date,start_time,end_time,court,capacity,price,payment_email,payment_first,status,availability_status,dropin_enabled,dropin_spots,registration_open_override,registration_open_at,sports(name),locations(name,city)')
      .gte('session_date', month + '-01').lte('session_date', month + '-' + last)
      .order('session_date').order('start_time').order('id').range(offset, offset + 499);
    if (error) throw new Error(error.message);
    rows.push(...(data || []) as unknown as CalendarSession[]);
    if (!data || data.length < 500) return rows;
  }
}

export default function AdminAvailabilityCalendar({locations, sports, revision, onChanged, renderSession, readOnly = false}: {
  locations: Location[]; sports: Sport[]; revision: unknown; onChanged: () => void;
  renderSession: (session: CalendarSession) => ReactNode; readOnly?: boolean;
}) {
  const [date, setDate] = useState(torontoDate);
  const [month, setMonth] = useState(() => torontoDate().slice(0, 7));
  const [sport, setSport] = useState('');
  const [query, setQuery] = useState('');
  const [sessions, setSessions] = useState<CalendarSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState<number | null>(null);
  const [refresh, setRefresh] = useState(0);
  const request = useRef(0);
  const saveInProgress = useRef(false);
  useEffect(() => {
    const id = ++request.current;
    setLoading(true); setError(''); setSessions([]);
    loadCalendarMonth(month).then(rows => {if (id === request.current) setSessions(rows);})
      .catch(e => {if (id === request.current) setError(e.message || 'Unable to load the calendar. Please retry.');})
      .finally(() => {if (id === request.current) setLoading(false);});
    return () => {request.current++;};
  }, [month, revision, refresh]);

  function chooseDate(value: string) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return;
    setDate(value); setMonth(value.slice(0, 7)); setMessage('');
  }
  function changeMonth(delta: number) {
    const [y, m] = month.split('-').map(Number);
    const next = new Date(y, m - 1 + delta, 1);
    const value = next.getFullYear() + '-' + String(next.getMonth() + 1).padStart(2, '0') + '-01';
    chooseDate(value);
  }
  async function toggle(location: Location, unavailable: boolean) {
    if (saveInProgress.current) return;
    const selectedDate = date;
    const availability = unavailable ? 'available' : 'unavailable';
    if (!window.confirm(`Mark ${location.name} ${availability} on ${longDate(selectedDate)}? This affects all sports and courts at this school on this date.`)) return;
    saveInProgress.current = true;
    setSaving(location.id); setMessage(''); setError('');
    try {
      const {error: failure} = await supabase.rpc('admin_set_school_availability', {
        p_location_name: location.name, p_session_date: selectedDate, p_availability: availability,
      });
      if (failure) throw new Error(failure.message);
      setMessage(`${location.name} · ${longDate(selectedDate)}: ${availability}.`);
      setRefresh(v => v + 1); onChanged();
    } catch (e) {setError(e instanceof Error ? e.message : 'Could not save availability. Please retry.');}
    finally {saveInProgress.current = false; setSaving(null);}
  }

  const schools = schoolCalendarDay(sessions, locations, date, sport, query);
  const scheduled = schools.filter(s => s.status !== 'no-session');
  const unscheduled = schools.filter(s => s.status === 'no-session');
  const [year, monthNumber] = month.split('-').map(Number);
  const offset = new Date(year, monthNumber - 1, 1).getDay();
  const days = new Date(year, monthNumber, 0).getDate();
  const current = torontoDate();
  return <section className="card admin-calendar" aria-labelledby="admin-calendar-title">
    <div className="sectionhead"><div><h2 id="admin-calendar-title">{readOnly ? 'Activity availability calendar' : 'School availability calendar'}</h2>
      <p className="muted">Tap a date to see schools and their session times.</p></div>
      <button className="outline" onClick={() => chooseDate(current)}>Today</button></div>
    <div className="calendar-filters">
      <label>Find a school or city<input type="search" placeholder="Example: Ange Gabriel" value={query} onChange={e => setQuery(e.target.value)}/></label>
      <label>Sport (optional)<select value={sport} onChange={e => setSport(e.target.value)}><option value="">All sports</option>{sports.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
    </div>
    <div className="calendar-navigation">
      <button className="outline" aria-label="Previous month" onClick={() => changeMonth(-1)}>‹</button>
      <strong>{new Date(year, monthNumber - 1, 1).toLocaleDateString('en-CA', {month: 'long', year: 'numeric'})}</strong>
      <button className="outline" aria-label="Next month" onClick={() => changeMonth(1)}>›</button>
    </div>
    <div className="calendar-weekdays" aria-hidden="true">{['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(d => <span key={d}>{d}</span>)}</div>
    <div className="calendar-days" role="group" aria-label="Choose a calendar date">
      {Array.from({length: offset}, (_, i) => <span key={'blank-' + i}/>)}
      {Array.from({length: days}, (_, i) => {
        const value = month + '-' + String(i + 1).padStart(2, '0');
        const summary = schoolCalendarDay(sessions, locations, value, sport, query);
        const available = summary.filter(s => s.status === 'available').length;
        const unavailable = summary.filter(s => s.status === 'unavailable').length;
        return <button key={value} type="button" className={'calendar-day' + (date === value ? ' selected' : '')}
          aria-pressed={date === value} aria-current={value === current ? 'date' : undefined}
          aria-label={longDate(value) + (!loading && !error ? `, ${available} schools available, ${unavailable} unavailable` : '')}
          onClick={() => chooseDate(value)}><span>{i + 1}</span><span className="calendar-dots" aria-hidden="true">{!loading && !error && available > 0 && <i className="available"/>}{!loading && !error && unavailable > 0 && <i className="unavailable"/>}</span></button>;
      })}
    </div>
    <div className="calendar-legend"><span><i className="available"/> Available</span><span><i className="unavailable"/> Unavailable</span></div>
    <label className="calendar-date-jump">Go to date<input type="date" value={date} onChange={e => chooseDate(e.target.value)}/></label>
    <h3>{longDate(date)}</h3>
    {message && <p className="success" role="status">{message}</p>}
    {error && <div role="alert"><p className="error">{error}</p><button className="outline" onClick={() => setRefresh(v => v + 1)}>Retry calendar</button></div>}
    {loading ? <p role="status">Loading school availability…</p> : !error && <>
      <p className="muted">{scheduled.filter(s => s.status === 'available').length} available · {scheduled.filter(s => s.status === 'unavailable').length} unavailable</p>
      {scheduled.map(school => {
        const unavailable = school.status === 'unavailable';
        const times = [...new Map(school.sessions.map(s => [s.sport_id + '|' + s.start_time + '|' + s.end_time, s])).values()];
        return <article className={'calendar-school ' + school.status} key={school.location.id}>
          <div className="calendar-school-heading"><div><h4>{school.location.name}</h4><small>{school.location.city}</small></div><span className="calendar-status">{unavailable ? 'Unavailable' : 'Available'}</span></div>
          {times.map(s => <p className="calendar-session-time" key={s.id}>{s.sports?.name} · {time(s.start_time)}–{time(s.end_time)}</p>)}
          {unavailable && <p>School not available on this day.</p>}
          {!readOnly && <button className={unavailable ? 'outline' : 'danger'} disabled={saving !== null}
            onClick={() => toggle(school.location, unavailable)}>{saving === school.location.id ? 'Saving…' : unavailable ? 'Mark school available' : 'Mark school unavailable'}</button>}
          {!readOnly && school.sessions.length > 0 && <details><summary>Manage session details</summary>{school.sessions.map(renderSession)}</details>}
        </article>;
      })}
      {!scheduled.length && schools.length > 0 && <p className="notice">No sessions scheduled for {query ? 'this school search' : 'these filters'} on this date. This does not mean the school is unavailable.</p>}
      {unscheduled.length > 0 && <details className="calendar-no-sessions" open={!!query}>
        <summary>No session scheduled ({unscheduled.length} {unscheduled.length === 1 ? 'school' : 'schools'})</summary>
        {unscheduled.map(s => <div key={s.location.id}><strong>{s.location.name}</strong><p className="muted">{s.all.length && sport ? 'Other sports are scheduled here. Select All sports to see them.' : 'No session scheduled on this date. School availability is not confirmed.'}</p></div>)}
      </details>}
      {!schools.length && <p className="muted">No school matches “{query}”. Try part of its name or city.</p>}
    </>}
  </section>;
}
