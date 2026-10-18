// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
const rpc=vi.hoisted(()=>vi.fn());
vi.mock('../src/lib/supabase',()=>({supabase:{rpc}}));
import {GroupRequestButton,AdminGroupApprovals,collapseGroupRoster,type DropinGroup} from '../src/DropinGroups';
const session={id:42,session_date:'2099-06-02',start_time:'18:00:00',end_time:'20:00:00',price:6,sports:{name:'volleyball'},locations:{name:'Test School'}};
const group:DropinGroup={id:7,owner_id:'tim',owner_name:'Tim',session_id:42,guest_names:['Alex Alpha','Blake Beta','Casey Gamma'],total_people:4,status:'pending',expires_at:'2099-06-01T18:00:00Z',review_note:null,unit_price:6,total_price:24,credit_paid:0,amount_due:24,session_date:'2099-06-02',start_time:'18:00:00',end_time:'20:00:00',sport:'volleyball',location:'Test School',court:'General',member_ids:['tim','a','b','c']};
beforeEach(()=>{rpc.mockReset();rpc.mockResolvedValue({data:[],error:null});HTMLDialogElement.prototype.showModal=function(){this.open=true};HTMLDialogElement.prototype.close=function(){this.open=false}});
afterEach(cleanup);
describe('Group Drop-in booking',()=>{
 it('submits ten people including the organiser, with nine guests',async()=>{
  const user=userEvent.setup();const saved=vi.fn();
  render(<GroupRequestButton session={session} availability={{occupied:0,total_capacity:12}} registered={false} level="intermediate" requests={[]} onSaved={saved}/>);
  await user.click(screen.getByRole('button',{name:'Book for a group'}));
  fireEvent.change(screen.getByRole('spinbutton'),{target:{value:'10'}});
  const names=Array.from({length:9},(_,i)=>'Guest '+String.fromCharCode(65+i));
  names.forEach((name,i)=>fireEvent.change(screen.getByLabelText('Guest '+(i+1)+': real name'),{target:{value:name}}));
  await user.click(screen.getByRole('checkbox'));
  expect(screen.getByText('$60.00 for the whole group')).toBeTruthy();
  await user.click(screen.getByRole('button',{name:'Request 10 spots'}));
  await waitFor(()=>expect(rpc).toHaveBeenCalledWith('request_dropin_group',{p_session_id:42,p_guest_names:names,p_level:'intermediate',p_eligible:true}));
  expect(saved).toHaveBeenCalled();
  expect(screen.getByRole('status').textContent).toContain('only after Admin approval');
 });
 it('prevents a request larger than capacity and credits an existing organiser spot in the limit',async()=>{
  const user=userEvent.setup();
  render(<GroupRequestButton session={session} availability={{occupied:8,total_capacity:12}} registered={true} level="intermediate" requests={[]} onSaved={()=>{}}/>);
  await user.click(screen.getByRole('button',{name:'Add guests — Admin approval'}));
  expect(screen.getByRole('spinbutton').getAttribute('max')).toBe('5');
  fireEvent.change(screen.getByRole('spinbutton'),{target:{value:'10'}});
  expect(screen.getByRole('button',{name:'Request 10 spots'}).hasAttribute('disabled')).toBe(true);
  expect(rpc).not.toHaveBeenCalled();
 });
 it('requires admin eligibility confirmation before approval',async()=>{
  const user=userEvent.setup();
  rpc.mockImplementation((name:string)=>Promise.resolve({data:name==='list_dropin_groups'?[group]:null,error:null}));
  render(<AdminGroupApprovals/>);
  const approve=await screen.findByRole('button',{name:'Approve 4 people'});
  expect(approve.hasAttribute('disabled')).toBe(true);
  await user.click(screen.getByRole('checkbox'));
  expect(approve.hasAttribute('disabled')).toBe(false);
  await user.click(approve);
  await waitFor(()=>expect(rpc).toHaveBeenCalledWith('review_dropin_group',{p_request_id:7,p_approve:true,p_note:null}));
 });
 it('clears a previous fetch error when refreshing succeeds',async()=>{
  rpc.mockResolvedValueOnce({data:null,error:{message:'TypeError: Failed to fetch'}});
  render(<AdminGroupApprovals/>);
  expect((await screen.findByRole('alert')).textContent).toContain('Failed to fetch');
  rpc.mockResolvedValueOnce({data:[group],error:null});
  fireEvent.click(screen.getByRole('button',{name:'Refresh'}));
  await screen.findByRole('button',{name:'Approve 4 people'});
  expect(screen.queryByRole('alert')).toBeNull();
 });
 it('hides the recovered panel when there are no pending requests',async()=>{
  rpc.mockResolvedValueOnce({data:null,error:{message:'TypeError: Failed to fetch'}});
  render(<AdminGroupApprovals/>);
  await screen.findByRole('alert');
  fireEvent.click(screen.getByRole('button',{name:'Refresh'}));
  await waitFor(()=>expect(screen.queryByRole('alert')).toBeNull());
  expect(screen.queryByText(/Group Drop-in approvals/)).toBeNull();
 });
 it('shows Tim + 9 as one row while preserving ten occupied spots',()=>{
  const members=['tim',...Array.from({length:9},(_,i)=>'guest-'+i)];
  const rows=members.map((id,i)=>({id:i+1,user_id:id,session_id:42,status:'confirmed',payment_status:'paid',profiles:{full_name:id}}));
  const result=collapseGroupRoster(rows,[{...group,status:'approved',total_people:10,member_ids:members}]);
  expect(result).toHaveLength(1);expect(result[0].profiles.full_name).toBe('Tim + 9');expect(result[0].party_size).toBe(10);
  expect(collapseGroupRoster(rows,[group])).toHaveLength(10);
 });
});
