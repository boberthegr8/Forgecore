-- Forge Core: Manufacturing v1
-- Canonical work orders and production operations linked to commercial quote/takeoff lineage.

create table if not exists public.work_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  quote_id uuid references public.quotes(id) on delete set null,
  work_order_number text not null,
  product_type text not null,
  title text,
  status text not null default 'released',
  priority integer not null default 3,
  due_date date,
  notes text,
  source text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, work_order_number),
  check (priority between 1 and 5)
);

create table if not exists public.work_order_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  quote_item_id uuid references public.quote_items(id) on delete set null,
  takeoff_item_id uuid references public.takeoff_items(id) on delete set null,
  line_number integer,
  sku text,
  description text not null,
  quantity_required numeric not null default 0,
  quantity_completed numeric not null default 0,
  unit text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (quantity_required >= 0),
  check (quantity_completed >= 0)
);

create table if not exists public.production_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  sequence integer not null,
  operation_type text not null,
  station text,
  status text not null default 'queued',
  quantity_planned numeric not null default 0,
  quantity_completed numeric not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (work_order_id, sequence),
  check (sequence >= 1),
  check (quantity_planned >= 0),
  check (quantity_completed >= 0)
);

create index if not exists idx_work_orders_org_status_due on public.work_orders(organization_id, status, due_date);
create index if not exists idx_work_orders_location on public.work_orders(location_id);
create index if not exists idx_work_orders_project on public.work_orders(project_id);
create index if not exists idx_work_orders_quote on public.work_orders(quote_id);
create index if not exists idx_work_orders_created_by on public.work_orders(created_by);
create index if not exists idx_work_order_items_org on public.work_order_items(organization_id);
create index if not exists idx_work_order_items_work_order on public.work_order_items(work_order_id);
create index if not exists idx_work_order_items_quote_item on public.work_order_items(quote_item_id);
create index if not exists idx_work_order_items_takeoff_item on public.work_order_items(takeoff_item_id);
create index if not exists idx_production_operations_org_status on public.production_operations(organization_id, status);
create index if not exists idx_production_operations_work_order on public.production_operations(work_order_id, sequence);
create index if not exists idx_production_operations_created_by on public.production_operations(created_by);

drop trigger if exists trg_work_orders_updated_at on public.work_orders;
create trigger trg_work_orders_updated_at before update on public.work_orders for each row execute function private.set_updated_at();
drop trigger if exists trg_production_operations_updated_at on public.production_operations;
create trigger trg_production_operations_updated_at before update on public.production_operations for each row execute function private.set_updated_at();

alter table public.work_orders enable row level security;
alter table public.work_order_items enable row level security;
alter table public.production_operations enable row level security;
revoke all on public.work_orders, public.work_order_items, public.production_operations from anon;
grant select, insert, update, delete on public.work_orders, public.work_order_items, public.production_operations to authenticated;

create policy work_orders_select_org on public.work_orders for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_orders.organization_id and m.user_id=(select auth.uid()) and m.status='active')
);
create policy work_orders_insert_org on public.work_orders for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_orders.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
);
create policy work_orders_update_org on public.work_orders for update to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_orders.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
) with check (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_orders.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
);
create policy work_orders_delete_admin on public.work_orders for delete to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_orders.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner'::public.forge_member_role,'admin'::public.forge_member_role))
);

create policy work_order_items_select_org on public.work_order_items for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_order_items.organization_id and m.user_id=(select auth.uid()) and m.status='active')
);
create policy work_order_items_insert_org on public.work_order_items for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_order_items.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
);
create policy work_order_items_update_org on public.work_order_items for update to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_order_items.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
) with check (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_order_items.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
);
create policy work_order_items_delete_admin on public.work_order_items for delete to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=work_order_items.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner'::public.forge_member_role,'admin'::public.forge_member_role))
);

create policy production_operations_select_org on public.production_operations for select to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=production_operations.organization_id and m.user_id=(select auth.uid()) and m.status='active')
);
create policy production_operations_insert_org on public.production_operations for insert to authenticated with check (
  exists (select 1 from public.organization_memberships m where m.organization_id=production_operations.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
);
create policy production_operations_update_org on public.production_operations for update to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=production_operations.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
) with check (
  exists (select 1 from public.organization_memberships m where m.organization_id=production_operations.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role<>'viewer'::public.forge_member_role)
);
create policy production_operations_delete_admin on public.production_operations for delete to authenticated using (
  exists (select 1 from public.organization_memberships m where m.organization_id=production_operations.organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.role in ('owner'::public.forge_member_role,'admin'::public.forge_member_role))
);

create or replace function public.commit_work_order_v1(
  p_organization_id uuid,
  p_location_id uuid,
  p_quote_id uuid,
  p_work_order_number text,
  p_product_type text,
  p_title text,
  p_priority integer,
  p_due_date date,
  p_notes text,
  p_items jsonb
) returns table(work_order_id uuid, item_count integer, operation_count integer)
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_project uuid;
  v_wo uuid;
  v_item jsonb;
  v_qi public.quote_items%rowtype;
  v_takeoff_item uuid;
  v_count integer := 0;
  v_ops integer := 0;
  v_total_qty numeric := 0;
  v_type text := lower(trim(p_product_type));
  v_routes text[];
  v_route text;
  v_seq integer := 0;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.organization_memberships m where m.organization_id=p_organization_id and m.user_id=v_user and m.status='active' and m.role<>'viewer'::public.forge_member_role) then raise exception 'Active manufacturing membership required'; end if;
  if p_location_id is not null and not exists(select 1 from public.locations l where l.id=p_location_id and l.organization_id=p_organization_id and l.status='active') then raise exception 'Invalid location'; end if;
  select q.project_id into v_project from public.quotes q where q.id=p_quote_id and q.organization_id=p_organization_id; if not found then raise exception 'Quote not found in organization'; end if;
  if nullif(trim(p_work_order_number),'') is null then raise exception 'Work order number required'; end if;
  if exists(select 1 from public.work_orders w where w.organization_id=p_organization_id and lower(w.work_order_number)=lower(trim(p_work_order_number))) then raise exception 'Work order number already exists'; end if;
  if coalesce(p_priority,3) not between 1 and 5 then raise exception 'Priority must be between 1 and 5'; end if;
  if v_type not in ('trusses','wall_panels','ewp','stairs','mixed') then raise exception 'Unsupported product type'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>500 then raise exception 'Work order must contain 1 to 500 quote lines'; end if;

  insert into public.work_orders(organization_id,location_id,project_id,quote_id,work_order_number,product_type,title,status,priority,due_date,notes,source,metadata,created_by)
  values(p_organization_id,p_location_id,v_project,p_quote_id,trim(p_work_order_number),v_type,coalesce(nullif(trim(p_title),''),trim(p_work_order_number)),'released',coalesce(p_priority,3),p_due_date,p_notes,'forge-mfg',jsonb_build_object('quote_id',p_quote_id),v_user)
  returning id into v_wo;

  for v_item in select value from jsonb_array_elements(p_items) loop
    select qi.* into v_qi
    from public.quote_items qi
    join public.quote_revisions qr on qr.id=qi.quote_revision_id
    join public.quotes q on q.id=qr.quote_id and q.current_revision=qr.revision_number
    where qi.id=(v_item->>'quote_item_id')::uuid and qi.organization_id=p_organization_id and q.id=p_quote_id;
    if not found then raise exception 'Work order line must reference a current quote item'; end if;
    begin v_takeoff_item:=nullif(v_qi.metadata->>'takeoff_item_id','')::uuid; exception when others then v_takeoff_item:=null; end;
    insert into public.work_order_items(organization_id,work_order_id,quote_item_id,takeoff_item_id,line_number,sku,description,quantity_required,unit,metadata)
    values(p_organization_id,v_wo,v_qi.id,v_takeoff_item,v_count+1,v_qi.sku,v_qi.description,coalesce(v_qi.quantity,0),v_qi.unit,jsonb_build_object('quote_item_metadata',v_qi.metadata));
    v_total_qty:=v_total_qty+coalesce(v_qi.quantity,0); v_count:=v_count+1;
  end loop;

  v_routes := case v_type
    when 'trusses' then array['Cutting','Assembly','Quality Check','Stacking']
    when 'wall_panels' then array['Cutting','Framing','Sheathing','Quality Check','Stacking']
    when 'ewp' then array['Picking / Cutting','Quality Check','Packaging']
    when 'stairs' then array['Cutting','Assembly','Quality Check','Packaging']
    else array['Preparation','Production','Quality Check','Staging'] end;

  foreach v_route in array v_routes loop
    v_seq:=v_seq+1;
    insert into public.production_operations(organization_id,work_order_id,sequence,operation_type,status,quantity_planned,metadata,created_by)
    values(p_organization_id,v_wo,v_seq,v_route,'queued',v_total_qty,jsonb_build_object('product_type',v_type),v_user);
    v_ops:=v_ops+1;
  end loop;

  insert into public.events(organization_id,location_id,entity_type,entity_id,action,payload,source,actor_user_id)
  values(p_organization_id,p_location_id,'work_order',v_wo,'created',jsonb_build_object('work_order_number',trim(p_work_order_number),'quote_id',p_quote_id,'product_type',v_type,'item_count',v_count,'operation_count',v_ops),'forge-mfg',v_user);
  return query select v_wo,v_count,v_ops;
end $$;

revoke all on function public.commit_work_order_v1(uuid,uuid,uuid,text,text,text,integer,date,text,jsonb) from public,anon;
grant execute on function public.commit_work_order_v1(uuid,uuid,uuid,text,text,text,integer,date,text,jsonb) to authenticated;

create or replace function public.update_production_operation_v1(
  p_operation_id uuid,
  p_status text,
  p_station text,
  p_quantity_completed numeric,
  p_notes text
) returns table(operation_id uuid, work_order_id uuid, work_order_status text)
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid:=auth.uid();
  v_org uuid;
  v_wo uuid;
  v_old_status text;
  v_new_status text;
  v_qty_plan numeric;
  v_qty_done numeric;
  v_wo_status text;
begin
  select o.organization_id,o.work_order_id,o.status,o.quantity_planned into v_org,v_wo,v_old_status,v_qty_plan from public.production_operations o where o.id=p_operation_id;
  if not found then raise exception 'Production operation not found'; end if;
  if v_user is null or not exists(select 1 from public.organization_memberships m where m.organization_id=v_org and m.user_id=v_user and m.status='active' and m.role<>'viewer'::public.forge_member_role) then raise exception 'Active manufacturing membership required'; end if;
  v_new_status:=coalesce(nullif(lower(trim(p_status)),''),v_old_status);
  if v_new_status not in ('queued','in_progress','completed','blocked','cancelled') then raise exception 'Unsupported production status'; end if;
  v_qty_done:=coalesce(p_quantity_completed,(select quantity_completed from public.production_operations where id=p_operation_id));
  if v_qty_done<0 or v_qty_done>v_qty_plan then raise exception 'Completed quantity must be between 0 and planned quantity'; end if;
  update public.production_operations set status=v_new_status,station=case when p_station is null then station else nullif(trim(p_station),'') end,quantity_completed=v_qty_done,notes=case when p_notes is null then notes else p_notes end,started_at=case when v_new_status='in_progress' and started_at is null then now() else started_at end,completed_at=case when v_new_status='completed' then coalesce(completed_at,now()) else null end where id=p_operation_id;
  if not exists(select 1 from public.production_operations o where o.work_order_id=v_wo and o.status not in ('completed','cancelled')) then v_wo_status:='completed';
  elsif exists(select 1 from public.production_operations o where o.work_order_id=v_wo and o.status in ('in_progress','completed','blocked')) then v_wo_status:='in_production';
  else v_wo_status:='released'; end if;
  update public.work_orders set status=v_wo_status where id=v_wo;
  if v_wo_status='completed' then update public.work_order_items set quantity_completed=quantity_required where work_order_id=v_wo; end if;
  insert into public.events(organization_id,location_id,entity_type,entity_id,action,payload,source,actor_user_id)
  select v_org,w.location_id,'production_operation',p_operation_id,case when v_old_status is distinct from v_new_status then 'status_changed' else 'updated' end,jsonb_build_object('work_order_id',v_wo,'from_status',v_old_status,'to_status',v_new_status,'station',p_station,'quantity_completed',v_qty_done,'work_order_status',v_wo_status),'forge-mfg',v_user from public.work_orders w where w.id=v_wo;
  return query select p_operation_id,v_wo,v_wo_status;
end $$;

revoke all on function public.update_production_operation_v1(uuid,text,text,numeric,text) from public,anon;
grant execute on function public.update_production_operation_v1(uuid,text,text,numeric,text) to authenticated;
