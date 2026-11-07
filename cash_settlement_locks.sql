-- CargoFlow: penguncian setoran COD & DFOD per sprinter per tanggal
create table if not exists public.cash_settlement_locks (
  id uuid primary key default gen_random_uuid(),
  settlement_date date not null,
  sprinter_name text not null,
  locked_at timestamptz not null default now(),
  locked_by uuid references auth.users(id),
  constraint cash_settlement_locks_date_sprinter_unique unique (settlement_date, sprinter_name)
);

alter table public.cash_settlement_locks enable row level security;

grant select, insert on public.cash_settlement_locks to authenticated;

drop policy if exists "Authenticated users can view cash settlement locks" on public.cash_settlement_locks;
create policy "Authenticated users can view cash settlement locks"
on public.cash_settlement_locks
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can create cash settlement locks" on public.cash_settlement_locks;
create policy "Authenticated users can create cash settlement locks"
on public.cash_settlement_locks
for insert
to authenticated
with check (true);
