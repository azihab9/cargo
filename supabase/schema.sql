-- CargoFlow Area Rantau - Supabase schema
-- Run this file in Supabase SQL Editor. Never put the service_role key in frontend code.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'operations' check (role in ('admin','finance','operations')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and active = true $$;

create or replace function public.has_role(allowed text[])
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_role() = any(allowed), false) $$;

create table if not exists public.sprinters (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  basic_salary numeric(14,2) not null default 0,
  fee_per_kg numeric(14,2) not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.freelancers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  fee_per_package numeric(14,2) not null default 8000,
  counting_method text not null default 'delivered' check (counting_method in ('delivered','assigned')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  file_hash text,
  row_count integer not null default 0,
  imported_by uuid references auth.users(id),
  imported_at timestamptz not null default now(),
  status text not null default 'completed' check (status in ('completed','reversed'))
);
create unique index if not exists import_batches_file_hash_uq on public.import_batches(file_hash) where file_hash is not null;

create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  import_batch_id uuid references public.import_batches(id) on delete set null,
  awb text,
  sprinter_id uuid references public.sprinters(id),
  sprinter_name text not null default '',
  ttd_status text not null default '',
  weight_kg numeric(12,3) not null default 0,
  cod_amount numeric(14,2) not null default 0,
  dfod_amount numeric(14,2) not null default 0,
  delivery_date date,
  ttd_date date,
  source_row jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists deliveries_awb_batch_uq on public.deliveries(import_batch_id, awb) where awb is not null;

create table if not exists public.employee_loans (
  id uuid primary key default gen_random_uuid(),
  sprinter_id uuid references public.sprinters(id),
  freelancer_id uuid references public.freelancers(id),
  person_name text not null,
  principal numeric(14,2) not null check (principal > 0),
  installment_amount numeric(14,2) not null default 0 check (installment_amount >= 0),
  balance numeric(14,2) not null,
  loan_date date not null default current_date,
  note text,
  status text not null default 'open' check (status in ('open','paid','paused')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check ((sprinter_id is not null)::int + (freelancer_id is not null)::int <= 1)
);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','locked','paid')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create table if not exists public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  sprinter_id uuid references public.sprinters(id),
  freelancer_id uuid references public.freelancers(id),
  person_name text not null,
  pay_type text not null check (pay_type in ('sprinter','freelance')),
  basic_salary numeric(14,2) not null default 0,
  ttd_weight_kg numeric(12,3) not null default 0,
  fee_per_kg numeric(14,2) not null default 0,
  package_count integer not null default 0,
  fee_per_package numeric(14,2) not null default 0,
  gross_amount numeric(14,2) not null default 0,
  loan_deduction numeric(14,2) not null default 0,
  net_amount numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.loan_installments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.employee_loans(id),
  payroll_item_id uuid references public.payroll_items(id),
  amount numeric(14,2) not null check (amount > 0),
  paid_at timestamptz not null default now(),
  note text
);

create table if not exists public.freelance_work (
  id uuid primary key default gen_random_uuid(),
  freelancer_id uuid not null references public.freelancers(id),
  work_date date not null default current_date,
  package_count integer not null default 0 check (package_count >= 0),
  delivered_count integer not null default 0 check (delivered_count >= 0),
  fee_per_package numeric(14,2) not null,
  counting_method text not null check (counting_method in ('delivered','assigned')),
  total_fee numeric(14,2) generated always as
    ((case when counting_method = 'delivered' then delivered_count else package_count end) * fee_per_package) stored,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null default current_date,
  category text not null,
  amount numeric(14,2) not null check (amount > 0),
  description text,
  receipt_path text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  action text not null,
  entity text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Enable RLS on all business tables.
alter table public.profiles enable row level security;
alter table public.sprinters enable row level security;
alter table public.freelancers enable row level security;
alter table public.import_batches enable row level security;
alter table public.deliveries enable row level security;
alter table public.employee_loans enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_items enable row level security;
alter table public.loan_installments enable row level security;
alter table public.freelance_work enable row level security;
alter table public.expenses enable row level security;
alter table public.audit_logs enable row level security;

-- Profiles: users can view their own profile; admins can manage profiles.
drop policy if exists "profile read own or admin" on public.profiles;
create policy "profile read own or admin" on public.profiles for select to authenticated
using (id = auth.uid() or public.has_role(array['admin']));
drop policy if exists "admin manage profiles" on public.profiles;
create policy "admin manage profiles" on public.profiles for all to authenticated
using (public.has_role(array['admin'])) with check (public.has_role(array['admin']));

-- Authenticated staff can read operational data. Writes are role-scoped.
do $$
declare t text;
begin
  foreach t in array array['sprinters','freelancers','import_batches','deliveries','employee_loans','payroll_runs','payroll_items','loan_installments','freelance_work','expenses','audit_logs']
  loop
    execute format('drop policy if exists "authenticated read %1$s" on public.%1$I', t);
    execute format('create policy "authenticated read %1$s" on public.%1$I for select to authenticated using (public.current_role() is not null)', t);
    execute format('drop policy if exists "authorized insert %1$s" on public.%1$I', t);
    execute format('create policy "authorized insert %1$s" on public.%1$I for insert to authenticated with check (public.has_role(array[''admin'',''finance'',''operations'']))', t);
    execute format('drop policy if exists "admin finance update %1$s" on public.%1$I', t);
    execute format('create policy "admin finance update %1$s" on public.%1$I for update to authenticated using (public.has_role(array[''admin'',''finance''])) with check (public.has_role(array[''admin'',''finance'']))', t);
    execute format('drop policy if exists "admin delete %1$s" on public.%1$I', t);
    execute format('create policy "admin delete %1$s" on public.%1$I for delete to authenticated using (public.has_role(array[''admin'']))', t);
  end loop;
end $$;

-- Private bucket for receipt photos/PDFs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cargoflow-receipts','cargoflow-receipts',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

drop policy if exists "receipt read authenticated" on storage.objects;
create policy "receipt read authenticated" on storage.objects for select to authenticated
using (bucket_id = 'cargoflow-receipts' and public.current_role() is not null);
drop policy if exists "receipt upload authenticated" on storage.objects;
create policy "receipt upload authenticated" on storage.objects for insert to authenticated
with check (bucket_id = 'cargoflow-receipts' and public.has_role(array['admin','finance','operations']));
drop policy if exists "receipt delete admin" on storage.objects;
create policy "receipt delete admin" on storage.objects for delete to authenticated
using (bucket_id = 'cargoflow-receipts' and public.has_role(array['admin']));

-- New user profiles are intentionally NOT auto-promoted to admin.
-- After the first user signs up, set their role manually in SQL Editor:
-- update public.profiles set role = 'admin', full_name = 'Admin CargoFlow' where id = '<AUTH_USER_UUID>';
