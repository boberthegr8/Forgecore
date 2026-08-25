create or replace function public.commit_reader_document_v1(
  p_document_id uuid,
  p_organization_id uuid,
  p_location_id uuid,
  p_project_id uuid,
  p_customer_id uuid,
  p_document_type text,
  p_title text,
  p_original_filename text,
  p_storage_bucket text,
  p_storage_path text,
  p_mime_type text,
  p_file_size_bytes bigint,
  p_sha256 text
)
returns table (
  document_id uuid,
  analysis_run_id uuid,
  duplicate boolean
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  existing_document public.documents%rowtype;
  new_analysis_id uuid;
begin
  select d.*
    into existing_document
  from public.documents d
  where d.organization_id = p_organization_id
    and d.sha256 = p_sha256
  order by d.created_at asc
  limit 1;

  if found then
    select r.id
      into new_analysis_id
    from public.document_analysis_runs r
    where r.document_id = existing_document.id
    order by r.created_at desc
    limit 1;

    return query
      select existing_document.id, new_analysis_id, true;
    return;
  end if;

  insert into public.documents (
    id,
    organization_id,
    location_id,
    project_id,
    customer_id,
    document_type,
    title,
    original_filename,
    storage_bucket,
    storage_path,
    mime_type,
    file_size_bytes,
    sha256,
    status,
    source,
    metadata,
    created_by
  ) values (
    p_document_id,
    p_organization_id,
    p_location_id,
    p_project_id,
    p_customer_id,
    coalesce(nullif(trim(p_document_type), ''), 'drawing_set'),
    coalesce(nullif(trim(p_title), ''), p_original_filename),
    p_original_filename,
    p_storage_bucket,
    p_storage_path,
    p_mime_type,
    p_file_size_bytes,
    p_sha256,
    'uploaded',
    'forge-reader',
    jsonb_build_object('reader_version', 1),
    auth.uid()
  );

  insert into public.document_analysis_runs (
    organization_id,
    location_id,
    document_id,
    project_id,
    analysis_type,
    status,
    parser,
    extracted_data,
    warnings,
    created_by
  ) values (
    p_organization_id,
    p_location_id,
    p_document_id,
    p_project_id,
    'reader_intake',
    'queued',
    'forge-reader-v1',
    '{}'::jsonb,
    '[]'::jsonb,
    auth.uid()
  )
  returning id into new_analysis_id;

  insert into public.events (
    organization_id,
    location_id,
    entity_type,
    entity_id,
    action,
    payload,
    source,
    actor_user_id
  ) values (
    p_organization_id,
    p_location_id,
    'document',
    p_document_id,
    'reader_uploaded',
    jsonb_build_object(
      'analysis_run_id', new_analysis_id,
      'filename', p_original_filename,
      'sha256', p_sha256
    ),
    'forge-reader',
    auth.uid()
  );

  return query
    select p_document_id, new_analysis_id, false;
end;
$$;

grant execute on function public.commit_reader_document_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,text,text,bigint,text) to authenticated;
