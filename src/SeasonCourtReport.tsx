import {useEffect, useState} from 'react';
import {supabase} from './lib/supabase';
import {filterSeasonCourts, groupSeasonCourts, seasonCourtCsv, seasonCourtRows, seasonCourtText, weekdays} from './lib/seasonCourtReport';
import type {SeasonCourtRow} from './lib/seasonCourtReport';

export default function SeasonCourtReport() {
  const [rows, setRows] = useState<SeasonCourtRow[]>([]);
  const [loading, setLoading] = useState(true), [error, setError] = useState('');
  const [refresh, setRefresh] = useState(0), [locations, setLocations] = useState<string[]>([]);
  const [sport, setSport] = useState(''), [day, setDay] = useState(''), [search, setSearch] = useState('');
  const [moving, setMoving] = useState(''), [moveError, setMoveError] = useState('');
  const [copyMessage, setCopyMessage] = useState(''), [manualCopy, setManualCopy] = useState(false);
  useEffect(() => {
    let active = true;
    async function load() {
      setLoading(true); setError(''); setCopyMessage(''); setManualCopy(false);
      try {
        const requests: any[] = [];
        // Fetch every assignment rather than silently stopping at the API row limit.
        for (let offset = 0; ; offset += 500) {
          const {data, error} = await supabase.from('recurring_permanent_requests')
            .select('id,user_id,recurring_schedule_id,court,status,profiles!recurring_permanent_requests_user_id_fkey(full_name,email,player_type,player_type_status),recurring_schedules(id,location_id,active,weekday,schedule_label,sports(name),locations(name,city))')
            .eq('status', 'approved').order('id').range(offset, offset + 499);
          if (!active) return;
          if (error) throw error;
          requests.push(...(data || []));
          if ((data || []).length < 500) break;
        }
        setRows(seasonCourtRows(requests));
      } catch (e) {
        if (active) { setRows([]); setError(e instanceof Error ? e.message : (e as {message?: string})?.message || 'Unable to load Season assignments.'); }
      } finally { if (active) setLoading(false); }
    }
    load(); return () => { active = false; };
  }, [refresh]);
  const locationOptions = [...new Map(rows.map(r => [r.locationId, {id: r.locationId, name: r.location, city: r.city}])).values()];
  const visible = filterSeasonCourts(rows, locations, sport, day, search);
  const groups = groupSeasonCourts(visible);
  const text = seasonCourtText(visible);
  async function movePermanent(player: SeasonCourtRow, target: string) {
    if (target === player.court) return;
    setMoveError('');
    const occupied = rows.filter(r => r.scheduleId === player.scheduleId && r.court === target && r.key !== player.key).length;
    if (occupied >= 5) { setMoveError(target + ' already has 5 Season players. Transfer cancelled.'); return; }
    if (!window.confirm('Permanently move ' + player.player + ' to ' + target + ' for ' + player.day + ' · ' + player.schedule + '? This updates the recurring assignment for future weeks.')) return;
    setMoving(player.key);
    try {
      const {data, error} = await supabase.from('recurring_permanent_requests')
        .update({court: target}).eq('user_id', player.userId).eq('recurring_schedule_id', player.scheduleId)
        .eq('status', 'approved').select('id');
      if (error) throw error;
      if (!data?.length) throw new Error('No assignment was updated. Check administrator permissions.');
      setCopyMessage(player.player + ' permanently assigned to ' + target + '.');
      setRefresh(v => v + 1);
    } catch (e) { setMoveError(e instanceof Error ? e.message : 'Transfer failed.'); }
    finally { setMoving(''); }
  }
  async function copy() {
    try { await navigator.clipboard.writeText(text); setCopyMessage('Combined report copied. Paste it into WhatsApp.'); setManualCopy(false); }
    catch { setManualCopy(true); setCopyMessage('Select and copy the report below.'); }
  }
  function exportCsv() {
    const url = URL.createObjectURL(new Blob([seasonCourtCsv(visible)], {type: 'text/csv;charset=utf-8;'}));
    const link = document.createElement('a'); link.href = url; link.download = 'kestrel-season-players-by-court.csv';
    document.body.appendChild(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return <section className="card">
    <div className="sectionhead"><h2>Season Players by Court</h2><button className="outline" disabled={loading} onClick={() => setRefresh(v => v + 1)}>Refresh</button></div>
    <p className="muted">Approved Season players and their regular weekly assignments across all locations. Temporary Not Going / vacation choices are included. Use Permanent court to change the weekly assignment; date-specific overrides are managed separately. For attendance or a court change on a particular date, use Activity roster.</p>
    <div className="grid2">
      <label>Sport<select value={sport} onChange={e => setSport(e.target.value)}><option value="">All sports</option>{[...new Set(rows.map(r => r.sport))].sort().map(s => <option key={s}>{s}</option>)}</select></label>
      <label>Day<select value={day} onChange={e => setDay(e.target.value)}><option value="">All days</option>{weekdays.map(d => <option key={d}>{d}</option>)}</select></label>
      <label>Player name<input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search Season players"/></label>
    </div>
    <fieldset style={{border: '1px solid #cbd5e1', borderRadius: 12, padding: 12, margin: '16px 0'}}>
      <legend>Locations / Schools</legend>
      <button className={!locations.length ? '' : 'outline'} onClick={() => setLocations([])}>All locations</button>
      <p className="muted">Select several schools to combine them. No selection shows all locations.</p>
      <div className="grid2">{locationOptions.map(l => <label key={l.id} style={{display: 'flex', alignItems: 'center', gap: 8}}><input type="checkbox" style={{width: 'auto', flexShrink: 0}} checked={locations.includes(l.id)} onChange={e => setLocations(v => e.target.checked ? [...v, l.id] : v.filter(id => id !== l.id))}/>{l.name}{l.city ? ' · ' + l.city : ''}</label>)}</div>
    </fieldset>
    <div className="rowactions">
      <button className="outline" onClick={() => {setLocations([]); setSport(''); setDay(''); setSearch(''); setManualCopy(false); setCopyMessage('');}}>Clear filters</button>
      <button disabled={loading || !!error || !visible.length} onClick={copy}>Copy combined report for WhatsApp</button>
      <button className="outline" disabled={loading || !!error || !visible.length} onClick={exportCsv}>Export CSV</button>
    </div>
    {copyMessage && <p role="status">{copyMessage}</p>}
    {manualCopy && <label>Combined report<textarea readOnly rows={12} value={text} onFocus={e => e.target.select()}/></label>}
    {moveError && <p className="error" role="alert">{moveError}</p>}
    {error && <p className="error" role="alert">Could not load the report: {error}</p>}
    {loading ? <p role="status">Loading Season assignments…</p> : !error && <>
      <p><strong>{new Set(visible.map(r => r.userId)).size} Season players</strong> · {visible.length} weekly assignments · {new Set(visible.map(r => r.locationId)).size} locations</p>
      {groups.map(g => <div className="notice" key={g.key}>
        <h3>{g.row.location}{g.row.city ? ' · ' + g.row.city : ''}</h3>
        <p><strong>{g.row.sport} · {g.row.day}</strong> · {g.row.schedule}</p>
        {[...g.courts].map(([court, players]) => <div key={court}><h4>{court} · {players.length} players</h4><ol>{players.map(p => <li key={p.key}>{p.player} <span className="muted">(S)</span>{p.sport.toLowerCase() === 'badminton' && <label style={{display:'block',maxWidth:280}}>Permanent court <select aria-label={'Permanent court for ' + p.player} value={p.court} disabled={!!moving} onChange={e => movePermanent(p,e.target.value)}><option value={p.court}>{p.court}</option>{Array.from({length:6},(_,i)=>'Court '+(i+1)).filter(v=>v!==p.court).map(v=><option key={v} value={v}>{v}</option>)}</select></label>}</li>)}</ol></div>)}
      </div>)}
      {!visible.length && <p className="muted">No approved Season assignments match the selected filters.</p>}
    </>}
  </section>;
}
