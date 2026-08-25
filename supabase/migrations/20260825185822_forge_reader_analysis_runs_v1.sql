create table public.document_analysis_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  document_id uuid not null references public.documents(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  analysis_type text not null default 'reader_intake',
  status text not null default 'queued' check (status in ('queued','processing','review','completed','failed','cancelled')),
  parser text,
  model text,
  page_count integer,
  extracted_data jsonb not null default '{}'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  error_message text,
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_document_analysis_runs_org_status on public.document_analysis_runs(organization_id, status, created_at desc);
create index idx_document_analysis_runs_document on public.document_analysis_runs(document_id, created_at desc);
create index idx_document_analysis_runs_project on public.document_analysis_runs(project_id) where project_id is not null;

create trigger trg_document_analysis_runs_updated before update on public.document_analysis_runs for each row execute function private.set_updated_at();

alter table public.document_analysis_runs enable row level security;
grant select, insert, update, delete on public.document_analysis_runs to authenticated;

create policy document_analysis_runs_select_org on public.document_analysis_runs
for select to authenticated using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = document_analysis_runs.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
);

create policy document_analysis_runs_insert_org on public.document_analysis_runs
for insert to authenticated with check (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = document_analysis_runs.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role <> 'viewer'
  )
);

create policy document_analysis_runs_update_org on public.document_analysis_runs
for update to authenticated using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = document_analysis_runs.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role <> 'viewer'
  )
) with check (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = document_analysis_runs.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role <> 'viewer'
  )
);

create policy document_analysis_runs_delete_admin on public.document_analysis_runs
for delete to authenticated using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = document_analysis_runs.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role in ('owner','admin')
  )
);
