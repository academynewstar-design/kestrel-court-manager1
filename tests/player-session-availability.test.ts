import {describe, expect, it} from 'vitest';
import {availablePlayerSessions} from '../src/playerSessionAvailability';

describe('player session availability', () => {
  it('applies a school closure to sibling courts and sports while keeping other dates and schools', () => {
    const rows = [
      {id: 1, location_id: 10, session_date: '2026-11-27', availability_status: 'unavailable'},
      {id: 2, location_id: 10, session_date: '2026-11-27', availability_status: 'available'},
      {id: 3, location_id: 10, session_date: '2026-12-02'},
      {id: 4, location_id: 11, session_date: '2026-11-27'},
      {id: 5, location_id: 11, session_date: '2026-12-02', status: 'closed'},
      {id: 6, location_id: 11, session_date: '2026-12-04', status: 'cancelled'},
    ];
    expect(availablePlayerSessions(rows).map(s => s.id)).toEqual([3, 4]);
    expect(availablePlayerSessions(rows.map(s => ({...s, availability_status: 'available'}))).map(s => s.id)).toEqual([1, 2, 3, 4]);
  });
});
