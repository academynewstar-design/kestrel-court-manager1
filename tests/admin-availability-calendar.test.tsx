// @vitest-environment jsdom
import {afterEach, beforeEach, expect, it, vi} from 'vitest';
import {cleanup, fireEvent, render, screen, waitFor} from '@testing-library/react';
const mock = vi.hoisted(() => ({range: vi.fn(), rpc: vi.fn()}));
vi.mock('../src/lib/supabase', () => ({supabase: {
  from: () => {const query: any = {select: () => query, gte: () => query, lte: () => query, order: () => query, range: mock.range}; return query;},
  rpc: mock.rpc,
}}));
import Calendar, {loadCalendarMonth, schoolCalendarDay, type CalendarSession} from '../src/AdminAvailabilityCalendar';

const locations = [{id: 1, name: 'Ange Gabriel', city: 'Mississauga'}, {id: 2, name: 'Carrefour', city: 'Brampton'}];
const sports = [{id: 1, name: 'badminton'}, {id: 2, name: 'volleyball'}];
const session: CalendarSession = {id: 1, location_id: 1, sport_id: 2, session_date: '2026-10-26', start_time: '18:30:00', end_time: '21:00:00', availability_status: 'available', sports: {name: 'volleyball'}};
beforeEach(() => {vi.useFakeTimers({toFake: ['Date']}); vi.setSystemTime(new Date('2026-10-20T15:00:00Z')); mock.range.mockReset().mockResolvedValue({data: [session], error: null}); mock.rpc.mockReset().mockResolvedValue({error: null});});
afterEach(() => {cleanup(); vi.restoreAllMocks(); vi.useRealTimers();});

it('does not confuse a wrong sport filter with a school closure', () => {
  const result = schoolCalendarDay([session], locations, '2026-10-26', '1', 'ange');
  expect(result[0].status).toBe('no-session');
  expect(result[0].all[0].sports?.name).toBe('volleyball');
  expect(schoolCalendarDay([session], locations, '2026-10-26', '', 'mississauga')[0].status).toBe('available');
});

it('resolves closures across all sports and courts before optional filtering', () => {
  const closed = {...session, id: 2, sport_id: 1, availability_status: 'unavailable'};
  expect(schoolCalendarDay([session, closed], locations, '2026-10-26', '2')[0].status).toBe('unavailable');
  expect(schoolCalendarDay([session, closed], locations, '2026-10-27')[0].status).toBe('no-session');
});

it('loads all pages so later school/date results cannot be silently truncated', async () => {
  mock.range.mockResolvedValueOnce({data: Array.from({length: 500}, (_, id) => ({...session, id})), error: null})
    .mockResolvedValueOnce({data: [{...session, id: 501}], error: null});
  expect(await loadCalendarMonth('2026-10')).toHaveLength(501);
  expect(mock.range.mock.calls).toEqual([[0, 499], [500, 999]]);
});

it('opens a date directly with all sports and groups duplicate court times', async () => {
  mock.range.mockResolvedValue({data: [session, {...session, id: 2, court: 'Court 2'}], error: null});
  render(<Calendar locations={locations} sports={sports} revision={0} onChanged={vi.fn()} renderSession={s => <p key={s.id}>Court details {s.id}</p>}/>);
  await waitFor(() => expect(screen.queryByText('Loading school availability…')).toBeNull());
  fireEvent.click(screen.getByRole('button', {name: /Monday, October 26, 2026/}));
  expect(screen.getByText('Available', {selector: '.calendar-status'})).toBeTruthy();
  expect(screen.getAllByText(/volleyball · 6:30/)).toHaveLength(1);
  expect(screen.queryByLabelText('Start time')).toBeNull();
  expect(screen.queryByRole('button', {name: /Search sessions/})).toBeNull();
  expect(screen.getByText('No session scheduled (1 school)')).toBeTruthy();
});

it('changes the selected school/date only after confirmation and reports save errors', async () => {
  const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
  mock.rpc.mockResolvedValue({error: {message: 'Save failed'}});
  render(<Calendar locations={locations} sports={sports} revision={0} onChanged={vi.fn()} renderSession={() => null}/>);
  await waitFor(() => expect(screen.queryByText('Loading school availability…')).toBeNull());
  fireEvent.change(screen.getByLabelText('Go to date'), {target: {value: '2026-10-26'}});
  fireEvent.click(screen.getByRole('button', {name: 'Mark school unavailable'}));
  expect(mock.rpc).not.toHaveBeenCalled();
  confirm.mockReturnValue(true);
  fireEvent.click(screen.getByRole('button', {name: 'Mark school unavailable'}));
  await screen.findByText('Save failed');
  expect(mock.rpc).toHaveBeenCalledWith('admin_set_school_availability', {p_location_name: 'Ange Gabriel', p_session_date: '2026-10-26', p_availability: 'unavailable'});
  expect(screen.queryByText(/Ange Gabriel · Monday/)).toBeNull();
});

it('shows an error instead of falsely reporting no sessions when a page fails', async () => {
  mock.range.mockResolvedValue({data: null, error: {message: 'Calendar could not load'}});
  render(<Calendar locations={locations} sports={sports} revision={0} onChanged={vi.fn()} renderSession={() => null}/>);
  await screen.findByText('Calendar could not load');
  expect(screen.queryByText(/No sessions scheduled for/)).toBeNull();
  expect(screen.getByRole('button', {name: 'Retry calendar'})).toBeTruthy();
});
