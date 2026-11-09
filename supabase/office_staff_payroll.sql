-- CargoFlow: Master Staff Kantor + payroll Admin/Staff Gudang
create table if not exists public.office_staff (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  staff_role text not null check (staff_role in ('admin','warehouse')),
  basic_salary numeric(14,2) not null default 0 check (basic_salary >= 0),
  fee_per_kg numeric(14,2) not null default 100 check (fee_per_kg >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.office_staff enable row level security;
drop policy if exists "authenticated read office_staff" on public.office_staff;
create policy "authenticated read office_staff" on public.office_staff
  for select to authenticated using (public.current_role() is not null);
drop policy if exists "authorized insert office_staff" on public.office_staff;
create policy "authorized insert office_staff" on public.office_staff
  for insert to authenticated with check (public.has_role(array['admin','finance','operations']));
drop policy if exists "admin finance update office_staff" on public.office_staff;
create policy "admin finance update office_staff" on public.office_staff
  for update to authenticated using (public.has_role(array['admin','finance']))
  with check (public.has_role(array['admin','finance']));
drop policy if exists "admin delete office_staff" on public.office_staff;
create policy "admin delete office_staff" on public.office_staff
  for delete to authenticated using (public.has_role(array['admin']));

-- Extend the payroll type constraint so office staff can be saved in payroll_runs.
alter table public.payroll_items
  drop constraint if exists payroll_items_pay_type_check;
alter table public.payroll_items
  add constraint payroll_items_pay_type_check
  check (pay_type in ('sprinter','freelance','admin','warehouse'));

alter table public.payroll_items
  add column if not exists penalty_deduction numeric(14,2) not null default 0;
