// @vitest-environment jsdom
import React from 'react';
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,cleanup,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Tournaments,{entryFee} from '../src/Tournaments';
const mock=vi.hoisted(()=>({from:vi.fn(),insert:vi.fn(),update:vi.fn()}));
vi.mock('../src/lib/supabase',()=>({supabase:{from:mock.from}}));
const event={id:1,title:'Brampton Basketball Tournament',city:'Brampton',sports:{name:'basketball'},starts_at:'2099-10-30T22:00:00Z',individual_fee:7,team_fee:30,minimum_age:16,location_details:'Inbox for location details',payment_email:null,status:'open'};
let entries:any[]=[];
let failure:string|null=null;
function query(table:string){let mutation=false;const q:any={select:()=>q,eq:()=>q,order:()=>q,single:()=>q,
 insert:(value:any)=>{mutation=true;mock.insert(value);if(!failure)entries=[{...value,id:1,payment_status:'unpaid'}];return q},
 update:(value:any)=>{mutation=true;mock.update(value);if(!failure)entries=entries.map(e=>({...e,...value}));return q},
 then:(resolve:any)=>Promise.resolve({data:mutation?{id:1}:table==='tournament_events'?[event]:entries,error:failure?{message:failure}:null}).then(resolve)};return q;}
beforeEach(()=>{entries=[];failure=null;vi.clearAllMocks();mock.from.mockImplementation(query);vi.spyOn(window,'confirm').mockReturnValue(true)});
afterEach(()=>{cleanup();vi.restoreAllMocks()});
const profile={id:'owner',full_name:'Jordan Player'};
describe('Tournament registration',()=>{
 it('requires age confirmation and saves a $7 individual entry',async()=>{
  const user=userEvent.setup();render(<Tournaments profile={profile}/>);
  const submit=await screen.findByRole('button',{name:'Register individually'});
  expect((submit as HTMLButtonElement).disabled).toBe(true);
  expect(screen.getByText(/6:00 p.m./)).toBeTruthy();
  await user.click(screen.getByRole('checkbox'));await user.click(submit);
  await screen.findByText('My tournament entry');
  expect(mock.insert).toHaveBeenCalledWith(expect.objectContaining({entry_kind:'individual',player_names:['Jordan Player'],team_name:null,eligibility_confirmed:true}));
  expect(entryFee(event,'individual')).toBe(7);
 });
 it('charges $30 once for a team and records all names',async()=>{
  const user=userEvent.setup();render(<Tournaments profile={profile}/>);
  await user.selectOptions(await screen.findByLabelText('Entry type'),'team');
  await user.type(screen.getByLabelText('Team name'),'Blue');
  await user.type(screen.getByLabelText(/Player names/),'Jordan Player\nTaylor Player\nAlex Player');
  expect((screen.getByRole('button',{name:'Register team'}) as HTMLButtonElement).disabled).toBe(true);
  await user.click(screen.getByRole('checkbox'));await user.click(screen.getByRole('button',{name:'Register team'}));
  await screen.findByText('My tournament entry');
  expect(mock.insert).toHaveBeenCalledWith(expect.objectContaining({entry_kind:'team',team_name:'Blue',player_names:['Jordan Player','Taylor Player','Alex Player']}));
  expect(entryFee(event,'team')).toBe(30);
  expect(screen.getByText('$30 for the whole team')).toBeTruthy();
 });
 it('keeps a paid entry paid when cancelled and rejoined',async()=>{
  entries=[{id:1,event_id:1,user_id:'owner',entry_kind:'individual',player_names:['Jordan Player'],status:'registered',payment_status:'paid'}];
  const user=userEvent.setup();render(<Tournaments profile={profile}/>);
  await user.click(await screen.findByRole('button',{name:'Cancel tournament entry'}));
  await user.click(await screen.findByRole('button',{name:'Rejoin tournament'}));
  await screen.findByRole('button',{name:'Paid ✓'});
  expect(mock.update.mock.calls.map(c=>c[0])).toEqual([{status:'cancelled'},{status:'registered'}]);
 });
 it('reports a failed save without showing a registration confirmation',async()=>{
  const user=userEvent.setup();render(<Tournaments profile={profile}/>);
  await user.click(await screen.findByRole('checkbox'));failure='Registration is closed';
  await user.click(screen.getByRole('button',{name:'Register individually'}));
  await waitFor(()=>expect(screen.getByRole('alert').textContent).toContain('Registration is closed'));
  expect(screen.queryByText('My tournament entry')).toBeNull();
 });
});
