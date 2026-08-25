create or replace function public.commit_scope_v1(
  p_scope_id uuid,
  p_organization_id uuid,
  p_location_id uuid,
  p_project_id uuid,
  p_customer_id uuid,
  p_source_document_id uuid,
  p_scope_type text,
  p_title text,
  p_structured_data jsonb
)
returns table(scope_id uuid, version_number integer, created boolean, changed boolean)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  existing_scope public.scopes%rowtype;
  source_document public.documents%rowtype;
  next_version integer;
  did_create boolean := false;
  did_change boolean := false;
  resolved_project_id uuid := p_project_id;
  resolved_customer_id uuid := p_customer_id;
  resolved_source text := 'forge-scope';
begin
  if p_scope_id is null then raise exception 'Scope id is required'; end if;
  if p_organization_id is null then raise exception 'Organization id is required'; end if;
  if nullif(trim(coalesce(p_scope_type,'')),'') is null then raise exception 'Scope type is required'; end if;

  if p_source_document_id is not null then
    select d.* into source_document from public.documents d where d.id = p_source_document_id;
    if not found then raise exception 'Source document not found'; end if;
    if source_document.organization_id <> p_organization_id then raise exception 'Source document belongs to another organization'; end if;
    if p_project_id is not null and source_document.project_id is not null and source_document.project_id <> p_project_id then raise exception 'Project does not match source document'; end if;
    if p_customer_id is not null and source_document.customer_id is not null and source_document.customer_id <> p_customer_id then raise exception 'Customer does not match source document'; end if;
    resolved_project_id := coalesce(p_project_id, source_document.project_id);
    resolved_customer_id := coalesce(p_customer_id, source_document.customer_id);
    resolved_source := 'forge-scope-reader';
  end if;

  if resolved_project_id is not null then
    if not exists (select 1 from public.projects p where p.id=resolved_project_id and p.organization_id=p_organization_id) then
      raise exception 'Project belongs to another organization or does not exist';
    end if;
  end if;
  if resolved_customer_id is not null then
    if not exists (select 1 from public.customers c where c.id=resolved_customer_id and c.organization_id=p_organization_id) then
      raise exception 'Customer belongs to another organization or does not exist';
    end if;
  end if;

  select s.* into existing_scope from public.scopes s where s.id = p_scope_id;

  if not found then
    insert into public.scopes (
      id, organization_id, location_id, project_id, customer_id, source_document_id,
      scope_type, status, title, structured_data, current_version, source, created_by
    ) values (
      p_scope_id, p_organization_id, p_location_id, resolved_project_id, resolved_customer_id,
      p_source_document_id, trim(p_scope_type), 'draft', nullif(trim(coalesce(p_title,'')),''),
      coalesce(p_structured_data,'{}'::jsonb), 1, resolved_source, auth.uid()
    );

    insert into public.scope_versions (
      organization_id, scope_id, version_number, structured_data, notes, created_by
    ) values (
      p_organization_id, p_scope_id, 1, coalesce(p_structured_data,'{}'::jsonb),
      case when p_source_document_id is not null
        then 'Created from Forge Reader document ' || p_source_document_id::text
        else 'Created in Forge Scope'
      end,
      auth.uid()
    );
    next_version := 1;
    did_create := true;
    did_change := true;
  else
    if existing_scope.organization_id <> p_organization_id then raise exception 'Scope belongs to another organization'; end if;

    if existing_scope.structured_data = coalesce(p_structured_data,'{}'::jsonb)
       and existing_scope.source_document_id is not distinct from p_source_document_id
       and existing_scope.project_id is not distinct from resolved_project_id
       and existing_scope.customer_id is not distinct from resolved_customer_id
       and existing_scope.scope_type = trim(p_scope_type)
       and coalesce(existing_scope.title,'') = coalesce(nullif(trim(coalesce(p_title,'')),''),'') then
      next_version := existing_scope.current_version;
    else
      next_version := existing_scope.current_version + 1;
      did_change := true;
      update public.scopes s
      set location_id = p_location_id,
          project_id = resolved_project_id,
          customer_id = resolved_customer_id,
          source_document_id = p_source_document_id,
          scope_type = trim(p_scope_type),
          title = nullif(trim(coalesce(p_title,'')),''),
          structured_data = coalesce(p_structured_data,'{}'::jsonb),
          current_version = next_version,
          source = resolved_source
      where s.id = p_scope_id;

      insert into public.scope_versions (
        organization_id, scope_id, version_number, structured_data, notes, created_by
      ) values (
        p_organization_id, p_scope_id, next_version, coalesce(p_structured_data,'{}'::jsonb),
        'Saved from Forge Scope', auth.uid()
      );
    end if;
  end if;

  if did_change then
    insert into public.events (organization_id, location_id, entity_type, entity_id, action, payload, source, actor_user_id)
    values (
      p_organization_id, p_location_id, 'scope', p_scope_id,
      case when did_create then 'scope_created' else 'scope_version_saved' end,
      jsonb_build_object('version_number',next_version,'source_document_id',p_source_document_id,'scope_type',p_scope_type,'source',resolved_source),
      'forge-scope', auth.uid()
    );
  end if;

  return query select p_scope_id, next_version, did_create, did_change;
end;
$$;

revoke all on function public.commit_scope_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text,jsonb) from public, anon;
grant execute on function public.commit_scope_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text,jsonb) to authenticated;
