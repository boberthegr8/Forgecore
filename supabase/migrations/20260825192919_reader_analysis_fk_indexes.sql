create index if not exists idx_document_analysis_runs_location
  on public.document_analysis_runs(location_id)
  where location_id is not null;

create index if not exists idx_document_analysis_runs_created_by
  on public.document_analysis_runs(created_by)
  where created_by is not null;
