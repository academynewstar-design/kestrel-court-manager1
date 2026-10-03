-- Kestrel schedule seed data
insert into public.locations(name,address,city) values
('École élémentaire La Pommeraie','London, Ontario','London'),
('Ange Gabriel Elementary School','Mississauga, Ontario','Mississauga')
on conflict(name) do nothing;
insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,payment_first,status)
select
  s.id,
  l.id,
  v.d::date,
  v.st::time,
  v.et::time,
  v.cap,
  v.price,
  v.email,
  v.first,
  'open'
from (values
('volleyball','École élémentaire La Pommeraie','2026-10-06','19:00','21:00',18,6.00,'kheynand@gmail.com',false),
('volleyball','École élémentaire La Pommeraie','2026-10-08','19:00','21:00',18,6.00,'kheynand@gmail.com',false),
('volleyball','Ange Gabriel Elementary School','2026-10-05','18:30','21:00',18,7.00,'academynewstar@gmail.com',true)
) v(sp,loc,d,st,et,cap,price,email,first)
join public.sports s on s.name=v.sp join public.locations l on l.name=v.loc
where not exists(select 1 from public.sessions x where x.location_id=l.id and x.session_date=v.d::date and x.start_time=v.st::time);

-- Recurring 2026 sessions
insert into public.sessions (sport_id, location_id, session_date, start_time, end_time, capacity, price, payment_email, payment_first)
select s.id,l.id,d::date,'19:00','21:00',18,6,'kheynand@gmail.com',false
from public.sports s cross join public.locations l cross join generate_series('2026-10-06'::date,'2026-12-31'::date,'7 days') d
where s.name='volleyball' and l.name='École élémentaire La Pommeraie'
on conflict do nothing;

insert into public.sessions (sport_id, location_id, session_date, start_time, end_time, capacity, price, payment_email, payment_first)
select s.id,l.id,d::date,'19:00','21:00',18,6,'kheynand@gmail.com',false
from public.sports s cross join public.locations l cross join generate_series('2026-10-08'::date,'2026-12-31'::date,'7 days') d
where s.name='volleyball' and l.name='École élémentaire La Pommeraie'
on conflict do nothing;

insert into public.sessions (sport_id, location_id, session_date, start_time, end_time, capacity, price, payment_email, payment_first)
select s.id,l.id,d::date,'18:30','21:00',18,7,'academynewstar@gmail.com',true
from public.sports s cross join public.locations l cross join generate_series('2026-10-05'::date,'2026-12-28'::date,'7 days') d
where s.name='volleyball' and l.name='Ange Gabriel Elementary School'
on conflict do nothing;


-- Legacy permanent player roster: preserve existing registrations during migration
insert into public.legacy_player_roster (full_name, player_type) values
('Shoaib','permanent'),
('Vikram Sudera','permanent'),
('Navpreet','permanent'),
('Sagar','permanent'),
('Anbu','permanent'),
('Pankaj Mahindru','permanent'),
('MAULIK','permanent'),
('Suganya AR','permanent'),
('Siva Oakville','permanent'),
('Nish Shah','permanent'),
('Narsi','permanent'),
('Nisha','permanent'),
('Dharini','permanent'),
('Sangeethaa','permanent'),
('Mez','permanent'),
('Manjit Singh','permanent'),
('Deepak Pandey','permanent'),
('Sanjeev','permanent'),
('Vyom','permanent'),
('Abdul Rahman','permanent'),
('Ashish Patel','permanent'),
('Twisha','permanent'),
('Teja','permanent'),
('Keith','permanent'),
('Sathish','permanent'),
('Sundari Natrajan','permanent'),
('Amol','permanent'),
('Shaun','permanent'),
('Suhas Patha','permanent'),
('Praveen','permanent'),
('kheynand','permanent'),
('Bala','permanent'),
('Ushma','permanent'),
('Srinivas','permanent'),
('Durlabh','permanent'),
('Mahesh Nandam','permanent'),
('Pooja','permanent'),
('Chirag','permanent'),
('Vihari','permanent')
on conflict (full_name) do update set player_type='permanent';


-- Registration/payment deadlines for the seeded recurring sessions.
update public.sessions x
set registration_open_at = (x.session_date + x.start_time) - interval '44 hours',
    registration_deadline = (x.session_date + x.start_time) - interval '44 hours',
    payment_deadline = (x.session_date + x.start_time) - interval '8 hours'
where x.location_id=(select id from public.locations where name='École élémentaire La Pommeraie');

update public.sessions x
set registration_open_at = ((x.session_date - 3) + time '23:50'),
    payment_deadline = null
where x.location_id=(select id from public.locations where name='Ange Gabriel Elementary School');
