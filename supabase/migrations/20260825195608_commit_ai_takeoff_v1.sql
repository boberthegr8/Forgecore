create or replace function public.commit_ai_takeoff_v1(
  p_organization_id uuid,
  p_location_id uuid default null,
  p_project_id uuid default null,
  p_scope_id uuid default null,
  p_title text default null,
  p_assumptions jsonb default '{}'::jsonb,
  p_totals jsonb default '{}'::jsonb,
  p_items jsonb default '[]'::jsonb
)
returns table(takeoff_id uuid, item_count integer)
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_takeoff_id uuid := gen_random_uuid();
  v_item_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = p_organization_id
      and m.user_id = v_user_id
      and m.status = 'active'
      and m.role <> 'viewer'::forge_member_role
  ) then
    raise exception 'Active non-viewer membership required for this organization';
  end if;

  if p_location_id is not null and not exists (
    select 1 from public.locations l
    where l.id = p_location_id and l.organization_id = p_organization_id
  ) then
    raise exception 'Location does not belong to organization';
  end if;

  if p_project_id is not null and not exists (
    select 1 from public.projects p
    where p.id = p_project_id and p.organization_id = p_organization_id
  ) then
    raise exception 'Project does not belong to organization';
  end if;

  if p_scope_id is not null and not exists (
    select 1 from public.scopes s
    where s.id = p_scope_id
      and s.organization_id = p_organization_id
      and (p_project_id is null or s.project_id is null or s.project_id = p_project_id)
  ) then
    raise exception 'Scope does not belong to organization/project';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Items must be a JSON array';
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) < 1 then
    raise exception 'At least one takeoff item is required';
  end if;

  if jsonb_array_length(p_items) > 2000 then
    raise exception 'Takeoff exceeds 2000 item safety limit';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) item
    where jsonb_typeof(item) <> 'object'
       or btrim(coalesce(item->>'description','')) = ''
  ) then
    raise exception 'Every takeoff item requires a description';
  end if;

  insert into public.takeoffs (
    id, organization_id, location_id, project_id, scope_id,
    title, status, assumptions, totals, source, created_by
  ) values (
    v_takeoff_id,
    p_organization_id,
    p_location_id,
    p_project_id,
    p_scope_id,
    nullif(btrim(coalesce(p_title,'')),''),
    'draft',
    coalesce(p_assumptions, '{}'::jsonb),
    coalesce(p_totals, '{}'::jsonb),
    'forge-quoter',
    v_user_id
  );

  insert into public.takeoff_items (
    organization_id, takeoff_id, category, sku, description, unit, quantity, metadata
  )
  select
    p_organization_id,
    v_takeoff_id,
    nullif(btrim(x.category),''),
    nullif(btrim(x.sku),''),
    btrim(x.description),
    nullif(btrim(x.unit),''),
    coalesce(x.quantity, 0),
    coalesce(x.metadata, '{}'::jsonb)
  from jsonb_to_recordset(p_items) as x(
    category text,
    sku text,
    description text,
    unit text,
    quantity numeric,
    metadata jsonb
  );

  get diagnostics v_item_count = row_count;

  update public.takeoffs
  set totals = coalesce(p_totals, '{}'::jsonb) || jsonb_build_object('item_count', v_item_count),
      updated_at = now()
  where id = v_takeoff_id;

  return query select v_takeoff_id, v_item_count;
end;
$$;

revoke all on function public.commit_ai_takeoff_v1(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb) from public;
revoke all on function public.commit_ai_takeoff_v1(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb) from anon;
grant execute on function public.commit_ai_takeoff_v1(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb) to authenticated;
