-- Follow-up to purchasing_operations_v1.
-- Production creation already includes this column; keep the migration ledger explicit/idempotent.
alter table public.vendors add column if not exists source text;
