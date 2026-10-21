// @vitest-environment jsdom
import React from 'react';
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,within,waitFor,cleanup} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import FamilyManager,{AdminFamilyApprovals} from '../src/FamilyManager';
import App from '../src/App';
const mock=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),getSession:vi.fn()}));
vi.mock('../src/lib/supabase',()=>({supabase:{rpc:mock.rpc,from:mock.from,auth:{getSession:mock.getSession,onAuthStateChange:()=>({data:{subscription:{unsubscribe:()=>{}}}})}}}));
const owner={id:'owner',full_name:'Morgan Parent',player_type:'permanent',requested_player_type:'permanent',player_type_status:'approved',name_review_status:'approved',preferred_name_completed:true,whatsapp_contact_completed:true};
const schedule={id:1,weekday:'Monday',schedule_label:'Monday 6–7:45 PM',sports:{name:'badminton'},locations:{name:'David Saint Jacques',city:'Kitchener'}};
let members:any[]=[];
let profile:any=owner;
function query(result:any){const q:any={then:(resolve:any)=>Promise.resolve(result).then(resolve)};for(const k of ['select','eq','order','gte','limit','in','not','or','single','maybeSingle'])q[k]=()=>q;return q;}
beforeEach(()=>{
 members=[];profile=owner;vi.clearAllMocks();window.localStorage.clear();
 mock.from.mockImplementation((table:string)=>query({data:table==='profiles'?profile:table==='recurring_schedules'?[schedule]:[],error:null}));
 mock.getSession.mockResolvedValue({data:{session:{user:{id:'owner'}}}});
 mock.rpc.mockImplementation(async(name:string,args:any)=>{
  if(name==='get_my_family')return {data:structuredClone(members),error:null};
  if(name==='save_my_family_member'){
   members=[{id:'child',full_name:args.p_name,relationship:args.p_relationship,age_years:args.p_age,name_status:'approved',account_status:'approved',choices:[],sessions:[]}];return {data:'child',error:null};
  }
  if(name==='save_my_family_season_choices'){
   members[0].choices=[{id:4,schedule_id:1,court:'Court 1',level:'intermediate',status:'pending',weekday:'Monday',label:schedule.schedule_label,sport:'badminton',location:'David Saint Jacques',city:'Kitchener'}];return {data:null,error:null};
  }
  if(name==='set_my_family_attendance'){
   members[0].sessions[0].not_coming=args.p_not_coming;return {data:args.p_not_coming?'not_attending':'confirmed',error:null};
  }
  return {data:[],error:null};
 });
});
afterEach(()=>cleanup());
describe('Family registration',()=>{
 it('requires consent, saves child separately, submits their choices and toggles only their attendance',async()=>{
  const user=userEvent.setup();vi.spyOn(window,'confirm').mockReturnValue(true);
  render(<FamilyManager/>);
  await user.click(await screen.findByRole('button',{name:'Add family member',exact:true}));
  await user.type(screen.getByLabelText('Real first and last name'),'Alex Parent');
  await user.type(screen.getByLabelText('Age in years'),'12');
  expect((screen.getByRole('button',{name:'Save family member'}) as HTMLButtonElement).disabled).toBe(true);
  await user.click(screen.getByRole('checkbox',{name:/I am this child's/}));
  await user.click(screen.getByRole('button',{name:'Save family member'}));
  await screen.findByRole('heading',{name:'Choose Season sessions for Alex Parent'});
  expect(mock.rpc).toHaveBeenCalledWith('save_my_family_member',{p_member_id:null,p_name:'Alex Parent',p_relationship:'child',p_age:12,p_consent:true});
  await user.click(screen.getByRole('button',{name:'Choose',exact:true}));
  await user.selectOptions(screen.getByLabelText('Player level'),'intermediate');
  expect((screen.getByRole('button',{name:'Submit family Season request'}) as HTMLButtonElement).disabled).toBe(true);
  await user.click(screen.getByRole('checkbox',{name:/I confirm Season payment/}));
  await user.click(screen.getByRole('button',{name:'Submit family Season request'}));
  await screen.findByText('Pending Admin approval');
  expect(mock.rpc).toHaveBeenCalledWith('save_my_family_season_choices',{p_member_id:'child',p_choices:[{recurring_schedule_id:1,court:'Court 1',player_level:'intermediate',season_paid:true}]});
  members[0].sessions=[{id:7,date:'2099-01-01',start_time:'18:00',end_time:'19:45',court:'Court 1',sport:'badminton',location:'David Saint Jacques',city:'Kitchener',status:'confirmed',payment_status:'paid',not_coming:false}];
  await user.click(screen.getByRole('button',{name:'Refresh family'}));
  await user.click(await screen.findByRole('button',{name:'Not attending',exact:true}));
  await screen.findByRole('button',{name:'Going again'});
  expect(mock.rpc).toHaveBeenCalledWith('set_my_family_attendance',{p_member_id:'child',p_session_id:7,p_not_coming:true});
  await user.click(screen.getByRole('button',{name:'Going again'}));
  await screen.findByRole('button',{name:'Not attending',exact:true});
  expect(mock.rpc).toHaveBeenCalledWith('set_my_family_attendance',{p_member_id:'child',p_session_id:7,p_not_coming:false});
 });
 it('offers My Family to an existing season player',async()=>{
  const user=userEvent.setup();render(<App/>);
  await user.click(await screen.findByRole('button',{name:'👨‍👩‍👧 My Family'}));
  await screen.findByRole('heading',{name:'My Family',exact:true});
 });
 it('lets a new account register family without registering the account holder as a player',async()=>{
  profile={...owner,player_type:null,requested_player_type:null};const user=userEvent.setup();render(<App/>);
  await user.click(await screen.findByRole('button',{name:'Register a child / family member'}));
  await screen.findByRole('heading',{name:'My Family',exact:true});
 });
 it('requires an explicit eligibility and payment check for family approval',async()=>{
  const user=userEvent.setup();const reviewed=vi.fn();
  mock.rpc.mockImplementation(async(name:string)=>name==='get_pending_family_season_requests'?{data:[{id:1,member_name:'Alex Parent',age_years:12,name_status:'approved',owner_name:'Morgan Parent',owner_email:'parent@example.invalid',sport:'badminton',city:'Kitchener',location:'David Saint Jacques',weekday:'Monday',label:'6–7:45 PM',court:'Court 1',level:'intermediate'}],error:null}:{data:null,error:null});
  render(<AdminFamilyApprovals onReviewed={reviewed}/>);
  const approve=await screen.findByRole('button',{name:'Approve family request'});
  expect((approve as HTMLButtonElement).disabled).toBe(true);
  await user.click(screen.getByRole('checkbox',{name:/I checked that this person/}));
  await user.click(approve);
  await waitFor(()=>expect(reviewed).toHaveBeenCalledOnce());
  expect(mock.rpc).toHaveBeenCalledWith('admin_review_family_season_request',{p_request_id:1,p_approve:true,p_eligible:true});
 });
 it('shows a failed save and preserves the entered details for retry',async()=>{
  const user=userEvent.setup();const base=mock.rpc.getMockImplementation()!;
  mock.rpc.mockImplementation(async(name:string,args:any)=>name==='save_my_family_member'?{data:null,error:{message:'Connection interrupted'}}:base(name,args));
  render(<FamilyManager/>);await user.click(await screen.findByRole('button',{name:'Add family member',exact:true}));
  await user.type(screen.getByLabelText('Real first and last name'),'Alex Parent');await user.type(screen.getByLabelText('Age in years'),'12');
  await user.click(screen.getByRole('checkbox',{name:/I am this child's/}));await user.click(screen.getByRole('button',{name:'Save family member'}));
  expect((await screen.findByRole('alert')).textContent).toBe('Connection interrupted');
  expect((screen.getByLabelText('Real first and last name') as HTMLInputElement).value).toBe('Alex Parent');
 });
});
