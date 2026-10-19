// @vitest-environment jsdom
import {afterEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup} from '@testing-library/react';
import {ExclusiveCourtList,RosterCourtControl,exclusiveCourtText} from '../src/ActivityRosterTools';
afterEach(cleanup);
describe('Activity roster court tools',()=>{
 it('shows the reserved court and named group even without player registrations',()=>{
  const booking={id:1,session_id:42,lead_name:'Ankit',guest_count:4};
  render(<ExclusiveCourtList bookings={[booking]} sessionCourts={{42:'Court 3'}}/>);
  expect(screen.getByText('Court 3 · Ankit + 4 guests · Entire court reserved')).toBeTruthy();
  expect(exclusiveCourtText(booking,'Court 3')).toContain('Ankit + 4 guests');
 });
 it('lets a Drop-in player choose a court and save it',()=>{
  const change=vi.fn(),save=vi.fn();
  render(<RosterCourtControl name="Drop-in Player" courts={['Court 2','Court 3']} value="Court 2" busy={false} changed={true} onChange={change} onSave={save}/>);
  fireEvent.change(screen.getByRole('combobox'),{target:{value:'Court 3'}});
  expect(change).toHaveBeenCalledWith('Court 3');
  fireEvent.click(screen.getByRole('button',{name:'Save court'}));expect(save).toHaveBeenCalledOnce();
 });
 it('disables saves while a move is in progress',()=>{
  render(<RosterCourtControl name="Player" courts={['Court 2']} value="Court 2" busy={true} changed={true} onChange={()=>{}} onSave={()=>{}}/>);
  expect(screen.getByRole('button',{name:'Saving…'}).hasAttribute('disabled')).toBe(true);
 });
});
