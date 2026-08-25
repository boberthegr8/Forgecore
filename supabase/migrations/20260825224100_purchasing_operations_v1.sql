-- Forge Core: Purchasing + Operations v1
-- Canonical vendor, PO, receiving, and delivery linkage.

create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  name text not null,
  account_number text,
  status text not null default 'active',
  email text,
  phone text,
  address jsonb not null default '{}'::jsonb,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  project_id uuid references public.projects(id) on delete set null,
  quote_id uuid references public.quotes(id) on delete set null,
  po_number text not null,
  status text not null default 'draft',
  order_date date not null default current_date,
  expected_date date,
  currency text not null default 'CAD',
  subtotal numeric not null default 0,
  tax numeric not null default 0,
  total numeric not null default 0,
  notes text,
  source text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, po_number)
);

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  quote_item_id uuid references public.quote_items(id) on delete set null,
  takeoff_item_id uuid references public.takeoff_items(id) on delete set null,
  line_number integer,
  sku text,
  description text not null,
  quantity_ordered numeric not null default 0,
  quantity_received numeric not null default 0,
  unit text,
  unit_cost numeric not null default 0,
  line_total numeric not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (quantity_ordered >= 0),
  check (quantity_received >= 0),
  check (unit_cost >= 0)
);

create table if not exists public.purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  received_at timestamptz not null default now(),
  packing_slip text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.purchase_receipt_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchase_receipt_id uuid not null references public.purchase_receipts(id) on delete cascade,
  purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
  quantity_received numeric not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (quantity_received > 0)
);

alter table public.deliveries
  add column if not exists purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  add column if not exists direction text not null default 'outbound';

create index if not exists idx_vendors_org_name on public.vendors(organization_id, name);
create index if not exists idx_vendors_location on public.vendors(location_id);
create index if not exists idx_purchase_orders_org_status on public.purchase_orders(organization_id, status, expected_date);
create index if not exists idx_purchase_orders_vendor on public.purchase_orders(vendor_id);
create index if not exists idx_purchase_orders_project on public.purchase_orders(project_id);
create index if not exists idx_purchase_orders_quote on public.purchase_orders(quote_id);
create index if not exists idx_purchase_order_items_po on public.purchase_order_items(purchase_order_id);
create index if not exists idx_purchase_order_items_quote_item on public.purchase_order_items(quote_item_id);
create index if not exists idx_purchase_order_items_takeoff_item on public.purchase_order_items(takeoff_item_id);
create index if not exists idx_purchase_receipts_po on public.purchase_receipts(purchase_order_id, received_at desc);
create index if not exists idx_purchase_receipt_items_receipt on public.purchase_receipt_items(purchase_receipt_id);
create index if not exists idx_purchase_receipt_items_po_item on public.purchase_receipt_items(purchase_order_item_id);
create index if not exists idx_deliveries_purchase_order on public.deliveries(purchase_order_id);

-- Keep updated_at semantics consistent with the rest of Forge Core.
drop trigger if exists trg_vendors_updated_at on public.vendors;
create trigger trg_vendors_updated_at before update on public.vendors
for each row execute function private.set_updated_at();

drop trigger if exists trg_purchase_orders_updated_at on public.purchase_orders;
create trigger trg_purchase_orders_updated_at before update on public.purchase_orders
for each row execute function private.set_updated_at();

alter table public.vendors enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.purchase_receipts enable row level security;
alter table public.purchase_receipt_items enable row level security;

revoke all on public.vendors, public.purchase_orders, public.purchase_order_items, public.purchase_receipts, public.purchase_receipt_items from anon;
grant select, insert, update, delete on public.vendors, public.purchase_orders, public.purchase_order_items, public.purchase_receipts, public.purchase_receipt_items to authenticated;

-- Membership-scoped policies. Receipt history is append-only for normal users.
create policy vendors_select_org on public.vendors for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = vendors.organization_id and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy vendors_insert_org on public.vendors for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = vendors.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy vendors_update_org on public.vendors for update to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = vendors.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
) with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = vendors.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy vendors_delete_admin on public.vendors for delete to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = vendors.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role in ('owner'::public.forge_member_role,'admin'::public.forge_member_role))
);

create policy purchase_orders_select_org on public.purchase_orders for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_orders.organization_id and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy purchase_orders_insert_org on public.purchase_orders for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_orders.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy purchase_orders_update_org on public.purchase_orders for update to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_orders.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
) with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_orders.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy purchase_orders_delete_admin on public.purchase_orders for delete to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_orders.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role in ('owner'::public.forge_member_role,'admin'::public.forge_member_role))
);

create policy purchase_order_items_select_org on public.purchase_order_items for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_order_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy purchase_order_items_insert_org on public.purchase_order_items for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_order_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy purchase_order_items_update_org on public.purchase_order_items for update to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_order_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
) with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_order_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy purchase_order_items_delete_admin on public.purchase_order_items for delete to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_order_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role in ('owner'::public.forge_member_role,'admin'::public.forge_member_role))
);

create policy purchase_receipts_select_org on public.purchase_receipts for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_receipts.organization_id and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy purchase_receipts_insert_org on public.purchase_receipts for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_receipts.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);
create policy purchase_receipt_items_select_org on public.purchase_receipt_items for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_receipt_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active')
);
create policy purchase_receipt_items_insert_org on public.purchase_receipt_items for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id = purchase_receipt_items.organization_id and m.user_id = (select auth.uid()) and m.status = 'active' and m.role <> 'viewer'::public.forge_member_role)
);

create or replace function public.commit_purchase_order_v1(
  p_organization_id uuid,
  p_location_id uuid,
  p_quote_id uuid,
  p_vendor_id uuid,
  p_vendor_name text,
  p_po_number text,
  p_expected_date date,
  p_tax_rate numeric,
  p_notes text,
  p_items jsonb
) returns table(purchase_order_id uuid, vendor_id uuid, item_count integer, subtotal numeric, tax numeric, total numeric)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_vendor uuid := p_vendor_id;
  v_project uuid;
  v_subtotal numeric := 0;
  v_tax numeric := 0;
  v_total numeric := 0;
  v_po uuid;
  v_count integer := 0;
  v_item jsonb;
  v_qi public.quote_items%rowtype;
  v_qty numeric;
  v_cost numeric;
  v_takeoff_item uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.organization_memberships m where m.organization_id=p_organization_id and m.user_id=v_user and m.status='active' and m.role <> 'viewer'::public.forge_member_role) then raise exception 'Active purchasing membership required'; end if;
  if p_location_id is not null and not exists (select 1 from public.locations l where l.id=p_location_id and l.organization_id=p_organization_id and l.status='active') then raise exception 'Invalid location'; end if;
  select q.project_id into v_project from public.quotes q where q.id=p_quote_id and q.organization_id=p_organization_id;
  if not found then raise exception 'Quote not found in organization'; end if;
  if nullif(trim(p_po_number),'') is null then raise exception 'PO number required'; end if;
  if exists (select 1 from public.purchase_orders po where po.organization_id=p_organization_id and lower(po.po_number)=lower(trim(p_po_number))) then raise exception 'PO number already exists'; end if;
  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 1 then raise exception 'Tax rate must be between 0 and 1'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 500 then raise exception 'PO must contain 1 to 500 lines'; end if;

  if v_vendor is not null then
    if not exists (select 1 from public.vendors v where v.id=v_vendor and v.organization_id=p_organization_id) then raise exception 'Vendor not found in organization'; end if;
  else
    if nullif(trim(p_vendor_name),'') is null then raise exception 'Vendor required'; end if;
    select v.id into v_vendor from public.vendors v where v.organization_id=p_organization_id and lower(v.name)=lower(trim(p_vendor_name)) limit 1;
    if v_vendor is null then
      insert into public.vendors(organization_id,location_id,name,source,created_by)
      values (p_organization_id,p_location_id,trim(p_vendor_name),'forge-purchasing',v_user)
      returning id into v_vendor;
    end if;
  end if;

  insert into public.purchase_orders(organization_id,location_id,vendor_id,project_id,quote_id,po_number,status,expected_date,notes,source,metadata,created_by)
  values (p_organization_id,p_location_id,v_vendor,v_project,p_quote_id,trim(p_po_number),'ordered',p_expected_date,p_notes,'forge-purchasing',jsonb_build_object('quote_id',p_quote_id),v_user)
  returning id into v_po;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if nullif(v_item->>'quote_item_id','') is null then raise exception 'quote_item_id required'; end if;
    select qi.* into v_qi
    from public.quote_items qi
    join public.quote_revisions qr on qr.id=qi.quote_revision_id
    join public.quotes q on q.id=qr.quote_id and q.current_revision=qr.revision_number
    where qi.id=(v_item->>'quote_item_id')::uuid and qi.organization_id=p_organization_id and q.id=p_quote_id;
    if not found then raise exception 'PO line must reference a current quote item'; end if;
    v_qty := coalesce(nullif(v_item->>'quantity','')::numeric, v_qi.quantity, 0);
    v_cost := coalesce(nullif(v_item->>'unit_cost','')::numeric, v_qi.unit_cost, 0);
    if v_qty <= 0 or v_cost < 0 then raise exception 'PO quantity must be positive and cost non-negative'; end if;
    begin v_takeoff_item := nullif(v_qi.metadata->>'takeoff_item_id','')::uuid; exception when others then v_takeoff_item := null; end;
    insert into public.purchase_order_items(organization_id,purchase_order_id,quote_item_id,takeoff_item_id,line_number,sku,description,quantity_ordered,unit,unit_cost,line_total,metadata)
    values (p_organization_id,v_po,v_qi.id,v_takeoff_item,v_count+1,v_qi.sku,v_qi.description,v_qty,v_qi.unit,v_cost,round(v_qty*v_cost,2),jsonb_build_object('quote_revision_id',v_qi.quote_revision_id,'quote_item_metadata',v_qi.metadata));
    v_subtotal := v_subtotal + round(v_qty*v_cost,2);
    v_count := v_count + 1;
  end loop;

  v_tax := round(v_subtotal*p_tax_rate,2);
  v_total := v_subtotal+v_tax;
  update public.purchase_orders set subtotal=v_subtotal,tax=v_tax,total=v_total,metadata=metadata || jsonb_build_object('item_count',v_count,'tax_rate',p_tax_rate) where id=v_po;
  insert into public.events(organization_id,location_id,entity_type,entity_id,action,payload,source,actor_user_id)
  values (p_organization_id,p_location_id,'purchase_order',v_po,'created',jsonb_build_object('po_number',trim(p_po_number),'quote_id',p_quote_id,'vendor_id',v_vendor,'item_count',v_count,'total',v_total),'forge-purchasing',v_user);
  return query select v_po,v_vendor,v_count,v_subtotal,v_tax,v_total;
end;
$$;

revoke all on function public.commit_purchase_order_v1(uuid,uuid,uuid,uuid,text,text,date,numeric,text,jsonb) from public, anon;
grant execute on function public.commit_purchase_order_v1(uuid,uuid,uuid,uuid,text,text,date,numeric,text,jsonb) to authenticated;

create or replace function public.receive_purchase_order_v1(
  p_purchase_order_id uuid,
  p_packing_slip text,
  p_notes text,
  p_items jsonb
) returns table(receipt_id uuid, purchase_order_id uuid, status text, received_lines integer)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_location uuid;
  v_receipt uuid;
  v_item jsonb;
  v_po_item public.purchase_order_items%rowtype;
  v_qty numeric;
  v_lines integer := 0;
  v_status text;
begin
  select po.organization_id,po.location_id into v_org,v_location from public.purchase_orders po where po.id=p_purchase_order_id;
  if not found then raise exception 'Purchase order not found'; end if;
  if v_user is null or not exists (select 1 from public.organization_memberships m where m.organization_id=v_org and m.user_id=v_user and m.status='active' and m.role <> 'viewer'::public.forge_member_role) then raise exception 'Active receiving membership required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 500 then raise exception 'Receipt must contain 1 to 500 lines'; end if;
  insert into public.purchase_receipts(organization_id,purchase_order_id,packing_slip,notes,created_by) values (v_org,p_purchase_order_id,nullif(trim(p_packing_slip),''),p_notes,v_user) returning id into v_receipt;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select * into v_po_item from public.purchase_order_items where id=(v_item->>'purchase_order_item_id')::uuid and purchase_order_id=p_purchase_order_id and organization_id=v_org for update;
    if not found then raise exception 'Receipt line does not belong to purchase order'; end if;
    v_qty := coalesce(nullif(v_item->>'quantity_received','')::numeric,0);
    if v_qty <= 0 then raise exception 'Received quantity must be positive'; end if;
    if v_po_item.quantity_received + v_qty > v_po_item.quantity_ordered then raise exception 'Received quantity exceeds ordered quantity for %', v_po_item.description; end if;
    insert into public.purchase_receipt_items(organization_id,purchase_receipt_id,purchase_order_item_id,quantity_received,metadata)
    values (v_org,v_receipt,v_po_item.id,v_qty,jsonb_build_object('previous_received',v_po_item.quantity_received));
    update public.purchase_order_items set quantity_received=quantity_received+v_qty where id=v_po_item.id;
    v_lines := v_lines+1;
  end loop;
  if not exists (select 1 from public.purchase_order_items i where i.purchase_order_id=p_purchase_order_id and i.quantity_received < i.quantity_ordered) then v_status := 'received';
  elsif exists (select 1 from public.purchase_order_items i where i.purchase_order_id=p_purchase_order_id and i.quantity_received > 0) then v_status := 'partial';
  else v_status := 'ordered'; end if;
  update public.purchase_orders set status=v_status where id=p_purchase_order_id;
  insert into public.events(organization_id,location_id,entity_type,entity_id,action,payload,source,actor_user_id)
  values (v_org,v_location,'purchase_order',p_purchase_order_id,'received',jsonb_build_object('receipt_id',v_receipt,'packing_slip',p_packing_slip,'received_lines',v_lines,'status',v_status),'forge-purchasing',v_user);
  return query select v_receipt,p_purchase_order_id,v_status,v_lines;
end;
$$;

revoke all on function public.receive_purchase_order_v1(uuid,text,text,jsonb) from public, anon;
grant execute on function public.receive_purchase_order_v1(uuid,text,text,jsonb) to authenticated;

create or replace function public.schedule_delivery_v1(
  p_organization_id uuid,
  p_location_id uuid,
  p_quote_id uuid,
  p_project_id uuid,
  p_purchase_order_id uuid,
  p_delivery_number text,
  p_direction text,
  p_scheduled_start timestamptz,
  p_scheduled_end timestamptz,
  p_address jsonb,
  p_notes text
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_customer uuid;
  v_project uuid := p_project_id;
  v_quote uuid := p_quote_id;
  v_address jsonb := coalesce(p_address,'{}'::jsonb);
  v_delivery uuid;
begin
  if v_user is null or not exists (select 1 from public.organization_memberships m where m.organization_id=p_organization_id and m.user_id=v_user and m.status='active' and m.role <> 'viewer'::public.forge_member_role) then raise exception 'Active operations membership required'; end if;
  if p_direction not in ('inbound','outbound') then raise exception 'Direction must be inbound or outbound'; end if;
  if p_location_id is not null and not exists (select 1 from public.locations l where l.id=p_location_id and l.organization_id=p_organization_id) then raise exception 'Invalid location'; end if;
  if p_purchase_order_id is not null then
    select coalesce(v_project,po.project_id),coalesce(v_quote,po.quote_id) into v_project,v_quote from public.purchase_orders po where po.id=p_purchase_order_id and po.organization_id=p_organization_id;
    if not found then raise exception 'Purchase order not found in organization'; end if;
  end if;
  if v_quote is not null then
    select q.customer_id,coalesce(v_project,q.project_id) into v_customer,v_project from public.quotes q where q.id=v_quote and q.organization_id=p_organization_id;
    if not found then raise exception 'Quote not found in organization'; end if;
  end if;
  if v_project is not null then
    select coalesce(v_customer,p.customer_id),case when v_address='{}'::jsonb then p.address else v_address end into v_customer,v_address from public.projects p where p.id=v_project and p.organization_id=p_organization_id;
    if not found then raise exception 'Project not found in organization'; end if;
  end if;
  if p_direction='inbound' and v_address='{}'::jsonb and p_location_id is not null then select l.address into v_address from public.locations l where l.id=p_location_id; end if;
  insert into public.deliveries(organization_id,location_id,customer_id,project_id,quote_id,purchase_order_id,delivery_number,status,direction,scheduled_start,scheduled_end,address,notes,metadata,source,created_by)
  values (p_organization_id,p_location_id,v_customer,v_project,v_quote,p_purchase_order_id,nullif(trim(p_delivery_number),''),'planned',p_direction,p_scheduled_start,p_scheduled_end,coalesce(v_address,'{}'::jsonb),p_notes,jsonb_build_object('purchase_order_id',p_purchase_order_id),'forge-operations',v_user)
  returning id into v_delivery;
  insert into public.events(organization_id,location_id,entity_type,entity_id,action,payload,source,actor_user_id)
  values (p_organization_id,p_location_id,'delivery',v_delivery,'scheduled',jsonb_build_object('direction',p_direction,'quote_id',v_quote,'project_id',v_project,'purchase_order_id',p_purchase_order_id,'scheduled_start',p_scheduled_start),'forge-operations',v_user);
  return v_delivery;
end;
$$;

revoke all on function public.schedule_delivery_v1(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb,text) from public, anon;
grant execute on function public.schedule_delivery_v1(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb,text) to authenticated;
