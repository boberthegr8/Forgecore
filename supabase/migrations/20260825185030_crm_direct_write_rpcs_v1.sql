create or replace function public.create_crm_quote_v1(
  p_quote_id uuid,
  p_organization_id uuid,
  p_location_id uuid,
  p_customer_id uuid,
  p_quote_number text,
  p_status text,
  p_description text,
  p_subtotal numeric,
  p_po_number text,
  p_quote_date date,
  p_probability numeric,
  p_margin numeric
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  insert into public.quotes (
    id, organization_id, location_id, customer_id, quote_number, status,
    current_revision, title, description, currency, subtotal, total,
    po_number, quote_date, source, metadata, created_by
  ) values (
    p_quote_id, p_organization_id, p_location_id, p_customer_id, p_quote_number, coalesce(p_status,'draft'),
    0, p_description, p_description, 'CAD', coalesce(p_subtotal,0), coalesce(p_subtotal,0),
    p_po_number, p_quote_date, 'forge-crm',
    jsonb_build_object('probability', coalesce(p_probability,0), 'margin', coalesce(p_margin,0)),
    auth.uid()
  );

  insert into public.quote_revisions (
    organization_id, quote_id, revision_number, subtotal, total, description,
    raw_items, metadata, created_by
  ) values (
    p_organization_id, p_quote_id, 0, coalesce(p_subtotal,0), coalesce(p_subtotal,0), p_description,
    '[]'::jsonb, jsonb_build_object('source','forge-crm'), auth.uid()
  );

  insert into public.events (
    organization_id, location_id, entity_type, entity_id, action, payload, source, actor_user_id
  ) values (
    p_organization_id, p_location_id, 'quote', p_quote_id, 'created',
    jsonb_build_object('quote_number', p_quote_number, 'revision_number', 0), 'forge-crm', auth.uid()
  );

  return p_quote_id;
end;
$$;

grant execute on function public.create_crm_quote_v1(uuid,uuid,uuid,uuid,text,text,text,numeric,text,date,numeric,numeric) to authenticated;

create or replace function public.revise_crm_quote_v1(p_quote_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  q public.quotes%rowtype;
  next_revision integer;
begin
  select * into q from public.quotes where id = p_quote_id;
  if not found then raise exception 'Quote not found'; end if;

  next_revision := coalesce(q.current_revision,0) + 1;

  insert into public.quote_revisions (
    organization_id, quote_id, revision_number, document_id, subtotal, tax, total,
    description, raw_items, metadata, created_by
  ) values (
    q.organization_id, q.id, next_revision, q.source_document_id, q.subtotal, q.tax, q.total,
    q.description, '[]'::jsonb, jsonb_build_object('source','forge-crm-manual-revision'), auth.uid()
  );

  update public.quotes
  set current_revision = next_revision, status = 'revised'
  where id = q.id;

  insert into public.events (
    organization_id, location_id, entity_type, entity_id, action, payload, source, actor_user_id
  ) values (
    q.organization_id, q.location_id, 'quote', q.id, 'revised',
    jsonb_build_object('revision_number', next_revision), 'forge-crm', auth.uid()
  );

  return next_revision;
end;
$$;

grant execute on function public.revise_crm_quote_v1(uuid) to authenticated;

create or replace function public.convert_crm_quote_to_project_v1(
  p_quote_id uuid,
  p_project_id uuid,
  p_project_name text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  q public.quotes%rowtype;
begin
  select * into q from public.quotes where id = p_quote_id;
  if not found then raise exception 'Quote not found'; end if;

  insert into public.projects (
    id, organization_id, location_id, customer_id, name, status, description,
    address, source, metadata, created_by
  ) values (
    p_project_id, q.organization_id, q.location_id, q.customer_id, p_project_name,
    'active', coalesce(q.description, q.title, 'Converted from quote'), '{}'::jsonb,
    'forge-crm', coalesce(p_metadata,'{}'::jsonb), auth.uid()
  );

  update public.quotes set project_id = p_project_id, status = 'approved' where id = q.id;

  insert into public.events (
    organization_id, location_id, entity_type, entity_id, action, payload, source, actor_user_id
  ) values (
    q.organization_id, q.location_id, 'project', p_project_id, 'created_from_quote',
    jsonb_build_object('quote_id', q.id, 'quote_number', q.quote_number), 'forge-crm', auth.uid()
  );

  return p_project_id;
end;
$$;

grant execute on function public.convert_crm_quote_to_project_v1(uuid,uuid,text,jsonb) to authenticated;
