-- CargoFlow: finalisasi payroll per karyawan
-- Jalankan sekali di Supabase SQL Editor. Tidak mengubah transaksi payroll lama.
alter table public.payroll_items
  add column if not exists individual_status text not null default 'draft',
  add column if not exists finalized_at timestamptz,
  add column if not exists paid_at timestamptz;

alter table public.payroll_items
  drop constraint if exists payroll_items_individual_status_check;
alter table public.payroll_items
  add constraint payroll_items_individual_status_check
  check (individual_status in ('draft','final','paid'));

create index if not exists payroll_items_run_individual_status_idx
  on public.payroll_items(payroll_run_id, individual_status);

-- Finalisasi satu item: mencatat angsuran kasbon/denda secara atomik.
create or replace function public.finalize_payroll_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_item public.payroll_items%rowtype;
  v_run public.payroll_runs%rowtype;
  v_loan public.employee_loans%rowtype;
  v_penalty public.employee_penalties%rowtype;
  v_remaining numeric(14,2);
  v_amount numeric(14,2);
begin
  if not public.has_role(array['admin','finance']) then
    raise exception 'Tidak memiliki izin finalisasi payroll';
  end if;

  select * into v_item from public.payroll_items
  where id = p_item_id for update;
  if not found then raise exception 'Item payroll tidak ditemukan'; end if;

  select * into v_run from public.payroll_runs
  where id = v_item.payroll_run_id for update;
  if not found then raise exception 'Payroll tidak ditemukan'; end if;
  if v_run.status <> 'draft' then
    raise exception 'Periode payroll sudah dikunci. Finalisasi individual hanya tersedia saat periode berstatus draft.';
  end if;
  if v_item.individual_status <> 'draft' then
    raise exception 'Payroll karyawan ini sudah %', v_item.individual_status;
  end if;

  if v_item.pay_type = 'sprinter' and v_item.loan_deduction > 0 then
    v_remaining := v_item.loan_deduction;
    for v_loan in
      select * from public.employee_loans
      where sprinter_id = v_item.sprinter_id and status = 'open' and balance > 0
      order by loan_date, created_at for update
    loop
      exit when v_remaining <= 0;
      v_amount := least(v_remaining, v_loan.installment_amount, v_loan.balance);
      if v_amount > 0 then
        insert into public.loan_installments(loan_id,payroll_item_id,amount,note)
        values(v_loan.id,v_item.id,v_amount,'Potongan kasbon payroll individual');
        update public.employee_loans
        set balance=balance-v_amount,
            status=case when balance-v_amount<=0 then 'paid' else 'open' end
        where id=v_loan.id;
        v_remaining := v_remaining-v_amount;
      end if;
    end loop;
    if v_remaining > 0 then
      raise exception 'Saldo atau cicilan kasbon berubah. Muat ulang draft sebelum finalisasi.';
    end if;
  end if;

  if v_item.penalty_deduction > 0 then
    v_remaining := v_item.penalty_deduction;
    for v_penalty in
      select * from public.employee_penalties
      where status='open' and balance>0 and installment_amount>0
        and ((v_item.sprinter_id is not null and sprinter_id=v_item.sprinter_id)
          or (v_item.freelancer_id is not null and freelancer_id=v_item.freelancer_id))
      order by penalty_date, created_at for update
    loop
      exit when v_remaining <= 0;
      v_amount := least(v_remaining,v_penalty.installment_amount,v_penalty.balance);
      if v_amount > 0 then
        insert into public.penalty_installments(penalty_id,payroll_item_id,amount,note)
        values(v_penalty.id,v_item.id,v_amount,'Potongan denda payroll individual');
        update public.employee_penalties
        set balance=balance-v_amount,
            status=case when balance-v_amount<=0 then 'paid' else 'open' end
        where id=v_penalty.id;
        v_remaining := v_remaining-v_amount;
      end if;
    end loop;
    if v_remaining > 0 then
      raise exception 'Saldo atau cicilan denda berubah. Muat ulang draft sebelum finalisasi.';
    end if;
  end if;

  update public.payroll_items
  set individual_status='final', finalized_at=now()
  where id=p_item_id and individual_status='draft';
end;
$function$;

-- Finalisasi massal melewati item yang sudah difinalisasi individual.
create or replace function public.finalize_payroll(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_run public.payroll_runs%rowtype;
  v_item record;
begin
  if not public.has_role(array['admin','finance']) then
    raise exception 'Tidak memiliki izin finalisasi payroll';
  end if;
  select * into v_run from public.payroll_runs where id=p_run_id for update;
  if not found then raise exception 'Payroll tidak ditemukan'; end if;
  if v_run.status <> 'draft' then raise exception 'Payroll bukan berstatus draft'; end if;

  for v_item in
    select id from public.payroll_items
    where payroll_run_id=p_run_id and individual_status='draft'
    order by created_at, person_name
  loop
    perform public.finalize_payroll_item(v_item.id);
  end loop;

  update public.payroll_runs set status='locked' where id=p_run_id;
end;
$function$;

create or replace function public.mark_payroll_item_paid(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.has_role(array['admin','finance']) then
    raise exception 'Tidak memiliki izin mengubah status pembayaran';
  end if;
  update public.payroll_items
  set individual_status='paid', paid_at=now()
  where id=p_item_id and individual_status='final';
  if not found then
    raise exception 'Item payroll tidak ditemukan atau belum difinalisasi';
  end if;
end;
$function$;

-- Fungsi lama tetap kompatibel: tandai semua item final sebagai paid saat run dibayar.
create or replace function public.mark_payroll_paid(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.has_role(array['admin','finance']) then
    raise exception 'Tidak memiliki izin mengubah status pembayaran';
  end if;
  update public.payroll_runs set status='paid'
  where id=p_run_id and status='locked';
  if not found then
    raise exception 'Payroll tidak ditemukan atau belum difinalisasi';
  end if;
  update public.payroll_items
  set individual_status='paid', paid_at=coalesce(paid_at,now())
  where payroll_run_id=p_run_id and individual_status='final';
end;
$function$;

-- Simpan draft versi aman: jangan hapus item yang sudah final/dibayar.
create or replace function public.save_payroll_draft(
  p_period_start date, p_period_end date, p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_run public.payroll_runs%rowtype;
  v_item jsonb;
  v_sprinter_id uuid;
  v_freelancer_id uuid;
  v_gross numeric(14,2);
  v_bonus numeric(14,2);
  v_loan numeric(14,2);
  v_penalty numeric(14,2);
  v_net numeric(14,2);
begin
  if not public.has_role(array['admin','finance','operations']) then
    raise exception 'Tidak memiliki izin menyimpan draft payroll';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start then
    raise exception 'Periode payroll tidak valid';
  end if;
  if jsonb_typeof(p_items)<>'array' then raise exception 'Data payroll tidak valid'; end if;

  select * into v_run from public.payroll_runs
  where period_start=p_period_start and period_end=p_period_end for update;

  if found then
    if v_run.status<>'draft' then raise exception 'Periode ini sudah difinalisasi atau dibayar'; end if;
    delete from public.payroll_items
    where payroll_run_id=v_run.id and individual_status='draft';
  else
    insert into public.payroll_runs(period_start,period_end,status,created_by)
    values(p_period_start,p_period_end,'draft',auth.uid()) returning * into v_run;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_sprinter_id := nullif(v_item->>'sprinter_id','')::uuid;
    v_freelancer_id := nullif(v_item->>'freelancer_id','')::uuid;

    -- Item yang sudah final/paid dipertahankan, tidak dibuat ulang.
    if exists (
      select 1 from public.payroll_items
      where payroll_run_id=v_run.id
        and lower(trim(person_name))=lower(trim(v_item->>'person_name'))
        and individual_status in ('final','paid')
    ) then
      continue;
    end if;

    v_gross := greatest(0,coalesce((v_item->>'gross_amount')::numeric,0));
    v_bonus := greatest(0,coalesce((v_item->>'attendance_bonus')::numeric,0));

    select coalesce(sum(least(balance,installment_amount)),0) into v_loan
    from public.employee_loans
    where status='open' and balance>0 and installment_amount>0
      and ((v_sprinter_id is not null and sprinter_id=v_sprinter_id)
        or (v_freelancer_id is not null and freelancer_id=v_freelancer_id));
    v_loan := greatest(0,least(v_loan,v_gross));

    select coalesce(sum(least(balance,installment_amount)),0) into v_penalty
    from public.employee_penalties
    where status='open' and balance>0 and installment_amount>0
      and ((v_sprinter_id is not null and sprinter_id=v_sprinter_id)
        or (v_freelancer_id is not null and freelancer_id=v_freelancer_id));
    v_penalty := greatest(0,least(v_penalty,greatest(0,v_gross-v_loan)));
    v_net := greatest(0,v_gross-v_loan-v_penalty);

    insert into public.payroll_items(
      payroll_run_id,sprinter_id,freelancer_id,person_name,pay_type,basic_salary,
      ttd_weight_kg,ttd_count,fee_per_kg,package_count,fee_per_package,
      attendance_bonus,gross_amount,loan_deduction,penalty_deduction,net_amount,
      monthly_salary,prorata_days,calendar_days,employment_start_date,employment_end_date
    ) values(
      v_run.id,v_sprinter_id,v_freelancer_id,v_item->>'person_name',v_item->>'pay_type',
      coalesce((v_item->>'basic_salary')::numeric,0),
      coalesce((v_item->>'ttd_weight_kg')::numeric,0),
      coalesce((v_item->>'ttd_count')::integer,0),
      coalesce((v_item->>'fee_per_kg')::numeric,0),
      coalesce((v_item->>'package_count')::integer,0),
      coalesce((v_item->>'fee_per_package')::numeric,0),
      v_bonus,v_gross,v_loan,v_penalty,v_net,
      coalesce((v_item->>'monthly_salary')::numeric,0),
      coalesce((v_item->>'prorata_days')::integer,0),
      coalesce((v_item->>'calendar_days')::integer,0),
      nullif(v_item->>'employment_start_date','')::date,
      nullif(v_item->>'employment_end_date','')::date
    );
  end loop;
  return v_run.id;
end;
$function$;
