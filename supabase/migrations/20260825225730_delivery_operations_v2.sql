-- Forge Core: Delivery Operations v2
-- Adds dispatch fields and audited, tenant-safe delivery updates.

alter table public.deliveries
  add column if not exists truck text,
  add column if not exists driver text,
  add column if not exists load_type text,
  add column if not exists stop_sequence integer not null default 1;

create index if not exists idx_deliveries_org_status_schedule
  on public.deliveries(organization_id, status, scheduled_start);
create index if not exists idx_deliveries_created_by on public.deliveries(created_by);

create or replace function public.update_delivery_operations_v1(
  p_delivery_id uuid,
  p_status text,
  p_scheduled_start timestamptz,
  p_scheduled_end timestamptz,
  p_truck text,
  p_driver text,
  p_load_type text,
  p_stop_sequence integer,
  p_notes text
) returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_location uuid;
  v_old_status text;
  v_new_status text;
  v_payload jsonb;
begin
  select d.organization_id, d.location_id, d.status
    into v_org, v_location, v_old_status
  from public.deliveries d
  where d.id = p_delivery_id;

  if not found then
    raise exception 'Delivery not found';
  end if;

  if v_user is null or not exists (
    select 1 from public.organization_memberships m
    where m.organization_id = v_org
      and m.user_id = v_user
      and m.status = 'active'
      and m.role <> 'viewer'::public.forge_member_role
  ) then
    raise exception 'Active operations membership required';
  end if;

  v_new_status := coalesce(nullif(lower(trim(p_status)), ''), v_old_status);
  if v_new_status not in ('planned','confirmed','picked','loaded','in_transit','delivered','cancelled') then
    raise exception 'Unsupported delivery status';
  end if;

  if p_stop_sequence is not null and p_stop_sequence < 1 then
    raise exception 'Stop sequence must be at least 1';
  end if;

  update public.deliveries
  set status = v_new_status,
      scheduled_start = coalesce(p_scheduled_start, scheduled_start),
      scheduled_end = case when p_scheduled_end is null then scheduled_end else p_scheduled_end end,
      truck = case when p_truck is null then truck else nullif(trim(p_truck), '') end,
      driver = case when p_driver is null then driver else nullif(trim(p_driver), '') end,
      load_type = case when p_load_type is null then load_type else nullif(trim(p_load_type), '') end,
      stop_sequence = coalesce(p_stop_sequence, stop_sequence),
      notes = case when p_notes is null then notes else p_notes end
  where id = p_delivery_id;

  v_payload := jsonb_build_object(
    'from_status', v_old_status,
    'to_status', v_new_status,
    'scheduled_start', p_scheduled_start,
    'scheduled_end', p_scheduled_end,
    'truck', p_truck,
    'driver', p_driver,
    'load_type', p_load_type,
    'stop_sequence', p_stop_sequence
  );

  insert into public.events(
    organization_id, location_id, entity_type, entity_id, action,
    payload, source, actor_user_id
  ) values (
    v_org, v_location, 'delivery', p_delivery_id,
    case when v_old_status is distinct from v_new_status then 'status_changed' else 'updated' end,
    v_payload, 'forge-operations', v_user
  );

  return p_delivery_id;
end;
$$;

revoke all on function public.update_delivery_operations_v1(uuid,text,timestamptz,timestamptz,text,text,text,integer,text) from public, anon;
grant execute on function public.update_delivery_operations_v1(uuid,text,timestamptz,timestamptz,text,text,text,integer,text) to authenticated;
