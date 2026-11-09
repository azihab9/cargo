-- CargoFlow KPG003A: pendaftaran mandiri dan identitas absensi yang tervalidasi
-- Jalankan SETELAH supabase/attendance.sql.
-- Pendaftaran attendance memakai Auth Supabase, tetapi akun baru tidak otomatis mendapat akses CargoFlow.

create table if not exists public.attendance_registration_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  requested_name text not null,
  requested_type text not null check (requested_type in ('sprinter','admin','warehouse','freelance')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_members (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  person_name text not null,
  person_type text not null check (person_type in ('sprinter','admin','warehouse','freelance')),
  person_ref_id uuid not null,
  active boolean not null default true,
  approved_by uuid references auth.users(id),
  approved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (person_type, person_ref_id)
);

alter table public.attendance_records
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create index if not exists attendance_requests_status_idx
  on public.attendance_registration_requests(status, created_at desc);
create index if not exists attendance_members_user_idx
  on public.attendance_members(user_id);

alter table public.attendance_registration_requests enable row level security;
alter table public.attendance_members enable row level security;

drop policy if exists "attendance request insert own" on public.attendance_registration_requests;
create policy "attendance request insert own"
  on public.attendance_registration_requests for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and reviewed_by is null and reviewed_at is null);

drop policy if exists "attendance request read own or admin" on public.attendance_registration_requests;
create policy "attendance request read own or admin"
  on public.attendance_registration_requests for select to authenticated
  using (user_id = auth.uid() or public.has_role(array['admin','operations']));

drop policy if exists "attendance request admin review" on public.attendance_registration_requests;
create policy "attendance request admin review"
  on public.attendance_registration_requests for update to authenticated
  using (public.has_role(array['admin','operations']))
  with check (public.has_role(array['admin','operations']));

drop policy if exists "attendance member read own or admin" on public.attendance_members;
create policy "attendance member read own or admin"
  on public.attendance_members for select to authenticated
  using (user_id = auth.uid() or public.has_role(array['admin','operations']));

drop policy if exists "attendance member admin manage" on public.attendance_members;
create policy "attendance member admin manage"
  on public.attendance_members for all to authenticated
  using (public.has_role(array['admin','operations']))
  with check (public.has_role(array['admin','operations']));

-- Karyawan hanya bisa melihat catatan absensinya sendiri; admin/operasional tetap bisa melihat semuanya.
drop policy if exists "authenticated read attendance records" on public.attendance_records;
drop policy if exists "attendance read own or admin" on public.attendance_records;
create policy "attendance read own or admin"
  on public.attendance_records for select to authenticated
  using (
    user_id = auth.uid()
    or public.has_role(array['admin','operations'])
  );

-- Insert/update/delete absensi tetap melalui admin atau fungsi server yang akan ditambahkan pada tahap GPS.

-- Akun yang mendaftar dari aplikasi absensi diberi profil nonaktif agar tidak bisa masuk ke CargoFlow utama
-- sebelum admin mengaktifkan akses secara terpisah.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role, active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    'operations',
    case when new.raw_user_meta_data->>'app_context' = 'attendance' then false else true end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_cargoflow on auth.users;
create trigger on_auth_user_created_cargoflow
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Fungsi pengajuan dipakai setelah user berhasil daftar/login.
create or replace function public.attendance_submit_registration(
  p_requested_name text,
  p_requested_type text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Silakan login terlebih dahulu.';
  end if;
  if nullif(trim(p_requested_name), '') is null then
    raise exception 'Nama wajib diisi.';
  end if;
  if p_requested_type not in ('sprinter','admin','warehouse','freelance') then
    raise exception 'Kategori karyawan tidak valid.';
  end if;
  if exists (select 1 from public.attendance_members where user_id = auth.uid() and active = true) then
    raise exception 'Akun ini sudah terhubung dengan data karyawan.';
  end if;

  insert into public.attendance_registration_requests(user_id, requested_name, requested_type)
  values (auth.uid(), trim(p_requested_name), p_requested_type)
  on conflict (user_id) do update
    set requested_name = excluded.requested_name,
        requested_type = excluded.requested_type,
        status = 'pending',
        admin_note = null,
        reviewed_by = null,
        reviewed_at = null
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.attendance_submit_registration(text,text) from public;
grant execute on function public.attendance_submit_registration(text,text) to authenticated;

-- Admin menyetujui dengan memilih ID master yang cocok; nama/kategori diverifikasi di database.
create or replace function public.attendance_approve_registration(
  p_request_id uuid,
  p_person_ref_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.attendance_registration_requests%rowtype;
  v_name text;
  v_type text;
begin
  if not public.has_role(array['admin','operations']) then
    raise exception 'Tidak memiliki izin untuk menyetujui pendaftaran.';
  end if;

  select * into v_req
  from public.attendance_registration_requests
  where id = p_request_id and status = 'pending'
  for update;

  if not found then
    raise exception 'Pengajuan tidak ditemukan atau sudah diproses.';
  end if;

  v_type := v_req.requested_type;

  if v_type = 'sprinter' then
    select name into v_name from public.sprinters where id = p_person_ref_id and active = true;
  elsif v_type in ('admin','warehouse') then
    select name into v_name from public.office_staff
      where id = p_person_ref_id and active = true and staff_role = v_type;
  elsif v_type = 'freelance' then
    select name into v_name from public.freelancers where id = p_person_ref_id and active = true;
  end if;

  if v_name is null then
    raise exception 'Data master karyawan tidak ditemukan atau kategorinya tidak cocok.';
  end if;

  if lower(trim(v_name)) <> lower(trim(v_req.requested_name)) then
    raise exception 'Nama pengajuan tidak cocok dengan nama master karyawan.';
  end if;

  insert into public.attendance_members(user_id, person_name, person_type, person_ref_id, approved_by)
  values (v_req.user_id, v_name, v_type, p_person_ref_id, auth.uid())
  on conflict (user_id) do update
    set person_name = excluded.person_name,
        person_type = excluded.person_type,
        person_ref_id = excluded.person_ref_id,
        active = true,
        approved_by = auth.uid(),
        approved_at = now();

  update public.attendance_registration_requests
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), admin_note = null
  where id = p_request_id;
end;
$$;

revoke all on function public.attendance_approve_registration(uuid,uuid) from public;
grant execute on function public.attendance_approve_registration(uuid,uuid) to authenticated;

create or replace function public.attendance_reject_registration(
  p_request_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_role(array['admin','operations']) then
    raise exception 'Tidak memiliki izin untuk menolak pendaftaran.';
  end if;
  update public.attendance_registration_requests
  set status = 'rejected',
      admin_note = nullif(trim(p_note), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_request_id and status = 'pending';
  if not found then
    raise exception 'Pengajuan tidak ditemukan atau sudah diproses.';
  end if;
end;
$$;

revoke all on function public.attendance_reject_registration(uuid,text) from public;
grant execute on function public.attendance_reject_registration(uuid,text) to authenticated;
