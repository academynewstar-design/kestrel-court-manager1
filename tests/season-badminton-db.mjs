// Optional isolated PostgreSQL check: provide PGLITE_MODULE or install @electric-sql/pglite.
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const db=new PGlite();
const root=fileURLToPath(new URL('../',import.meta.url));
await db.exec(`
 create role anon; create role authenticated; create schema auth;
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
 create table public.profiles(id uuid primary key,full_name text,email text,is_admin boolean default false,player_type text,player_type_status text,managed_by uuid);
 create function public.is_admin() returns boolean language sql stable as $$ select coalesce((select is_admin from public.profiles where id=auth.uid()),false) $$;
 create table public.sports(id bigserial primary key,name text unique, constraint sports_name_check check(name in ('badminton','volleyball','soccer','pickleball')));
 insert into sports(name) values('badminton');grant select on public.profiles,public.sports to authenticated;
`);
await db.exec(readFileSync(root+'supabase/features/tournament_registration.sql','utf8'));
await db.exec(readFileSync(root+'supabase/features/season_badminton_tournament.sql','utf8'));
await db.exec(readFileSync(root+'supabase/features/season_badminton_tournament_event.sql','utf8'));
const uid=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
for(let n=1;n<=46;n++)await db.query('insert into profiles(id,full_name,player_type,player_type_status) values($1,$2,$3,$4)',[uid(n),'Player '+n,n===46?'dropin':'permanent','approved']);
const eid=(await db.query("select id from tournament_events where slug='kestrel-season-badminton-2027-02-07'")).rows[0].id;
const event=(await db.query('select * from tournament_events where id=$1',[eid])).rows[0];
assert.equal(new Date(event.starts_at).toISOString(),'2027-02-07T14:00:00.000Z');assert.equal(Number(event.individual_fee),25);assert.equal(Number(event.team_fee),50);assert.equal(event.location_details,'Jeunes sans Frontières Secondary School');
const asPlayer=async(n,fn)=>{await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid(n)]);await db.exec('set role authenticated');try{return await fn()}finally{await db.exec('reset role')}};
const entry=async(a,b,level='intermediate',paid=false)=>asPlayer(a,async()=>{
 const row=(await db.query(`insert into tournament_entries(event_id,user_id,entry_kind,team_name,player_names,eligibility_confirmed,player_id,partner_id,player_level,partner_level) values($1,$2,'team','Pair',array['Client name','Client partner'],true,$2,$3,$4,$4) returning id`,[eid,uid(a),uid(b),level])).rows[0];
 if(paid)await db.query("update tournament_entries set payment_status='paid' where id=$1",[row.id]);return row.id;
});
const status=async n=>asPlayer(n,async()=>((await db.query('select public.get_badminton_tournament_status($1) as data',[eid])).rows[0].data));
// Unpaid pairs do not take confirmed places. Invalid identity, level and duplicate submissions fail.
const first=await entry(1,2);
assert.equal((await status(1)).entries[0].allocation_status,'waitlist');
await assert.rejects(()=>entry(3,46),/Both players must be approved Kestrel Season players/);
await assert.rejects(()=>entry(3,4,'advanced'),/Only Low Intermediate and Intermediate/);
await assert.rejects(()=>entry(3,3),/two different Season players/);
await assert.rejects(()=>asPlayer(3,()=>db.query("insert into tournament_entries(event_id,user_id,entry_kind,team_name,player_names,eligibility_confirmed,player_id,partner_id,player_level,partner_level) values($1,$2,'team','Pair',array['Aaa','Bbb'],true,$2,$3,'intermediate','low_intermediate')",[eid,uid(3),uid(4)])),/same level division/);
await assert.rejects(()=>entry(3,2),/already registered/);
await assert.rejects(()=>asPlayer(3,()=>db.query(`insert into tournament_entries(event_id,user_id,entry_kind,team_name,player_names,eligibility_confirmed,player_id,partner_id,player_level,partner_level) values($1,$2,'team','Pair',array['Aaa','Bbb'],true,$3,$4,'intermediate','intermediate')`,[eid,uid(3),uid(5),uid(6)])),/Choose your own name/);
const directory=await asPlayer(1,()=>db.query('select * from public.get_tournament_season_players()'));
assert.equal(directory.rows.length,45);assert.equal(directory.rows.find(p=>p.id===uid(1)).can_register,true);assert.equal(directory.rows.find(p=>p.id===uid(2)).can_register,false);assert.equal(directory.rows.some(p=>p.id===uid(46)),false);
await asPlayer(1,()=>db.query("update tournament_entries set payment_status='paid' where id=$1",[first]));
assert.equal((await status(2)).entries[0].allocation_status,'confirmed');
for(let n=3;n<=21;n+=2)await entry(n,n+1,'intermediate',true);
let current=await status(21);assert.equal(current.intermediate_confirmed,20);assert.equal(current.entries[0].allocation_status,'waitlist');
for(let n=23;n<=41;n+=2)await entry(n,n+1,'low_intermediate',true);
current=await status(23);assert.equal(current.low_intermediate_confirmed,20);assert.equal(current.intermediate_confirmed,20);
const lowWait=await entry(43,44,'low_intermediate',true);assert.equal((await status(43)).entries[0].allocation_status,'waitlist');
// A cancellation promotes the paid waitlist without another client action.
await asPlayer(1,()=>db.query("update tournament_entries set status='cancelled' where id=$1",[first]));
assert.equal((await status(21)).entries[0].allocation_status,'confirmed');assert.equal((await status(21)).intermediate_confirmed,20);
assert.equal((await status(43)).entries[0].allocation_status,'waitlist');
await asPlayer(23,()=>db.query("update tournament_entries set status='cancelled' where event_id=$1 and user_id=$2",[eid,uid(23)]));
assert.equal((await status(43)).entries[0].allocation_status,'confirmed');
// Participants can read their own pair but cannot change someone else's pair or allocation.
const partner=await asPlayer(22,()=>db.query('select id from tournament_entries where event_id=$1',[eid]));assert.equal(partner.rows.length,1);
const unrelated=await asPlayer(45,()=>db.query('select id from tournament_entries where event_id=$1',[eid]));assert.equal(unrelated.rows.length,0);
const attempted=await asPlayer(22,()=>db.query("update tournament_entries set status='cancelled' where user_id=$1 returning id",[uid(21)]));assert.equal(attempted.rows.length,0);
await assert.rejects(()=>asPlayer(45,()=>db.exec('update kestrel_tournaments.allocations set confirmed=true')),/permission denied/);
console.log('PASS: schema, event date and fees, Season identities, allowed levels, duplicate pairs, unpaid waitlist, both 20-player caps, paid waitlist promotion, participant privacy and allocation permissions.');
await db.close();
