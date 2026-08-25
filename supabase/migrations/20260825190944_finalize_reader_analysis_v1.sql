create or replace function public.finalize_reader_analysis_v1(
  p_analysis_run_id uuid,
  p_status text,
  p_parser text,
  p_page_count integer,
  p_extracted_data jsonb,
  p_warnings jsonb,
  p_error_message text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  run_record public.document_analysis_runs%rowtype;
  document_status text;
begin
  if p_status not in ('review','completed','failed') then
    raise exception 'Invalid Reader analysis status: %', p_status;
  end if;

  select r.* into run_record
  from public.document_analysis_runs r
  where r.id = p_analysis_run_id;

  if not found then
    raise exception 'Reader analysis run not found';
  end if;

  update public.document_analysis_runs r
  set status = p_status,
      parser = coalesce(nullif(trim(p_parser), ''), r.parser),
      page_count = p_page_count,
      extracted_data = coalesce(p_extracted_data, '{}'::jsonb),
      warnings = coalesce(p_warnings, '[]'::jsonb),
      error_message = p_error_message,
      started_at = coalesce(r.started_at, now()),
      completed_at = now()
  where r.id = p_analysis_run_id;

  document_status := case
    when p_status = 'completed' then 'analyzed'
    when p_status = 'review' then 'needs_review'
    else 'analysis_failed'
  end;

  update public.documents d
  set status = document_status,
      metadata = coalesce(d.metadata, '{}'::jsonb) || jsonb_build_object(
        'reader_analysis_run_id', p_analysis_run_id,
        'reader_analysis_status', p_status,
        'reader_parser', p_parser,
        'reader_page_count', p_page_count
      )
  where d.id = run_record.document_id;

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
    run_record.organization_id,
    run_record.location_id,
    'document',
    run_record.document_id,
    'reader_analysis_' || p_status,
    jsonb_build_object(
      'analysis_run_id', p_analysis_run_id,
      'parser', p_parser,
      'page_count', p_page_count,
      'warning_count', jsonb_array_length(coalesce(p_warnings, '[]'::jsonb))
    ),
    'forge-reader',
    auth.uid()
  );

  return run_record.document_id;
end;
$$;

grant execute on function public.finalize_reader_analysis_v1(uuid,text,text,integer,jsonb,jsonb,text) to authenticated;
