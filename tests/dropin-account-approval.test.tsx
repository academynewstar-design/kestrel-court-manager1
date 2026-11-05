// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup,waitFor} from '@testing-library/react';
const from=vi.hoisted(()=>vi.fn());
vi.mock('../src/lib/supabase',()=>({supabase:{from}}));
import {DropinApprovalGate,AdminDropinAccountApprovals,useDropinAccountApproval} from '../src/DropinAccountApproval';
afterEach(cleanup);beforeEach(()=>from.mockReset());
const approval=(status:string)=>({status,error:'',approved:status==='approved',refresh:vi.fn().mockResolvedValue(undefined)});
describe('Drop-in account approval',()=>{
 it.each(['loading','none','pending','rejected','error','approved'])('allows booking controls without first-time approval when %s',status=>{
  render(<DropinApprovalGate userId="player" approval={approval(status)}><button>Going</button></DropinApprovalGate>);
  expect(screen.getByRole('button',{name:'Going'})).toBeTruthy();
 });
 it('shows name and email and saves the admin decision',async()=>{
  const rows=[{user_id:'player',status:'pending',created_at:'2026-10-21T01:00:00Z',profiles:{full_name:'Test Player',email:'test@example.com'}}];
  const update=vi.fn(()=>({eq:()=>({select:()=>Promise.resolve({data:[{user_id:'player'}],error:null})})}));
  from.mockReturnValue({select:()=>({order:()=>Promise.resolve({data:rows,error:null})}),update});
  render(<AdminDropinAccountApprovals/>);
  expect(await screen.findByText('test@example.com')).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{name:'Approve Drop-in'}));
  await waitFor(()=>expect(update).toHaveBeenCalledWith({status:'approved'}));
  expect(await screen.findByRole('status')).toBeTruthy();
 });
 it('keeps booking available even when the legacy approval lookup fails',async()=>{
  from.mockReturnValue({select:()=>({eq:()=>({maybeSingle:()=>Promise.resolve({data:null,error:{message:'Connection failed'}})})})});
  function Harness(){const state=useDropinAccountApproval({id:'p',player_type:'dropin',player_type_status:'approved'});return <DropinApprovalGate userId="p" approval={state}><button>Going</button></DropinApprovalGate>}
  render(<Harness/>);expect(screen.getByRole('button',{name:'Going'})).toBeTruthy();
 });
});
