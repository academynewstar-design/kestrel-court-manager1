// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,waitFor,cleanup} from '@testing-library/react';
const rpc=vi.hoisted(()=>vi.fn());
vi.mock('../src/lib/supabase',()=>({supabase:{rpc}}));
import RemoveSeasonSession from '../src/RemoveSeasonSession';
beforeEach(()=>{rpc.mockReset();rpc.mockResolvedValue({data:4,error:null});vi.spyOn(window,'confirm').mockReturnValue(true)});
afterEach(()=>{cleanup();vi.restoreAllMocks()});
describe('Remove approved Season session',()=>{
 it('confirms the recurring removal and refreshes the profile after success',async()=>{
  const removed=vi.fn();render(<RemoveSeasonSession scheduleId={42} label="Monday Badminton" onRemoved={removed}/>);
  fireEvent.click(screen.getByRole('button',{name:'Remove Season session'}));
  expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining('all upcoming games'));
  expect(rpc).toHaveBeenCalledWith('remove_my_season_choice',{p_recurring_schedule_id:42});
  await waitFor(()=>expect(removed).toHaveBeenCalledOnce());
 });
 it('leaves the session alone when confirmation is cancelled',()=>{
  vi.mocked(window.confirm).mockReturnValue(false);
  render(<RemoveSeasonSession scheduleId={42} label="Monday" onRemoved={()=>{}}/>);
  fireEvent.click(screen.getByRole('button'));expect(rpc).not.toHaveBeenCalled();
 });
 it('keeps the choice visible when the server rejects removal',async()=>{
  const removed=vi.fn();rpc.mockResolvedValue({error:{message:'Choose one of your approved Season sessions'}});
  render(<RemoveSeasonSession scheduleId={42} label="Monday" onRemoved={removed}/>);
  fireEvent.click(screen.getByRole('button'));
  expect((await screen.findByRole('alert')).textContent).toContain('approved Season sessions');expect(removed).not.toHaveBeenCalled();
 });
});
