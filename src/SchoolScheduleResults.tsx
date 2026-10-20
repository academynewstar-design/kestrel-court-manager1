import type {ReactNode} from 'react';

type Session = {
  id: number;
  location_id: number;
  sport_id: number;
  session_date: string;
  start_time: string;
  availability_status?: string;
  locations?: {name: string};
};
type Filters = {sport: string; location: string; date: string; time: string};
const schoolDay = (s: Session) => `${s.location_id}:${s.session_date}`;

export function schoolScheduleResults(sessions: Session[], filters: Filters) {
  // Availability is set for the whole school/day. Resolve closures before
  // sport/time filtering so a stale available court cannot hide a closure.
  const closedDays = new Set(sessions.filter(s => s.availability_status === 'unavailable').map(schoolDay));
  const matches = sessions.filter(s =>
    (!filters.sport || String(s.sport_id) === filters.sport) &&
    (!filters.location || String(s.location_id) === filters.location) &&
    (!filters.date || s.session_date === filters.date) &&
    (!filters.time || s.start_time.slice(0, 5) === filters.time));
  const closures = new Map<string, Session>();
  const available: Session[] = [];
  for (const session of matches) {
    const key = schoolDay(session);
    if (closedDays.has(key)) closures.set(key, session);
    else available.push(session);
  }
  return {closures: [...closures.values()], available};
}

export default function SchoolScheduleResults({sessions, filters, renderSession, onRestore}: {
  sessions: Session[];
  filters: Filters;
  renderSession: (session: any) => ReactNode;
  onRestore: (session: Session) => void;
}) {
  const {closures, available} = schoolScheduleResults(sessions, filters);
  return <>
    {closures.map(s => <div className="session" key={schoolDay(s)}>
      <div role="status">
        <strong>School not available on this day</strong>
        <p>{s.locations?.name} · {new Date(s.session_date + 'T12:00:00').toLocaleDateString('en-CA', {month: 'long', day: 'numeric', year: 'numeric'})}</p>
      </div>
      <button className="outline" onClick={() => onRestore(s)}>✓ Mark School Available</button>
    </div>)}
    {available.map(renderSession)}
    {!closures.length && !available.length && <p className="muted">No upcoming sessions match your search.</p>}
  </>;
}
