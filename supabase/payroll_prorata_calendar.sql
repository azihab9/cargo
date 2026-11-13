-- CargoFlow: Calendar-day salary prorata
-- Run once in Supabase SQL Editor before using the updated app.
-- Existing employees keep NULL dates and are treated as employed throughout each payroll period.
alter table public.sprinters
  add column if not exists employment_start_date date,
  add column if not exists employment_end_date date;

alter table public.office_staff
  add column if not exists employment_start_date date,
  add column if not exists employment_end_date date;

alter table public.payroll_items
  add column if not exists monthly_salary numeric(14,2) not null default 0,
  add column if not exists prorata_days integer not null default 0,
  add column if not exists calendar_days integer not null default 0,
  add column if not exists employment_start_date date,
  add column if not exists employment_end_date date;

alter table public.sprinters
  drop constraint if exists sprinters_employment_dates_check;
alter table public.sprinters
  add constraint sprinters_employment_dates_check
  check (employment_end_date is null or employment_start_date is null or employment_end_date >= employment_start_date);

alter table public.office_staff
  drop constraint if exists office_staff_employment_dates_check;
alter table public.office_staff
  add constraint office_staff_employment_dates_check
  check (employment_end_date is null or employment_start_date is null or employment_end_date >= employment_start_date);
