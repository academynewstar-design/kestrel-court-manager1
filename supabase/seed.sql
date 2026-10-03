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
