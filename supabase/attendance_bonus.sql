-- CargoFlow KPG003A: aturan bonus kehadiran yang dapat diatur admin
-- Jalankan di Supabase SQL Editor setelah attendance.sql, attendance_registration.sql,
-- dan attendance_checkin.sql.

create table if not exists public.attendance_bonus_rules (
  id uuid primary key default gen_random_uuid(),
  bonus_name text not null,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  person_types text[] not null default array['sprinter','admin','warehouse','freelance']::text[],
  min_present_days integer not null default 0 check (min_present_days >= 0),
  max_late_days integer not null default 999 check (max_late_days >= 0),
  max_izin_days integer not null default 999 check (max_izin_days >= 0),
  max_sakit_days integer not null default 999 check (max_sakit_days >= 0),
  max_alpha_days integer not null default 0 check (max_alpha_days >= 0),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_bonus_rules_person_types_check
    check (person_types <@ array['sprinter','admin','warehouse','freelance']::text[] and cardinality(person_types) > 0)
);

create index if not exists attendance_bonus_rules_active_idx
  on public.attendance_bonus_rules(active, created_at desc);

alter table public.attendance_bonus_rules enable row level security;

drop policy if exists "attendance bonus rules read admin" on public.attendance_bonus_rules;
create policy "attendance bonus rules read admin"
  on public.attendance_bonus_rules for select to authenticated
  using (public.has_role(array['admin','operations']));

drop policy if exists "attendance bonus rules manage admin" on public.attendance_bonus_rules;
create policy "attendance bonus rules manage admin"
  on public.attendance_bonus_rules for all to authenticated
  using (public.has_role(array['admin','operations']))
  with check (public.has_role(array['admin','operations']));

-- Kolom bonus terpisah agar tidak bercampur dengan fee delivery.
alter table public.payroll_items
  add column if not exists attendance_bonus numeric(14,2) not null default 0;
