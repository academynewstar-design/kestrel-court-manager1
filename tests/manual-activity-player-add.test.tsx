// @vitest-environment jsdom
import {afterEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup,waitFor} from '@testing-library/react';
import ManualActivityPlayerAdd from '../src/ManualActivityPlayerAdd';
const {rpc}=vi.hoisted(()=>({rpc:vi.fn()}));
vi.mock('../src/lib/supabase',()=>({supabase:{rpc}}));
afterEach(()=>{cleanup();vi.resetAllMocks()});
const players=[{id:'ankit-id',full_name:'Ankit',email:'ankit@example.com'}];
const courts=[{id:42,name:'Court 2',reserved:false},{id:43,name:'Court 3',reserved:true}];
function choosePlayer(){fireEvent.change(screen.getByRole('textbox',{name:'Search player name or email'}),{target:{value:'Ankit'}});fireEvent.change(screen.getByRole('combobox',{name:'Select player to add'}),{target:{value:'ankit-id'}})}
function chooseCourt(){fireEvent.change(screen.getByLabelText('Booking type'),{target:{value:'court'}});fireEvent.change(screen.getByLabelText('Court to reserve'),{target:{value:'42'}})}
describe('manual activity additions',()=>{
 it('reserves the chosen court for the selected player and guests without an individual registration',async()=>{
  rpc.mockResolvedValue({data:'booked',error:null});const refresh=vi.fn().mockResolvedValue(undefined);
  render(<ManualActivityPlayerAdd activitySessionId={1} players={players} courts={courts} allowFullCourt onSaved={refresh}/>);
  choosePlayer();chooseCourt();fireEvent.click(screen.getByRole('button',{name:'Reserve entire court'}));
  await waitFor(()=>expect(refresh).toHaveBeenCalledOnce());
  expect(rpc).toHaveBeenCalledExactlyOnceWith('admin_manage_exclusive_court_booking',{p_session_id:42,p_lead_name:'Ankit',p_guest_count:4,p_action:'book'});
  expect(screen.getByRole('status').textContent).toBe('Court 2 reserved for Ankit + 4 guests.');
 });
 it('keeps the selection and shows the server conflict when a court already has players',async()=>{
  rpc.mockResolvedValue({error:{message:'This court already has players assigned'}});const refresh=vi.fn();
  render(<ManualActivityPlayerAdd activitySessionId={1} players={players} courts={courts} allowFullCourt onSaved={refresh}/>);
  choosePlayer();chooseCourt();fireEvent.click(screen.getByRole('button',{name:'Reserve entire court'}));
  await waitFor(()=>expect(screen.getByRole('status').textContent).toContain('already has players'));
  expect(refresh).not.toHaveBeenCalled();expect((screen.getByLabelText('Court to reserve') as HTMLSelectElement).value).toBe('42');
  expect(screen.getByRole('option',{name:'Court 3 — already reserved'}).hasAttribute('disabled')).toBe(true);
 });
 it('rejects fractional and empty guest counts',()=>{
  render(<ManualActivityPlayerAdd activitySessionId={1} players={players} courts={courts} allowFullCourt onSaved={vi.fn()}/>);
  choosePlayer();chooseCourt();const guests=screen.getByRole('spinbutton');
  for(const value of ['1.5','', '-1','31']){fireEvent.change(guests,{target:{value}});expect(screen.getByRole('button',{name:'Reserve entire court'}).hasAttribute('disabled')).toBe(true)}
  expect(rpc).not.toHaveBeenCalled();
 });
 it('preserves individual additions and waitlist feedback for other activities',async()=>{
  rpc.mockResolvedValue({data:'waitlist',error:null});const refresh=vi.fn().mockResolvedValue(undefined);
  render(<ManualActivityPlayerAdd activitySessionId={1} players={players} courts={courts} allowFullCourt={false} onSaved={refresh}/>);
  expect(screen.queryByLabelText('Booking type')).toBeNull();choosePlayer();fireEvent.click(screen.getByRole('button',{name:'Add Player to Activity'}));
  await waitFor(()=>expect(refresh).toHaveBeenCalledOnce());
  expect(rpc).toHaveBeenCalledExactlyOnceWith('admin_add_player_to_activity',{p_session_id:1,p_user_id:'ankit-id'});
  expect(screen.getByRole('status').textContent).toContain('waitlist');
 });
});
