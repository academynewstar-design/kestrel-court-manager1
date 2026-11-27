-- Publish after the doubles schema and registration interface are available.
insert into public.tournament_events(
 slug,title,sport_id,city,location_details,starts_at,individual_fee,team_fee,minimum_age,
 registration_format,intermediate_capacity,low_intermediate_capacity,status
)
select 'kestrel-season-badminton-2027-02-07','Kestrel Season Badminton Tournament',id,
 'Brampton','Jeunes sans Frontières Secondary School',
 '2027-02-07 09:00:00 America/Toronto'::timestamptz,25,50,0,
 'season_badminton_doubles',20,20,'open'
from public.sports where name='badminton'
on conflict(slug) do nothing;
