export type SeasonCourtRow = {
  key: string; userId: string; player: string; locationId: string;
  location: string; city: string; sport: string; day: string;
  scheduleId: string; schedule: string; court: string;
};
export const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

export function seasonCourtRows(requests: any[]): SeasonCourtRow[] {
  const rows = new Map<string, SeasonCourtRow>();
  for (const r of requests) {
    const p = r.profiles, s = r.recurring_schedules;
    if (r.status !== 'approved' || !s?.active || p?.player_type !== 'permanent' || p?.player_type_status !== 'approved') continue;
    const key = `${r.recurring_schedule_id}|${r.user_id}`;
    rows.set(key, {
      key, userId: String(r.user_id), player: p.full_name?.trim() || p.email || 'Unnamed player',
      locationId: String(s.location_id), location: s.locations?.name || 'Unknown location',
      city: s.locations?.city || '', sport: s.sports?.name || 'Unknown sport', day: s.weekday,
      scheduleId: String(s.id), schedule: s.schedule_label,
      court: s.sports?.name === 'badminton' ? (r.court?.trim() || 'Court not assigned') : 'General',
    });
  }
  return [...rows.values()].sort((a, b) => a.location.localeCompare(b.location) || a.sport.localeCompare(b.sport)
    || weekdays.indexOf(a.day) - weekdays.indexOf(b.day) || a.schedule.localeCompare(b.schedule, undefined, {numeric: true})
    || a.court.localeCompare(b.court, undefined, {numeric: true}) || a.player.localeCompare(b.player));
}

export function filterSeasonCourts(rows: SeasonCourtRow[], locations: string[], sport: string, day: string, search: string) {
  const q = search.trim().toLocaleLowerCase();
  return rows.filter(r => (!locations.length || locations.includes(r.locationId)) && (!sport || r.sport === sport)
    && (!day || r.day === day) && (!q || r.player.toLocaleLowerCase().includes(q)));
}

export function groupSeasonCourts(rows: SeasonCourtRow[]) {
  const groups = new Map<string, {key: string; row: SeasonCourtRow; courts: Map<string, SeasonCourtRow[]>}>();
  for (const row of rows) {
    const key = `${row.locationId}|${row.scheduleId}`;
    let group = groups.get(key);
    if (!group) { group = {key, row, courts: new Map()}; groups.set(key, group); }
    group.courts.set(row.court, [...(group.courts.get(row.court) || []), row]);
  }
  return [...groups.values()];
}

export function seasonCourtText(rows: SeasonCourtRow[]) {
  return '*Kestrel Sports Club — Season Players by Court*\nRegular weekly assignments (includes temporary absences).\n\n'
    + groupSeasonCourts(rows).map(g => `*${g.row.location}${g.row.city ? ' · ' + g.row.city : ''}*\n${g.row.sport} · ${g.row.day} · ${g.row.schedule}\n`
      + [...g.courts].map(([court, players]) => `*${court} (${players.length})*\n` + players.map((p, i) => `${i + 1}. ${p.player} (S)`).join('\n')).join('\n\n')).join('\n\n');
}

export function seasonCourtCsv(rows: SeasonCourtRow[]) {
  // Prevent names or labels from being interpreted as spreadsheet formulas.
  const cell = (value: string) => '"' + (/^[\s]*[=+@-]/.test(value) ? "'" + value : value).replaceAll('"', '""') + '"';
  return '\uFEFF' + [['Location', 'City', 'Sport', 'Day', 'Session', 'Court', 'Season player'],
    ...rows.map(r => [r.location, r.city, r.sport, r.day, r.schedule, r.court, r.player])]
    .map(row => row.map(cell).join(',')).join('\r\n');
}
