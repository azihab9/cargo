-- CargoFlow: imported J&T Cargo TTD report items for COD/DFOD reconciliation
-- Run once in Supabase SQL Editor. Safe to re-run.

create table if not exists public.cash_report_items (
  id uuid primary key default gen_random_uuid(),
  awb text not null unique,
  ttd_date date not null,
  sprinter_name text not null,
  cod_amount numeric(14,2) not null default 0,
  dfod_amount numeric(14,2) not null default 0,
  imported_by uuid references auth.users(id),
  imported_at timestamptz not null default now()
);

create index if not exists cash_report_items_ttd_date_idx
  on public.cash_report_items(ttd_date, sprinter_name);

alter table public.cash_report_items enable row level security;

drop policy if exists "cash report items read authenticated" on public.cash_report_items;
create policy "cash report items read authenticated"
on public.cash_report_items for select to authenticated
using (public.current_role() is not null);

drop policy if exists "cash report items import authorized" on public.cash_report_items;
create policy "cash report items import authorized"
on public.cash_report_items for insert to authenticated
with check (public.has_role(array['admin','finance','operations']));

drop policy if exists "cash report items update authorized" on public.cash_report_items;
create policy "cash report items update authorized"
on public.cash_report_items for update to authenticated
using (public.has_role(array['admin','finance','operations']))
with check (public.has_role(array['admin','finance','operations']));

drop policy if exists "cash report items delete admin" on public.cash_report_items;
create policy "cash report items delete admin"
on public.cash_report_items for delete to authenticated
using (public.has_role(array['admin']));
