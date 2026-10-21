// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
const insert=vi.hoisted(()=>vi.fn());
vi.mock('../src/lib/supabase',()=>({supabase:{from:(table:string)=>{if(table!=='absence_reports')throw new Error('Unexpected table');return {insert}}}}));
import ReportAbsence from '../src/ReportAbsence';
afterEach(cleanup);beforeEach(()=>{insert.mockReset();insert.mockResolvedValue({error:null})});
function fill(){
 fireEvent.change(screen.getByLabelText('Absent player’s name'),{target:{value:' Alex Player '}});
 fireEvent.change(screen.getByLabelText('Location / school'),{target:{value:' Test School '}});
 fireEvent.change(screen.getByLabelText('Session date'),{target:{value:'2026-10-20'}});
 fireEvent.change(screen.getByLabelText('Session / time'),{target:{value:' Badminton 6–7:45 PM '}});
 fireEvent.change(screen.getByLabelText('Court / team'),{target:{value:' Court 3 '}});
 fireEvent.change(screen.getByLabelText('Additional details (optional)'),{target:{value:' Not present tonight. '}});
}
describe('Report Absence',()=>{
 it('requires all game details before submitting',()=>{
  render(<ReportAbsence profile={{id:'reporter'}} sessions={[]}/>);
  expect(screen.getByRole('button',{name:'Send absence report'}).hasAttribute('disabled')).toBe(true);
  fill();expect(screen.getByRole('button',{name:'Send absence report'}).hasAttribute('disabled')).toBe(false);
 });
 it('records the reporter and trimmed details, queues the email and clears only player-specific fields',async()=>{
  const user=userEvent.setup();render(<ReportAbsence profile={{id:'reporter'}} sessions={[]}/>);fill();
  await user.click(screen.getByRole('button',{name:'Send absence report'}));
  expect(insert).toHaveBeenCalledWith({reporter_id:'reporter',player_name:'Alex Player',location:'Test School',court:'Court 3',session_date:'2026-10-20',session_label:'Badminton 6–7:45 PM',notes:'Not present tonight.'});
  expect((await screen.findByRole('status')).textContent).toContain('academynewstar@gmail.com');
  expect((screen.getByLabelText('Absent player’s name') as HTMLInputElement).value).toBe('');
  expect((screen.getByLabelText('Court / team') as HTMLInputElement).value).toBe(' Court 3 ');
 });
 it.each([{code:'23505',message:'duplicate'},{message:'Connection failed'}])('does not show success when saving fails: %j',async(error)=>{
  insert.mockResolvedValue({error});render(<ReportAbsence profile={{id:'reporter'}} sessions={[]}/>);fill();
  fireEvent.click(screen.getByRole('button',{name:'Send absence report'}));
  await screen.findByRole('alert');expect(screen.queryByRole('status')).toBeNull();
  expect((screen.getByLabelText('Absent player’s name') as HTMLInputElement).value).toBe(' Alex Player ');
 });
 it('blocks double submissions while the first request is in flight',async()=>{
  let resolve:any;insert.mockReturnValue(new Promise(r=>{resolve=r}));render(<ReportAbsence profile={{id:'reporter'}} sessions={[]}/>);fill();
  fireEvent.click(screen.getByRole('button',{name:'Send absence report'}));
  expect(screen.getByRole('button',{name:'Submitting…'}).hasAttribute('disabled')).toBe(true);expect(insert).toHaveBeenCalledTimes(1);
  resolve({error:null});await waitFor(()=>expect(screen.getByRole('status')).toBeTruthy());
 });
});
