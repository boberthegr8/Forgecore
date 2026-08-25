-- Cover Purchasing v1 foreign keys reported by the Supabase advisor.
create index if not exists idx_purchase_order_items_org on public.purchase_order_items(organization_id);
create index if not exists idx_purchase_orders_created_by on public.purchase_orders(created_by);
create index if not exists idx_purchase_orders_location on public.purchase_orders(location_id);
create index if not exists idx_purchase_receipt_items_org on public.purchase_receipt_items(organization_id);
create index if not exists idx_purchase_receipts_created_by on public.purchase_receipts(created_by);
create index if not exists idx_purchase_receipts_org on public.purchase_receipts(organization_id);
create index if not exists idx_vendors_created_by on public.vendors(created_by);
