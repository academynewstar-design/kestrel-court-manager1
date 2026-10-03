-- Kestrel schedule seed data
insert into public.locations(name,address,city) values
('École élémentaire La Pommeraie','London, Ontario','London'),
('Ange Gabriel Elementary School','Mississauga, Ontario','Mississauga')
on conflict(name) do nothing;
insert into public.sessions(sport_id,location_id,session_date,start_time,end_time,capacity,price,payment_email,payment_first,status)
select s.id,l.id,v.d::date,v.st,v.et,v.cap,v.price,v.email,v.first,'open'
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
where s.name='Volleyball' and l.name='École élémentaire La Pommeraie'
on conflict do nothing;

insert into public.sessions (sport_id, location_id, session_date, start_time, end_time, capacity, price, payment_email, payment_first)
select s.id,l.id,d::date,'19:00','21:00',18,6,'kheynand@gmail.com',false
from public.sports s cross join public.locations l cross join generate_series('2026-10-08'::date,'2026-12-31'::date,'7 days') d
where s.name='Volleyball' and l.name='École élémentaire La Pommeraie'
on conflict do nothing;

insert into public.sessions (sport_id, location_id, session_date, start_time, end_time, capacity, price, payment_email, payment_first)
select s.id,l.id,d::date,'18:30','21:00',18,7,'academynewstar@gmail.com',true
from public.sports s cross join public.locations l cross join generate_series('2026-10-05'::date,'2026-12-28'::date,'7 days') d
where s.name='Volleyball' and l.name='Ange Gabriel Elementary School'
on conflict do nothing;
