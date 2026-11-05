# CargoFlow — J&T Cargo Area Rantau

CargoFlow is being migrated from a browser-only prototype to a shared web app backed by Supabase.

## Current repository
- Existing prototype: `cargoflow_dashboard_v3.html`
- Database schema: `supabase/schema.sql`

## Supabase setup
1. Open the Supabase project SQL Editor.
2. Run the complete contents of `supabase/schema.sql`.
3. In Authentication, create the first user.
4. Copy that user's UUID from Authentication > Users.
5. Run this in SQL Editor, replacing the UUID:
   `update public.profiles set role = 'admin', full_name = 'Admin CargoFlow' where id = 'USER-UUID';`
6. Keep the `cargoflow-receipts` storage bucket private.

## Frontend configuration
The Supabase project URL and publishable key may be used in browser code. Never put a Supabase secret key or service_role key in this repository. Row Level Security must remain enabled.

## Important
The existing V3 HTML still uses localStorage. Adding the schema does not by itself migrate the UI to cloud storage. The next development step is to connect login, imports, payroll, freelance fees, loans, expenses, and payslip generation to these tables and verify the RLS policies with separate user roles.
