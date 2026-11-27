// @vitest-environment jsdom
import React from 'react';
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,cleanup,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import BadmintonTournamentCard from '../src/BadmintonTournament';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),insert:vi.fn(),update:vi.fn()}));
vi.mock('../src/lib/supabase',()=>({supabase:mocks}));
const event={id:2,title:'Kestrel Season Badminton Tournament',city:'Brampton',sports:{name:'badminton'},starts_at:'2027-02-07T14:00:00Z',individual_fee:25,team_fee:50,minimum_age:0,location_details:'Jeunes sans Frontières Secondary School',payment_email:null,status:'open',registration_format:'season_badminton_doubles'};
const profile={id:'owner',full_name:'Season Player'};
const players=[{id:'owner',full_name:'Season Player',can_register:true},{id:'partner',full_name:'Season Partner',can_register:false},{id:'other',full_name:'Other Player',can_register:false}];
let directory=players;
let allocation='waitlist';
let failure:string|null=null;
const saved=vi.fn(async()=>{});
beforeEach(()=>{
 directory=players;allocation='waitlist';failure=null;vi.clearAllMocks();vi.spyOn(window,'confirm').mockReturnValue(true);
 mocks.rpc.mockImplementation((name:string)=>Promise.resolve({data:name==='get_tournament_season_players'?directory:{entries:[{entry_id:1,allocation_status:allocation}]},error:null}));
 const q:any={insert:(payload:any)=>{mocks.insert(payload);return q},update:(payload:any)=>{mocks.update(payload);return q},select:()=>q,eq:()=>q,single:()=>Promise.resolve({data:{id:1},error:failure?{message:failure}:null})};
 mocks.from.mockReturnValue(q);
});
afterEach(()=>{cleanup();vi.restoreAllMocks()});
describe('Season badminton tournament',()=>{
 it('requires two Season identities, both allowed levels and partner consent',async()=>{
  const user=userEvent.setup();render(<BadmintonTournamentCard event={event} profile={profile} onSaved={saved}/>);
  const own=await screen.findByLabelText('Your name');
  expect(screen.getByText(/Maximum 10 Intermediate pairs and 10 Low Intermediate pairs/)).toBeTruthy();
  expect(screen.getByText(/\$25 per player/)).toBeTruthy();
  expect(screen.queryByRole('option',{name:'Advanced'})).toBeNull();
  expect((screen.getByRole('button',{name:'Register badminton pair'}) as HTMLButtonElement).disabled).toBe(true);
  await user.selectOptions(own,'owner');
  expect(Array.from((screen.getByLabelText('Partner name') as HTMLSelectElement).options).some(o=>o.value==='owner')).toBe(false);
  await user.selectOptions(screen.getByLabelText('Your level'),'intermediate');
  await user.selectOptions(screen.getByLabelText('Partner name'),'partner');
  await user.click(screen.getByRole('checkbox'));
  await user.click(screen.getByRole('button',{name:'Register badminton pair'}));
  await waitFor(()=>expect(saved).toHaveBeenCalled());
  expect(mocks.insert).toHaveBeenCalledWith(expect.objectContaining({player_id:'owner',partner_id:'partner',player_level:'intermediate',partner_level:'intermediate',entry_kind:'team',status:'registered'}));
  expect(saved.mock.calls[0][0]).toContain('waitlist');
 });
 it('blocks registration for a Drop-in account absent from eligible Season identities',async()=>{
  directory=players.filter(p=>p.id!=='owner');render(<BadmintonTournamentCard event={event} profile={profile} onSaved={saved}/>);
  await screen.findByText(/Registration is reserved for approved Kestrel Season players/);
  expect(screen.queryByLabelText('Your name')).toBeNull();
 });
 it('shows waitlist for an unpaid entry and requires full pair payment confirmation',async()=>{
  const user=userEvent.setup();render(<BadmintonTournamentCard event={event} profile={profile} entry={{id:1,event_id:2,user_id:'owner',entry_kind:'team',team_name:'Pair',player_names:['Season Player','Season Partner'],status:'registered',payment_status:'unpaid',player_level:'intermediate',partner_level:'low_intermediate'}} onSaved={saved}/>);
  await screen.findByText('Waitlisted');await user.click(screen.getByRole('button',{name:'Mark pair Paid'}));
  expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining('$50'));
  expect(mocks.update).toHaveBeenCalledWith({payment_status:'paid'});
 });
 it('does not label a paid waitlisted pair confirmed, and lets the partner view without editing',async()=>{
  render(<BadmintonTournamentCard event={event} profile={{id:'partner',full_name:'Season Partner'}} entry={{id:1,event_id:2,user_id:'owner',entry_kind:'team',team_name:'Pair',player_names:['Season Player','Season Partner'],status:'registered',payment_status:'paid'}} onSaved={saved}/>);
  await screen.findByText('Waitlisted');expect(screen.queryByText('Confirmed — paid')).toBeNull();
  expect(screen.queryByRole('button',{name:'Cancel pair entry'})).toBeNull();
 });
 it('shows confirmed only after the server allocates both paid places',async()=>{
  allocation='confirmed';render(<BadmintonTournamentCard event={event} profile={profile} entry={{id:1,event_id:2,user_id:'owner',entry_kind:'team',team_name:'Pair',player_names:['Season Player','Season Partner'],status:'registered',payment_status:'paid'}} onSaved={saved}/>);
  await screen.findByText('Confirmed — paid');
 });
});
