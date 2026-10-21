// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup,within,waitFor} from '@testing-library/react';
const rpc=vi.hoisted(()=>vi.fn());
vi.mock('../src/lib/supabase',()=>({supabase:{rpc}}));
import {AttendanceSheet} from '../src/ConvenorAttendance';
const activity={session_id:177,location:'Gaetan Gervais',city:'Oakville',sport:'badminton',session_date:'2026-10-21',start_time:'18:00:00',end_time:'20:00:00',confirmed_at:null};
const base={session_id:177,players:[
 {user_id:'present',player_name:'Present Player',court:'Court 2',kind:'Season',not_going:false},
 {user_id:'absent',player_name:'Absent Player',court:'Court 1',kind:'Drop-in',not_going:false},
 {user_id:'excused',player_name:'Excused Player',court:'Court 1',kind:'Season',not_going:true}
],marks:{},roster_token:'roster-version',revision:0,confirmed_at:null,no_show_count:null,report_queued:false,can_save:true,can_confirm:true};
beforeEach(()=>{rpc.mockReset();rpc.mockResolvedValue({data:base,error:null})});afterEach(cleanup);
describe('Convenor attendance',()=>{
 it('groups and sorts courts, and saves a draft without confirming',async()=>{
  render(<AttendanceSheet activity={activity}/>);await screen.findByText('Present Player');
  const groups=screen.getAllByRole('group');expect(within(groups[0]).getByText('Court 1')).toBeTruthy();
  fireEvent.click(screen.getByLabelText(/Present Player/));
  rpc.mockResolvedValueOnce({data:{...base,revision:1,marks:{present:true,absent:false,excused:false}},error:null});
  fireEvent.click(screen.getByRole('button',{name:'Save attendance'}));
  await screen.findByText('Attendance saved. No absence report has been sent.');
  expect(rpc).toHaveBeenLastCalledWith('save_convenor_attendance',{p_session_id:177,p_marks:{present:true,absent:false,excused:false},p_roster_token:'roster-version',p_revision:0,p_confirm:false});
 });
 it('requires explicit review, lists only unexcused absences and confirms once',async()=>{
  render(<AttendanceSheet activity={activity}/>);await screen.findByText('Present Player');
  fireEvent.click(screen.getByLabelText(/Present Player/));
  fireEvent.click(screen.getByRole('button',{name:'Review & confirm attendance'}));
  const list=screen.getByRole('list');expect(list.textContent).toContain('Absent Player');expect(list.textContent).not.toContain('Excused Player');
  expect(screen.getByRole('button',{name:'Confirm attendance'}).hasAttribute('disabled')).toBe(true);
  fireEvent.click(screen.getByLabelText(/I reviewed every court/));
  rpc.mockResolvedValueOnce({data:{...base,marks:{present:true,absent:false,excused:false},revision:1,confirmed_at:'2026-10-22T01:00:00Z',no_show_count:1,report_queued:true},error:null});
  fireEvent.click(screen.getByRole('button',{name:'Confirm attendance'}));
  await screen.findByText(/report queued for academynewstar/);expect(screen.queryByRole('button',{name:'Confirm attendance'})).toBeNull();
  expect(rpc.mock.calls.filter(c=>c[0]==='save_convenor_attendance')).toHaveLength(1);
 });
 it('disables final confirmation before the session ends',async()=>{
  rpc.mockResolvedValue({data:{...base,can_confirm:false},error:null});render(<AttendanceSheet activity={activity}/>);
  await screen.findByText('Present Player');expect(screen.getByRole('button',{name:'Review & confirm attendance'}).hasAttribute('disabled')).toBe(true);
 });
 it('preserves ticks and never reports success on a failed save',async()=>{
  render(<AttendanceSheet activity={activity}/>);await screen.findByText('Present Player');fireEvent.click(screen.getByLabelText(/Present Player/));
  rpc.mockResolvedValueOnce({data:null,error:{message:'Roster changed. Reload before saving.'}});fireEvent.click(screen.getByRole('button',{name:'Save attendance'}));
  await screen.findByRole('alert');expect((screen.getByLabelText(/Present Player/) as HTMLInputElement).checked).toBe(true);expect(screen.queryByText(/Attendance saved/)).toBeNull();
 });
 it('prevents duplicate submissions while confirmation is in flight',async()=>{
  render(<AttendanceSheet activity={activity}/>);await screen.findByText('Present Player');fireEvent.click(screen.getByRole('button',{name:'Review & confirm attendance'}));fireEvent.click(screen.getByLabelText(/I reviewed every court/));
  let finish:any;rpc.mockReturnValueOnce(new Promise(r=>{finish=r}));fireEvent.click(screen.getByRole('button',{name:'Confirm attendance'}));
  expect(screen.getByRole('button',{name:'Confirming…'}).hasAttribute('disabled')).toBe(true);
  finish({data:{...base,confirmed_at:'2026-10-22T01:00:00Z'},error:null});await waitFor(()=>expect(screen.queryByRole('button',{name:'Confirming…'})).toBeNull());
 });
});
