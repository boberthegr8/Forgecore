create or replace function public.commit_scope_from_reader_v1(
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
returns table(scope_id uuid, version_number integer, created boolean)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  existing_scope public.scopes%rowtype;
  source_document public.documents%rowtype;
  next_version integer;
  did_create boolean := false;
begin
  if p_scope_id is null then raise exception 'Scope id is required'; end if;
  if p_organization_id is null then raise exception 'Organization id is required'; end if;
  if p_source_document_id is null then raise exception 'Reader source document is required'; end if;
  if nullif(trim(coalesce(p_scope_type,'')),'') is null then raise exception 'Scope type is required'; end if;

  select d.* into source_document from public.documents d where d.id = p_source_document_id;
  if not found then raise exception 'Reader document not found'; end if;
  if source_document.organization_id <> p_organization_id then raise exception 'Reader document belongs to another organization'; end if;
  if p_project_id is not null and source_document.project_id is not null and source_document.project_id <> p_project_id then raise exception 'Project does not match Reader document'; end if;
  if p_customer_id is not null and source_document.customer_id is not null and source_document.customer_id <> p_customer_id then raise exception 'Customer does not match Reader document'; end if;

  select s.* into existing_scope from public.scopes s where s.id = p_scope_id;

  if not found then
    insert into public.scopes (
      id, organization_id, location_id, project_id, customer_id, source_document_id,
      scope_type, status, title, structured_data, current_version, source, created_by
    ) values (
      p_scope_id, p_organization_id, p_location_id,
      coalesce(p_project_id, source_document.project_id),
      coalesce(p_customer_id, source_document.customer_id),
      p_source_document_id,
      trim(p_scope_type), 'draft', nullif(trim(coalesce(p_title,'')),''),
      coalesce(p_structured_data,'{}'::jsonb), 1, 'forge-scope-reader', auth.uid()
    );

    insert into public.scope_versions (
      organization_id, scope_id, version_number, structured_data, notes, created_by
    ) values (
      p_organization_id, p_scope_id, 1, coalesce(p_structured_data,'{}'::jsonb),
      'Created from Forge Reader document ' || p_source_document_id::text, auth.uid()
    );

    next_version := 1;
    did_create := true;
  else
    if existing_scope.organization_id <> p_organization_id then raise exception 'Scope belongs to another organization'; end if;

    if existing_scope.structured_data = coalesce(p_structured_data,'{}'::jsonb)
       and existing_scope.source_document_id = p_source_document_id
       and existing_scope.scope_type = trim(p_scope_type)
       and coalesce(existing_scope.title,'') = coalesce(nullif(trim(coalesce(p_title,'')),''),'') then
      next_version := existing_scope.current_version;
    else
      next_version := existing_scope.current_version + 1;
      update public.scopes s
      set location_id = p_location_id,
          project_id = coalesce(p_project_id, source_document.project_id),
          customer_id = coalesce(p_customer_id, source_document.customer_id),
          source_document_id = p_source_document_id,
          scope_type = trim(p_scope_type),
          title = nullif(trim(coalesce(p_title,'')),''),
          structured_data = coalesce(p_structured_data,'{}'::jsonb),
          current_version = next_version,
          source = 'forge-scope-reader'
      where s.id = p_scope_id;

      insert into public.scope_versions (
        organization_id, scope_id, version_number, structured_data, notes, created_by
      ) values (
        p_organization_id, p_scope_id, next_version, coalesce(p_structured_data,'{}'::jsonb),
        'Saved from Forge Scope', auth.uid()
      );
    end if;
  end if;

  insert into public.events (organization_id, location_id, entity_type, entity_id, action, payload, source, actor_user_id)
  values (
    p_organization_id, p_location_id, 'scope', p_scope_id,
    case when did_create then 'scope_created_from_reader' else 'scope_saved' end,
    jsonb_build_object('version_number',next_version,'source_document_id',p_source_document_id,'scope_type',p_scope_type),
    'forge-scope', auth.uid()
  );

  return query select p_scope_id, next_version, did_create;
end;
$$;

revoke all on function public.commit_scope_from_reader_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text,jsonb) from public, anon;
grant execute on function public.commit_scope_from_reader_v1(uuid,uuid,uuid,uuid,uuid,uuid,text,text,jsonb) to authenticated;
