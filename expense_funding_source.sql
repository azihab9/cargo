-- CargoFlow: sumber dana pengeluaran dari setoran COD/DFOD
-- Jalankan sekali di Supabase SQL Editor.
ALTER TABLE public.expenses
ADD COLUMN IF NOT EXISTS source_settlement_date date;

CREATE INDEX IF NOT EXISTS expenses_source_settlement_date_idx
ON public.expenses (source_settlement_date);
