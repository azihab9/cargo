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

-- Kolom bonus dan jumlah TTD disimpan terpisah agar tidak bercampur dengan fee delivery.
alter table public.payroll_items
  add column if not exists attendance_bonus numeric(14,2) not null default 0,
  add column if not exists ttd_count integer not null default 0;


-- Terapkan bonus absensi ke draft payroll secara idempoten (tidak menggandakan bonus saat dijalankan ulang).
create or replace function public.apply_attendance_bonus_to_payroll(p_run_id uuid)
returns table(updated_items integer, total_bonus numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.payroll_runs%rowtype;
begin
  if not public.has_role(array['admin','finance','operations']) then
    raise exception 'Tidak memiliki izin untuk menghitung bonus payroll.';
  end if;

  select * into v_run
  from public.payroll_runs
  where id = p_run_id
  for update;

  if not found then raise exception 'Draft payroll tidak ditemukan.'; end if;
  if v_run.status <> 'draft' then
    raise exception 'Bonus absensi hanya dapat diterapkan pada payroll berstatus draft.';
  end if;

  -- Buat item payroll untuk anggota attendance aktif yang belum memiliki item pada periode ini.
  with stats as (
    select
      m.person_name,
      m.person_type,
      m.person_ref_id,
      count(r.id) filter (where r.attendance_status = 'hadir')::integer as present_days,
      count(r.id) filter (where r.attendance_status = 'hadir' and coalesce(r.late_minutes,0) > 0)::integer as late_days,
      count(r.id) filter (where r.attendance_status = 'izin')::integer as izin_days,
      count(r.id) filter (where r.attendance_status = 'sakit')::integer as sakit_days,
      count(r.id) filter (where r.attendance_status = 'alpha')::integer as alpha_days
    from public.attendance_members m
    left join public.attendance_records r
      on r.person_name = m.person_name
     and r.person_type = m.person_type
     and r.attendance_date between v_run.period_start and v_run.period_end
    where m.active = true
    group by m.person_name,m.person_type,m.person_ref_id
  ),
  awards as (
    select s.*,
      coalesce(sum(rule.amount),0)::numeric(14,2) as bonus
    from stats s
    left join public.attendance_bonus_rules rule
      on rule.active = true
     and rule.person_types @> array[s.person_type]::text[]
     and s.present_days >= rule.min_present_days
     and s.late_days <= rule.max_late_days
     and s.izin_days <= rule.max_izin_days
     and s.sakit_days <= rule.max_sakit_days
     and s.alpha_days <= rule.max_alpha_days
    group by s.person_name,s.person_type,s.person_ref_id,s.present_days,s.late_days,s.izin_days,s.sakit_days,s.alpha_days
  )
  insert into public.payroll_items (
    payroll_run_id,sprinter_id,freelancer_id,person_name,pay_type,
    basic_salary,ttd_weight_kg,ttd_count,fee_per_kg,package_count,fee_per_package,
    gross_amount,loan_deduction,penalty_deduction,net_amount,attendance_bonus
  )
  select
    v_run.id,
    case when a.person_type='sprinter' then a.person_ref_id end,
    case when a.person_type='freelance' then a.person_ref_id end,
    a.person_name,a.person_type,
    case
      when a.person_type='sprinter' then coalesce(sp.basic_salary,0)
      when a.person_type in ('admin','warehouse') then coalesce(os.basic_salary,0)
      else 0
    end,
    0,0,0,0,0,
    case
      when a.person_type='sprinter' then coalesce(sp.basic_salary,0)
      when a.person_type in ('admin','warehouse') then coalesce(os.basic_salary,0)
      else 0
    end + a.bonus,
    0,0,
    case
      when a.person_type='sprinter' then coalesce(sp.basic_salary,0)
      when a.person_type in ('admin','warehouse') then coalesce(os.basic_salary,0)
      else 0
    end + a.bonus,
    a.bonus
  from awards a
  left join public.sprinters sp on a.person_type='sprinter' and sp.id=a.person_ref_id
  left join public.office_staff os on a.person_type in ('admin','warehouse') and os.id=a.person_ref_id
  where not exists (
    select 1 from public.payroll_items p
    where p.payroll_run_id=v_run.id and p.person_name=a.person_name and p.pay_type=a.person_type
  );

  -- Ganti nilai bonus lama, bukan menambahkannya berulang kali.
  with stats as (
    select
      m.person_name,m.person_type,
      count(r.id) filter (where r.attendance_status='hadir')::integer as present_days,
      count(r.id) filter (where r.attendance_status='hadir' and coalesce(r.late_minutes,0)>0)::integer as late_days,
      count(r.id) filter (where r.attendance_status='izin')::integer as izin_days,
      count(r.id) filter (where r.attendance_status='sakit')::integer as sakit_days,
      count(r.id) filter (where r.attendance_status='alpha')::integer as alpha_days
    from public.attendance_members m
    left join public.attendance_records r
      on r.person_name=m.person_name and r.person_type=m.person_type
     and r.attendance_date between v_run.period_start and v_run.period_end
    where m.active=true
    group by m.person_name,m.person_type
  ),
  awards as (
    select s.person_name,s.person_type,coalesce(sum(rule.amount),0)::numeric(14,2) as bonus
    from stats s
    left join public.attendance_bonus_rules rule
      on rule.active=true and rule.person_types @> array[s.person_type]::text[]
     and s.present_days>=rule.min_present_days
     and s.late_days<=rule.max_late_days
     and s.izin_days<=rule.max_izin_days
     and s.sakit_days<=rule.max_sakit_days
     and s.alpha_days<=rule.max_alpha_days
    group by s.person_name,s.person_type
  )
  update public.payroll_items p
  set gross_amount=p.gross_amount-coalesce(p.attendance_bonus,0)+a.bonus,
      net_amount=p.net_amount-coalesce(p.attendance_bonus,0)+a.bonus,
      attendance_bonus=a.bonus
  from awards a
  where p.payroll_run_id=v_run.id
    and p.person_name=a.person_name
    and p.pay_type=a.person_type;

  return query
  select count(*)::integer,coalesce(sum(p.attendance_bonus),0)::numeric
  from public.payroll_items p
  where p.payroll_run_id=v_run.id;

end;
$$;

revoke all on function public.apply_attendance_bonus_to_payroll(uuid) from public;
grant execute on function public.apply_attendance_bonus_to_payroll(uuid) to authenticated;
