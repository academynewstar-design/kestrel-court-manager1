// @vitest-environment jsdom
import {afterEach, expect, it, vi} from 'vitest';
import {cleanup, fireEvent, render, screen} from '@testing-library/react';
import SchoolScheduleResults, {schoolScheduleResults} from '../src/SchoolScheduleResults';

afterEach(cleanup);
const base = {location_id: 1, sport_id: 1, session_date: '2026-10-23', start_time: '19:45:00', locations: {name: 'Carrefour Des Jeunes'}};
const sessions = [
  {...base, id: 1, availability_status: 'unavailable'},
  {...base, id: 2, availability_status: 'unavailable'},
  {...base, id: 3, availability_status: 'unavailable'},
  {...base, id: 4, availability_status: 'available'},
];
const filters = {sport: '', location: '1', date: '2026-10-23', time: ''};

it('replaces mixed court schedules with one closure message and one restore action', () => {
  const restore = vi.fn(), renderSession = vi.fn();
  render(<SchoolScheduleResults sessions={sessions} filters={filters} onRestore={restore} renderSession={renderSession}/>);
  expect(screen.getAllByText('School not available on this day')).toHaveLength(1);
  expect(screen.getByText('Carrefour Des Jeunes · October 23, 2026')).toBeTruthy();
  expect(renderSession).not.toHaveBeenCalled();
  expect(screen.queryByText('No upcoming sessions match your search.')).toBeNull();
  fireEvent.click(screen.getByRole('button', {name: '✓ Mark School Available'}));
  expect(restore).toHaveBeenCalledOnce();
  expect(restore.mock.calls[0][0].location_id).toBe(1);
});

it('resolves school closures even when sport and time filters only match an available court', () => {
  const other = {...base, id: 5, sport_id: 2, start_time: '18:00:00', availability_status: 'available'};
  const result = schoolScheduleResults([...sessions, other], {...filters, sport: '2', time: '18:00'});
  expect(result.closures).toHaveLength(1);
  expect(result.available).toHaveLength(0);
});

it('keeps other dates and schools available and restores all court results after reopening', () => {
  const nextDay = {...base, id: 5, session_date: '2026-10-26', availability_status: 'available'};
  const otherSchool = {...base, id: 6, location_id: 2, availability_status: 'available'};
  const result = schoolScheduleResults([...sessions, nextDay, otherSchool], {...filters, location: '', date: ''});
  expect(result.closures).toHaveLength(1);
  expect(result.available.map(s => s.id)).toEqual([5, 6]);
  const reopened = schoolScheduleResults(sessions.map(s => ({...s, availability_status: 'available'})), filters);
  expect(reopened.closures).toHaveLength(0);
  expect(reopened.available).toHaveLength(4);
});

it('shows the empty state only when no school or session matches', () => {
  render(<SchoolScheduleResults sessions={sessions} filters={{...filters, date: '2026-10-24'}} onRestore={vi.fn()} renderSession={vi.fn()}/>);
  expect(screen.getByText('No upcoming sessions match your search.')).toBeTruthy();
  expect(screen.queryByRole('status')).toBeNull();
});
