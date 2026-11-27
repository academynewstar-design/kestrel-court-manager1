// @vitest-environment jsdom
import React from 'react';
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,cleanup,waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {AdminTournaments} from '../src/Tournaments';
const mocks=vi.hoisted(()=>({from:vi.fn(),rpc:vi.fn()}));
vi.mock('../src/lib/supabase',()=>({supabase:mocks}));
const event={id:1,title:'Old Basketball Tournament',city:'Brampton',sports:{name:'basketball'},starts_at:'2026-10-30T22:00:00Z',individual_fee:7,team_fee:30,minimum_age:16,location_details:'Gym',payment_email:null,status:'open'};
let deleted=false;
beforeEach(()=>{
 deleted=false;vi.clearAllMocks();vi.spyOn(window,'confirm').mockReturnValue(true);
 mocks.from.mockImplementation((table:string)=>{const q:any={select:()=>q,is:()=>q,order:()=>q,then:(resolve:any)=>Promise.resolve({data:table==='tournament_events'&&!deleted?[event]:[],error:null}).then(resolve)};return q});
 mocks.rpc.mockImplementation(async()=>{deleted=true;return {data:null,error:null}});
});
afterEach(()=>{cleanup();vi.restoreAllMocks()});
async function selectEvent(){await userEvent.selectOptions(await screen.findByLabelText('Tournament'),'1');}
describe('Admin tournament deletion',()=>{
 it('confirms removal and refreshes lists after success',async()=>{
  render(<AdminTournaments/>);await selectEvent();await userEvent.click(screen.getByRole('button',{name:'Delete tournament'}));
  expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining('Old Basketball Tournament'));
  expect(mocks.rpc).toHaveBeenCalledWith('admin_delete_tournament',{p_event_id:1});
  await screen.findByText('Tournament deleted from tournament lists.');expect(screen.queryByRole('option',{name:/Old Basketball Tournament/})).toBeNull();
 });
 it('does nothing if the administrator cancels confirmation',async()=>{
  vi.mocked(window.confirm).mockReturnValue(false);render(<AdminTournaments/>);await selectEvent();await userEvent.click(screen.getByRole('button',{name:'Delete tournament'}));
  expect(mocks.rpc).not.toHaveBeenCalled();expect(screen.getByRole('option',{name:/Old Basketball Tournament/})).toBeTruthy();
 });
 it('keeps the tournament visible and reports a failed deletion',async()=>{
  mocks.rpc.mockResolvedValue({data:null,error:{message:'Admin access required'}});render(<AdminTournaments/>);await selectEvent();await userEvent.click(screen.getByRole('button',{name:'Delete tournament'}));
  await waitFor(()=>expect(screen.getByRole('status').textContent).toContain('Admin access required'));expect(screen.getByRole('option',{name:/Old Basketball Tournament/})).toBeTruthy();
 });
});
