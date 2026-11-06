-- CargoFlow: daily COD/DFOD settlement ledger
-- Run once in Supabase SQL Editor. Safe to re-run.

create table if not exists public.cash_settlements (
  id uuid primary key default gen_random_uuid(),
  payment_date date not null default current_date,
  sprinter_id uuid references public.sprinters(id) on delete set null,
  sprinter_name text not null,
  awb text,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('transfer','qris','cash')),
  destination text not null check (destination in ('outlet','sprinter')),
  status text not null default 'pending'
    check (status in ('pending','held_by_sprinter','confirmed')),
  receipt_note text,
  created_by uuid references auth.users(id),
  confirmed_by uuid references auth.users(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists cash_settlements_payment_date_idx
  on public.cash_settlements(payment_date, sprinter_name);
create index if not exists cash_settlements_awb_idx
  on public.cash_settlements(awb) where awb is not null;

alter table public.cash_settlements enable row level security;

drop policy if exists "cash settlements read authenticated" on public.cash_settlements;
create policy "cash settlements read authenticated"
on public.cash_settlements for select to authenticated
using (public.current_role() is not null);

drop policy if exists "cash settlements insert authorized" on public.cash_settlements;
create policy "cash settlements insert authorized"
on public.cash_settlements for insert to authenticated
with check (public.has_role(array['admin','finance','operations']));

drop policy if exists "cash settlements confirm admin finance" on public.cash_settlements;
create policy "cash settlements confirm admin finance"
on public.cash_settlements for update to authenticated
using (public.has_role(array['admin','finance']))
with check (public.has_role(array['admin','finance']));

drop policy if exists "cash settlements delete admin" on public.cash_settlements;
create policy "cash settlements delete admin"
on public.cash_settlements for delete to authenticated
using (public.has_role(array['admin']));
