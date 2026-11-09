-- CargoFlow: allow freelance payment methods Per Koli and Per Resi
-- Keeps legacy values ('delivered', 'assigned') valid for existing records.

alter table public.freelancers
  drop constraint if exists freelancers_counting_method_check;

alter table public.freelancers
  add constraint freelancers_counting_method_check
  check (counting_method in ('delivered', 'assigned', 'koli', 'resi'));
