begin;

-- Database-level tenant lineage protection for core parent/child chains.
-- The parent ID remains the business identity; organization_id is added to
-- the foreign key so a child cannot reference a parent from another tenant.

create unique index if not exists uq_scopes_id_organization
  on public.scopes (id, organization_id);
create unique index if not exists uq_takeoffs_id_organization
  on public.takeoffs (id, organization_id);
create unique index if not exists uq_quotes_id_organization
  on public.quotes (id, organization_id);
create unique index if not exists uq_quote_revisions_id_organization
  on public.quote_revisions (id, organization_id);
create unique index if not exists uq_purchase_orders_id_organization
  on public.purchase_orders (id, organization_id);
create unique index if not exists uq_purchase_receipts_id_organization
  on public.purchase_receipts (id, organization_id);
create unique index if not exists uq_purchase_order_items_id_organization
  on public.purchase_order_items (id, organization_id);
create unique index if not exists uq_work_orders_id_organization
  on public.work_orders (id, organization_id);

alter table public.scope_versions
  drop constraint if exists scope_versions_scope_id_fkey;
alter table public.scope_versions
  add constraint scope_versions_scope_id_fkey
  foreign key (scope_id, organization_id)
  references public.scopes (id, organization_id)
  on delete cascade
  not valid;

alter table public.takeoff_items
  drop constraint if exists takeoff_items_takeoff_id_fkey;
alter table public.takeoff_items
  add constraint takeoff_items_takeoff_id_fkey
  foreign key (takeoff_id, organization_id)
  references public.takeoffs (id, organization_id)
  on delete cascade
  not valid;

alter table public.quote_revisions
  drop constraint if exists quote_revisions_quote_id_fkey;
alter table public.quote_revisions
  add constraint quote_revisions_quote_id_fkey
  foreign key (quote_id, organization_id)
  references public.quotes (id, organization_id)
  on delete cascade
  not valid;

alter table public.quote_items
  drop constraint if exists quote_items_quote_revision_id_fkey;
alter table public.quote_items
  add constraint quote_items_quote_revision_id_fkey
  foreign key (quote_revision_id, organization_id)
  references public.quote_revisions (id, organization_id)
  on delete cascade
  not valid;

alter table public.purchase_order_items
  drop constraint if exists purchase_order_items_purchase_order_id_fkey;
alter table public.purchase_order_items
  add constraint purchase_order_items_purchase_order_id_fkey
  foreign key (purchase_order_id, organization_id)
  references public.purchase_orders (id, organization_id)
  on delete cascade
  not valid;

alter table public.purchase_receipts
  drop constraint if exists purchase_receipts_purchase_order_id_fkey;
alter table public.purchase_receipts
  add constraint purchase_receipts_purchase_order_id_fkey
  foreign key (purchase_order_id, organization_id)
  references public.purchase_orders (id, organization_id)
  on delete cascade
  not valid;

alter table public.purchase_receipt_items
  drop constraint if exists purchase_receipt_items_purchase_receipt_id_fkey;
alter table public.purchase_receipt_items
  add constraint purchase_receipt_items_purchase_receipt_id_fkey
  foreign key (purchase_receipt_id, organization_id)
  references public.purchase_receipts (id, organization_id)
  on delete cascade
  not valid;

alter table public.purchase_receipt_items
  drop constraint if exists purchase_receipt_items_purchase_order_item_id_fkey;
alter table public.purchase_receipt_items
  add constraint purchase_receipt_items_purchase_order_item_id_fkey
  foreign key (purchase_order_item_id, organization_id)
  references public.purchase_order_items (id, organization_id)
  on delete restrict
  not valid;

alter table public.work_order_items
  drop constraint if exists work_order_items_work_order_id_fkey;
alter table public.work_order_items
  add constraint work_order_items_work_order_id_fkey
  foreign key (work_order_id, organization_id)
  references public.work_orders (id, organization_id)
  on delete cascade
  not valid;

alter table public.production_operations
  drop constraint if exists production_operations_work_order_id_fkey;
alter table public.production_operations
  add constraint production_operations_work_order_id_fkey
  foreign key (work_order_id, organization_id)
  references public.work_orders (id, organization_id)
  on delete cascade
  not valid;

alter table public.scope_versions validate constraint scope_versions_scope_id_fkey;
alter table public.takeoff_items validate constraint takeoff_items_takeoff_id_fkey;
alter table public.quote_revisions validate constraint quote_revisions_quote_id_fkey;
alter table public.quote_items validate constraint quote_items_quote_revision_id_fkey;
alter table public.purchase_order_items validate constraint purchase_order_items_purchase_order_id_fkey;
alter table public.purchase_receipts validate constraint purchase_receipts_purchase_order_id_fkey;
alter table public.purchase_receipt_items validate constraint purchase_receipt_items_purchase_receipt_id_fkey;
alter table public.purchase_receipt_items validate constraint purchase_receipt_items_purchase_order_item_id_fkey;
alter table public.work_order_items validate constraint work_order_items_work_order_id_fkey;
alter table public.production_operations validate constraint production_operations_work_order_id_fkey;

commit;
