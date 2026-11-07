-- CargoFlow: simpan waktu TTD lengkap untuk filter tagihan berdasarkan tanggal + jam
alter table public.cash_report_items
  add column if not exists ttd_at timestamp without time zone;

comment on column public.cash_report_items.ttd_at is
  'Waktu tanda terima asli dari laporan TTD J&T Cargo (waktu lokal outlet).';

-- Data lama tidak memiliki jam TTD. Biarkan NULL agar tidak mengarang jam;
-- unggah ulang laporan Excel untuk mengisi waktu TTD yang sebenarnya.
