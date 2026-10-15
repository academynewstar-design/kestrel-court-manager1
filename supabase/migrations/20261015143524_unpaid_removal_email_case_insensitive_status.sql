drop trigger queue_unpaid_removal_email on public.registrations;
create trigger queue_unpaid_removal_email after update of status on public.registrations
for each row when(old.status='confirmed' and new.status='cancelled' and lower(coalesce(old.payment_status,''))='unpaid' and new.payment_status='removed')
execute function public.queue_unpaid_removal_email();