-- CargoFlow: daily delivery attempt history
-- Run once in Supabase SQL Editor before importing daily Excel updates.

create table if not exists public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  import_batch_id uuid not null references public.import_batches(id) on delete cascade,
  awb text not null,
  sprinter_name text not null default '',
  ttd_status text not null default '',
  weight_kg numeric(12,3) not null default 0,
  delivery_date date not null,
  ttd_date date,
  imported_at timestamptz not null default now(),
  unique (import_batch_id, awb)
);

create index if not exists delivery_attempts_delivery_date_idx
  on public.delivery_attempts(delivery_date);

create index if not exists delivery_attempts_awb_idx
  on public.delivery_attempts(awb);

alter table public.delivery_attempts enable row level security;

drop policy if exists "authenticated read delivery_attempts" on public.delivery_attempts;
create policy "authenticated read delivery_attempts"
  on public.delivery_attempts for select to authenticated
  using (public.current_role() is not null);

drop policy if exists "authorized insert delivery_attempts" on public.delivery_attempts;
create policy "authorized insert delivery_attempts"
  on public.delivery_attempts for insert to authenticated
  with check (public.has_role(array['admin','finance','operations']));
