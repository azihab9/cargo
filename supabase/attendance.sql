-- CargoFlow KPG003A: fondasi absensi karyawan
-- Jalankan sekali di Supabase SQL Editor.

create table if not exists public.attendance_settings (
  id boolean primary key default true check (id = true),
  office_latitude numeric(10,7),
  office_longitude numeric(10,7),
  allowed_radius_m integer not null default 100 check (allowed_radius_m between 10 and 2000),
  gps_required_types text[] not null default array['sprinter','admin','warehouse']::text[],
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.attendance_settings (id, allowed_radius_m)
values (true, 100)
on conflict (id) do nothing;

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  person_name text not null,
  person_type text not null check (person_type in ('sprinter','admin','warehouse','freelance')),
  attendance_date date not null,
  attendance_status text not null default 'hadir'
    check (attendance_status in ('hadir','izin','sakit','alpha','libur')),
  check_in_at timestamptz,
  check_out_at timestamptz,
  check_in_latitude numeric(10,7),
  check_in_longitude numeric(10,7),
  check_out_latitude numeric(10,7),
  check_out_longitude numeric(10,7),
  check_in_method text not null default 'manual'
    check (check_in_method in ('gps','manual')),
  check_out_method text
    check (check_out_method in ('gps','manual')),
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_name, attendance_date)
);

create index if not exists attendance_records_date_idx
  on public.attendance_records (attendance_date desc);
create index if not exists attendance_records_person_date_idx
  on public.attendance_records (person_name, attendance_date desc);

alter table public.attendance_settings enable row level security;
alter table public.attendance_records enable row level security;

drop policy if exists "authenticated read attendance settings" on public.attendance_settings;
create policy "authenticated read attendance settings"
  on public.attendance_settings for select to authenticated
  using (public.current_role() is not null);

drop policy if exists "authorized manage attendance settings" on public.attendance_settings;
create policy "authorized manage attendance settings"
  on public.attendance_settings for all to authenticated
  using (public.has_role(array['admin','operations']))
  with check (public.has_role(array['admin','operations']));

drop policy if exists "authenticated read attendance records" on public.attendance_records;
create policy "authenticated read attendance records"
  on public.attendance_records for select to authenticated
  using (public.current_role() is not null);

drop policy if exists "authorized insert attendance records" on public.attendance_records;
create policy "authorized insert attendance records"
  on public.attendance_records for insert to authenticated
  with check (public.has_role(array['admin','operations']));

drop policy if exists "authorized update attendance records" on public.attendance_records;
create policy "authorized update attendance records"
  on public.attendance_records for update to authenticated
  using (public.has_role(array['admin','operations']))
  with check (public.has_role(array['admin','operations']));

drop policy if exists "authorized delete attendance records" on public.attendance_records;
create policy "authorized delete attendance records"
  on public.attendance_records for delete to authenticated
  using (public.has_role(array['admin']));
