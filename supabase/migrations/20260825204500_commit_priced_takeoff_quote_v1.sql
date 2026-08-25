create or replace function public.commit_priced_takeoff_quote_v1(
  p_organization_id uuid,
  p_location_id uuid,
  p_takeoff_id uuid,
  p_quote_number text,
  p_title text,
  p_customer_id uuid,
  p_project_id uuid,
  p_tax_rate numeric,
  p_items jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_member_role forge_member_role;
  v_takeoff public.takeoffs%rowtype;
  v_source_item public.takeoff_items%rowtype;
  v_quote_id uuid := gen_random_uuid();
  v_revision_id uuid := gen_random_uuid();
  v_location_id uuid;
  v_project_id uuid;
  v_project_customer_id uuid;
  v_customer_id uuid;
  v_item jsonb;
  v_takeoff_item_id uuid;
  v_quantity numeric;
  v_unit_cost numeric;
  v_unit_sell numeric;
  v_line_total numeric;
  v_subtotal numeric := 0;
  v_cost_total numeric := 0;
  v_tax numeric := 0;
  v_total numeric := 0;
  v_margin numeric := 0;
  v_tax_rate numeric := coalesce(p_tax_rate, 0);
  v_item_count integer;
  v_line_number integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required.' using errcode = '28000';
  end if;

  select m.role
    into v_member_role
  from public.organization_memberships m
  where m.organization_id = p_organization_id
    and m.user_id = v_user_id
    and m.status = 'active'
  limit 1;

  if v_member_role is null then
    raise exception 'Active Forge organization membership required.' using errcode = '42501';
  end if;

  if v_member_role = 'viewer'::forge_member_role then
    raise exception 'Viewer members cannot create quotes.' using errcode = '42501';
  end if;

  if nullif(btrim(p_quote_number), '') is null or length(btrim(p_quote_number)) > 80 then
    raise exception 'Quote number is required and must be 80 characters or fewer.' using errcode = '22023';
  end if;

  if v_tax_rate < 0 or v_tax_rate > 1 then
    raise exception 'Tax rate must be between 0 and 1.' using errcode = '22023';
  end if;

  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'Items must be a JSON array.' using errcode = '22023';
  end if;

  v_item_count := jsonb_array_length(p_items);
  if v_item_count < 1 or v_item_count > 1000 then
    raise exception 'Quote must contain between 1 and 1000 priced takeoff lines.' using errcode = '22023';
  end if;

  select t.*
    into v_takeoff
  from public.takeoffs t
  where t.id = p_takeoff_id
    and t.organization_id = p_organization_id;

  if not found then
    raise exception 'Takeoff not found in this Forge organization.' using errcode = '42501';
  end if;

  v_location_id := coalesce(p_location_id, v_takeoff.location_id);
  if v_location_id is not null and not exists (
    select 1 from public.locations l
    where l.id = v_location_id
      and l.organization_id = p_organization_id
  ) then
    raise exception 'Location does not belong to this Forge organization.' using errcode = '42501';
  end if;

  v_project_id := coalesce(p_project_id, v_takeoff.project_id);
  if v_project_id is not null then
    select pr.customer_id
      into v_project_customer_id
    from public.projects pr
    where pr.id = v_project_id
      and pr.organization_id = p_organization_id;

    if not found then
      raise exception 'Project does not belong to this Forge organization.' using errcode = '42501';
    end if;
  end if;

  if p_customer_id is not null
     and v_project_customer_id is not null
     and p_customer_id <> v_project_customer_id then
    raise exception 'Customer does not match the selected project.' using errcode = '22023';
  end if;

  v_customer_id := coalesce(p_customer_id, v_project_customer_id);
  if v_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = v_customer_id
      and c.organization_id = p_organization_id
  ) then
    raise exception 'Customer does not belong to this Forge organization.' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.quotes q
    where q.organization_id = p_organization_id
      and lower(q.quote_number) = lower(btrim(p_quote_number))
  ) then
    raise exception 'Quote number already exists in this Forge organization.' using errcode = '23505';
  end if;

  insert into public.quotes (
    id, organization_id, location_id, customer_id, project_id,
    quote_number, status, current_revision, title, description,
    currency, subtotal, tax, total, quote_date, source, metadata, created_by
  ) values (
    v_quote_id, p_organization_id, v_location_id, v_customer_id, v_project_id,
    btrim(p_quote_number), 'draft', 0, nullif(btrim(p_title), ''), nullif(btrim(p_title), ''),
    'CAD', 0, 0, 0, current_date, 'forge-quoter',
    jsonb_build_object(
      'source_takeoff_id', p_takeoff_id,
      'tax_rate', v_tax_rate
    ),
    v_user_id
  );

  insert into public.quote_revisions (
    id, organization_id, quote_id, revision_number,
    subtotal, tax, total, description, raw_items, metadata, created_by
  ) values (
    v_revision_id, p_organization_id, v_quote_id, 0,
    0, 0, 0, nullif(btrim(p_title), ''), p_items,
    jsonb_build_object(
      'source', 'forge-quoter',
      'source_takeoff_id', p_takeoff_id,
      'tax_rate', v_tax_rate
    ),
    v_user_id
  );

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    begin
      v_takeoff_item_id := nullif(v_item ->> 'takeoff_item_id', '')::uuid;
    exception when others then
      raise exception 'Every priced line must contain a valid takeoff_item_id.' using errcode = '22023';
    end;

    if v_takeoff_item_id is null then
      raise exception 'Every priced line must contain a takeoff_item_id.' using errcode = '22023';
    end if;

    select ti.*
      into v_source_item
    from public.takeoff_items ti
    where ti.id = v_takeoff_item_id
      and ti.takeoff_id = p_takeoff_id
      and ti.organization_id = p_organization_id;

    if not found then
      raise exception 'A priced line does not belong to the selected takeoff.' using errcode = '42501';
    end if;

    begin
      v_quantity := coalesce(nullif(v_item ->> 'quantity', '')::numeric, v_source_item.quantity);
      v_unit_cost := coalesce(nullif(v_item ->> 'unit_cost', '')::numeric, 0);
      v_unit_sell := coalesce(nullif(v_item ->> 'unit_sell', '')::numeric, 0);
    exception when others then
      raise exception 'Quantity, unit cost, and unit sell must be numeric.' using errcode = '22023';
    end;

    if v_quantity < 0 or v_quantity > 1000000000 then
      raise exception 'Quantity is outside the supported range.' using errcode = '22023';
    end if;
    if v_unit_cost < 0 or v_unit_cost > 1000000000 then
      raise exception 'Unit cost is outside the supported range.' using errcode = '22023';
    end if;
    if v_unit_sell < 0 or v_unit_sell > 1000000000 then
      raise exception 'Unit sell is outside the supported range.' using errcode = '22023';
    end if;

    v_line_number := v_line_number + 1;
    v_line_total := round(v_quantity * v_unit_sell, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_cost_total := v_cost_total + round(v_quantity * v_unit_cost, 2);

    insert into public.quote_items (
      organization_id, quote_revision_id, line_number, sku, description,
      quantity, unit, unit_cost, unit_sell, line_total, metadata
    ) values (
      p_organization_id, v_revision_id, v_line_number,
      v_source_item.sku, v_source_item.description,
      v_quantity, v_source_item.unit, v_unit_cost, v_unit_sell, v_line_total,
      coalesce(v_source_item.metadata, '{}'::jsonb) || jsonb_build_object(
        'takeoff_item_id', v_source_item.id,
        'takeoff_id', p_takeoff_id,
        'takeoff_category', v_source_item.category
      )
    );
  end loop;

  v_subtotal := round(v_subtotal, 2);
  v_cost_total := round(v_cost_total, 2);
  v_tax := round(v_subtotal * v_tax_rate, 2);
  v_total := v_subtotal + v_tax;
  if v_subtotal > 0 then
    v_margin := round(((v_subtotal - v_cost_total) / v_subtotal) * 100, 4);
  end if;

  update public.quote_revisions
  set subtotal = v_subtotal,
      tax = v_tax,
      total = v_total,
      metadata = metadata || jsonb_build_object(
        'cost_total', v_cost_total,
        'gross_margin_percent', v_margin,
        'item_count', v_item_count
      )
  where id = v_revision_id;

  update public.quotes
  set subtotal = v_subtotal,
      tax = v_tax,
      total = v_total,
      metadata = metadata || jsonb_build_object(
        'cost_total', v_cost_total,
        'gross_margin_percent', v_margin,
        'item_count', v_item_count
      ),
      updated_at = now()
  where id = v_quote_id;

  insert into public.events (
    organization_id, location_id, entity_type, entity_id,
    action, payload, source, actor_user_id
  ) values (
    p_organization_id, v_location_id, 'quote', v_quote_id,
    'created_from_takeoff',
    jsonb_build_object(
      'quote_number', btrim(p_quote_number),
      'revision_number', 0,
      'takeoff_id', p_takeoff_id,
      'subtotal', v_subtotal,
      'cost_total', v_cost_total,
      'gross_margin_percent', v_margin,
      'item_count', v_item_count
    ),
    'forge-quoter', v_user_id
  );

  return jsonb_build_object(
    'quote_id', v_quote_id,
    'quote_revision_id', v_revision_id,
    'quote_number', btrim(p_quote_number),
    'item_count', v_item_count,
    'subtotal', v_subtotal,
    'cost_total', v_cost_total,
    'tax', v_tax,
    'total', v_total,
    'gross_margin_percent', v_margin
  );
end;
$$;

revoke all on function public.commit_priced_takeoff_quote_v1(uuid, uuid, uuid, text, text, uuid, uuid, numeric, jsonb) from public;
revoke all on function public.commit_priced_takeoff_quote_v1(uuid, uuid, uuid, text, text, uuid, uuid, numeric, jsonb) from anon;
grant execute on function public.commit_priced_takeoff_quote_v1(uuid, uuid, uuid, text, text, uuid, uuid, numeric, jsonb) to authenticated;
