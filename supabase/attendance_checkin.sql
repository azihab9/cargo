-- CargoFlow KPG003A: check-in GPS + selfie dan check-out mandiri
-- Jalankan SETELAH attendance.sql dan attendance_registration.sql.
-- Zona waktu operasional: Asia/Jakarta. Default jam masuk 08:00, toleransi 0 menit.
-- Admin mengatur koordinat kantor dari tombol "Atur lokasi kantor" pada portal Attendance.

alter table public.attendance_settings
  add column if not exists work_start_time time not null default time '08:00',
  add column if not exists grace_minutes integer not null default 0
    check (grace_minutes between 0 and 180);

alter table public.attendance_records
  add column if not exists user_id uuid references auth.users(id) on delete set null,
  add column if not exists check_in_photo_path text,
  add column if not exists late_minutes integer not null default 0
    check (late_minutes >= 0);

-- Bucket privat untuk bukti selfie. Foto tidak dibuat publik.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attendance-selfies', 'attendance-selfies', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = false, file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "attendance selfie upload own" on storage.objects;
create policy "attendance selfie upload own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'attendance-selfies'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "attendance selfie read own or admin" on storage.objects;
create policy "attendance selfie read own or admin"
on storage.objects for select to authenticated
using (
  bucket_id = 'attendance-selfies'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.has_role(array['admin','operations'])
  )
);

create or replace function public.attendance_check_in(
  p_latitude numeric,
  p_longitude numeric,
  p_photo_path text
)
returns uuid
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_user uuid := auth.uid();
  v_member public.attendance_members%rowtype;
  v_settings public.attendance_settings%rowtype;
  v_now timestamptz := now();
  v_local timestamp;
  v_date date;
  v_distance numeric;
  v_late integer;
  v_record_id uuid;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'Lokasi GPS tidak valid.';
  end if;
  if nullif(trim(p_photo_path), '') is null
     or split_part(p_photo_path, '/', 1) <> v_user::text then
    raise exception 'Selfie wajib diunggah dari akun ini.';
  end if;

  select * into v_member
  from public.attendance_members
  where user_id = v_user and active = true;
  if not found then raise exception 'Akun belum disetujui admin.'; end if;

  select * into v_settings from public.attendance_settings where id = true;
  if not found or v_settings.office_latitude is null or v_settings.office_longitude is null then
    raise exception 'Lokasi kantor belum diatur admin.';
  end if;

  if not exists (
    select 1 from storage.objects
    where bucket_id = 'attendance-selfies' and name = p_photo_path
  ) then
    raise exception 'File selfie tidak ditemukan. Silakan ambil ulang selfie.';
  end if;

  -- Haversine distance in meters.
  v_distance := 6371000 * 2 * asin(sqrt(
    power(sin(radians((p_latitude - v_settings.office_latitude)::double precision) / 2), 2)
    + cos(radians(v_settings.office_latitude::double precision))
    * cos(radians(p_latitude::double precision))
    * power(sin(radians((p_longitude - v_settings.office_longitude)::double precision) / 2), 2)
  ));

  if v_distance > v_settings.allowed_radius_m then
    raise exception 'Di luar radius kantor. Jarak terdeteksi sekitar % meter; batas % meter.',
      round(v_distance)::integer, v_settings.allowed_radius_m;
  end if;

  v_local := v_now at time zone 'Asia/Jakarta';
  v_date := v_local::date;
  v_late := greatest(
    0,
    floor(extract(epoch from (
      v_local - (v_date + v_settings.work_start_time
        + make_interval(mins => v_settings.grace_minutes))
    )) / 60)::integer
  );

  insert into public.attendance_records (
    person_name, person_type, attendance_date, attendance_status,
    check_in_at, check_in_latitude, check_in_longitude,
    check_in_method, check_in_photo_path, late_minutes, user_id, created_by
  )
  values (
    v_member.person_name, v_member.person_type, v_date, 'hadir',
    v_now, p_latitude, p_longitude, 'gps', p_photo_path, v_late, v_user, v_user
  )
  on conflict (person_name, attendance_date) do update
    set check_in_at = excluded.check_in_at,
        check_in_latitude = excluded.check_in_latitude,
        check_in_longitude = excluded.check_in_longitude,
        check_in_method = 'gps',
        check_in_photo_path = excluded.check_in_photo_path,
        late_minutes = excluded.late_minutes,
        user_id = excluded.user_id,
        attendance_status = 'hadir',
        updated_at = now()
    where public.attendance_records.check_in_at is null
      and (public.attendance_records.user_id is null or public.attendance_records.user_id = v_user)
  returning id into v_record_id;

  if v_record_id is null then
    raise exception 'Absensi masuk hari ini sudah tercatat.';
  end if;
  return v_record_id;
end;
$$;

create or replace function public.attendance_check_out()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
  v_record_id uuid;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu.'; end if;

  update public.attendance_records
  set check_out_at = now(),
      check_out_method = 'manual',
      updated_at = now()
  where user_id = v_user
    and attendance_date = v_date
    and check_in_at is not null
    and check_out_at is null
  returning id into v_record_id;

  if v_record_id is null then
    raise exception 'Data Check In hari ini tidak ditemukan atau Check Out sudah dilakukan.';
  end if;
  return v_record_id;
end;
$$;

revoke all on function public.attendance_check_in(numeric,numeric,text) from public;
revoke all on function public.attendance_check_out() from public;
grant execute on function public.attendance_check_in(numeric,numeric,text) to authenticated;
grant execute on function public.attendance_check_out() to authenticated;

-- Check-in dan check-out hanya melalui fungsi di atas; admin tetap dapat mengelola catatan.
drop policy if exists "authorized insert attendance records" on public.attendance_records;
drop policy if exists "attendance employee insert own" on public.attendance_records;
create policy "attendance employee insert own"
on public.attendance_records for insert to authenticated
with check (
  public.has_role(array['admin','operations'])
  or user_id = auth.uid()
);

drop policy if exists "authorized update attendance records" on public.attendance_records;
drop policy if exists "attendance employee update own checkout" on public.attendance_records;
create policy "attendance employee update own checkout"
on public.attendance_records for update to authenticated
using (public.has_role(array['admin','operations']))
with check (public.has_role(array['admin','operations']));
