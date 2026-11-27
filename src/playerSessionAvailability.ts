type AvailabilitySession = {
  location_id?: number | string;
  locations?: {name?: string};
  session_date: string;
  availability_status?: string;
  status?: string;
};

// Match the calendar: a closure covers every sport and court at the school.
export function availablePlayerSessions<T extends AvailabilitySession>(sessions: T[]): T[] {
  const schoolDay = (s: T) => `${s.location_id ?? s.locations?.name}:${s.session_date}`;
  const closed = new Set(sessions.filter(s => s.availability_status === 'unavailable').map(schoolDay));
  return sessions.filter(s => !closed.has(schoolDay(s)) && s.status !== 'closed' && s.status !== 'cancelled');
}
