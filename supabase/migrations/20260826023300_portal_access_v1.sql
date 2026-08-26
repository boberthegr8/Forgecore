begin;

create table if not exists public.portal_access_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'revoked')),
  access_level text not null default 'viewer' check (access_level in ('viewer', 'approver')),
  can_view_quotes boolean not null default true,
  can_view_documents boolean not null default true,
  can_view_deliveries boolean not null default true,
  can_approve boolean not null default false,
  expires_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint portal_access_grants_one_scope check (num_nonnulls(customer_id, project_id) = 1)
);

create unique index if not exists uq_portal_access_project
  on public.portal_access_grants (organization_id, user_id, project_id)
  where project_id is not null;

create unique index if not exists uq_portal_access_customer
  on public.portal_access_grants (organization_id, user_id, customer_id)
  where project_id is null and customer_id is not null;

create index if not exists idx_portal_access_user_status
  on public.portal_access_grants (user_id, status, expires_at);
create index if not exists idx_portal_access_org_customer
  on public.portal_access_grants (organization_id, customer_id)
  where customer_id is not null;
create index if not exists idx_portal_access_org_project
  on public.portal_access_grants (organization_id, project_id)
  where project_id is not null;
create index if not exists idx_portal_access_created_by
  on public.portal_access_grants (created_by)
  where created_by is not null;

alter table public.portal_access_grants enable row level security;

revoke all on table public.portal_access_grants from anon;
grant select, insert, update, delete on table public.portal_access_grants to authenticated;

drop trigger if exists portal_access_grants_set_updated_at on public.portal_access_grants;
create trigger portal_access_grants_set_updated_at
before update on public.portal_access_grants
for each row execute function private.set_updated_at();

drop policy if exists "Portal users read own grants" on public.portal_access_grants;
create policy "Portal users read own grants"
on public.portal_access_grants
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role::text in ('owner', 'admin', 'manager')
  )
);

drop policy if exists "Portal grants managed by tenant managers" on public.portal_access_grants;
create policy "Portal grants managed by tenant managers"
on public.portal_access_grants
for all
to authenticated
using (
  exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role::text in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role::text in ('owner', 'admin', 'manager')
  )
);

create or replace function public.grant_portal_access_by_email_v1(
  p_organization_id uuid,
  p_email text,
  p_customer_id uuid default null,
  p_project_id uuid default null,
  p_access_level text default 'viewer',
  p_can_view_quotes boolean default true,
  p_can_view_documents boolean default true,
  p_can_view_deliveries boolean default true,
  p_can_approve boolean default false,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid;
  v_grant_id uuid;
  v_project_org uuid;
  v_project_customer uuid;
  v_customer_org uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role::text in ('owner', 'admin', 'manager')
  ) then
    raise exception 'Portal grants require owner, admin, or manager access' using errcode = '42501';
  end if;

  if num_nonnulls(p_customer_id, p_project_id) <> 1 then
    raise exception 'Provide exactly one customer_id or project_id' using errcode = '22023';
  end if;

  if p_access_level not in ('viewer', 'approver') then
    raise exception 'Unsupported portal access level' using errcode = '22023';
  end if;

  select u.id
    into v_user_id
  from auth.users u
  where lower(u.email) = lower(trim(p_email))
  order by u.created_at desc
  limit 1;

  if v_user_id is null then
    raise exception 'No Forge Core account exists for that email yet. Ask the portal user to sign in once first.' using errcode = 'P0002';
  end if;

  if p_project_id is not null then
    select p.organization_id, p.customer_id
      into v_project_org, v_project_customer
    from public.projects p
    where p.id = p_project_id;

    if v_project_org is null or v_project_org <> p_organization_id then
      raise exception 'Project does not belong to this organization' using errcode = '23503';
    end if;
  else
    select c.organization_id
      into v_customer_org
    from public.customers c
    where c.id = p_customer_id;

    if v_customer_org is null or v_customer_org <> p_organization_id then
      raise exception 'Customer does not belong to this organization' using errcode = '23503';
    end if;
  end if;

  if p_project_id is not null then
    insert into public.portal_access_grants (
      organization_id, user_id, project_id, status, access_level,
      can_view_quotes, can_view_documents, can_view_deliveries, can_approve,
      expires_at, created_by
    ) values (
      p_organization_id, v_user_id, p_project_id, 'active', p_access_level,
      p_can_view_quotes, p_can_view_documents, p_can_view_deliveries, p_can_approve,
      p_expires_at, auth.uid()
    )
    on conflict (organization_id, user_id, project_id) where project_id is not null
    do update set
      status = 'active',
      access_level = excluded.access_level,
      can_view_quotes = excluded.can_view_quotes,
      can_view_documents = excluded.can_view_documents,
      can_view_deliveries = excluded.can_view_deliveries,
      can_approve = excluded.can_approve,
      expires_at = excluded.expires_at
    returning id into v_grant_id;
  else
    insert into public.portal_access_grants (
      organization_id, user_id, customer_id, status, access_level,
      can_view_quotes, can_view_documents, can_view_deliveries, can_approve,
      expires_at, created_by
    ) values (
      p_organization_id, v_user_id, p_customer_id, 'active', p_access_level,
      p_can_view_quotes, p_can_view_documents, p_can_view_deliveries, p_can_approve,
      p_expires_at, auth.uid()
    )
    on conflict (organization_id, user_id, customer_id) where project_id is null and customer_id is not null
    do update set
      status = 'active',
      access_level = excluded.access_level,
      can_view_quotes = excluded.can_view_quotes,
      can_view_documents = excluded.can_view_documents,
      can_view_deliveries = excluded.can_view_deliveries,
      can_approve = excluded.can_approve,
      expires_at = excluded.expires_at
    returning id into v_grant_id;
  end if;

  insert into public.events (
    organization_id, event_type, entity_type, entity_id, actor_user_id, payload
  ) values (
    p_organization_id,
    'portal_access_granted',
    'portal_access_grant',
    v_grant_id,
    auth.uid(),
    jsonb_build_object('portal_user_id', v_user_id, 'customer_id', p_customer_id, 'project_id', p_project_id, 'access_level', p_access_level)
  );

  return v_grant_id;
end;
$$;

create or replace function public.portal_dashboard_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
with active_grants as (
  select g.*
  from public.portal_access_grants g
  where g.user_id = auth.uid()
    and g.status = 'active'
    and (g.expires_at is null or g.expires_at > now())
), project_access as (
  select
    p.id,
    p.organization_id,
    p.customer_id,
    p.project_number,
    p.name,
    p.status,
    p.description,
    p.address,
    p.updated_at,
    bool_or(g.can_view_quotes) as can_view_quotes,
    bool_or(g.can_view_documents) as can_view_documents,
    bool_or(g.can_view_deliveries) as can_view_deliveries,
    bool_or(g.can_approve) as can_approve
  from active_grants g
  join public.projects p
    on p.organization_id = g.organization_id
   and (
     (g.project_id is not null and p.id = g.project_id)
     or (g.customer_id is not null and p.customer_id = g.customer_id)
   )
  group by p.id
), project_rows as (
  select jsonb_build_object(
    'id', pa.id,
    'organization_id', pa.organization_id,
    'organization_name', o.name,
    'customer_id', pa.customer_id,
    'customer_name', c.display_name,
    'project_number', pa.project_number,
    'name', pa.name,
    'status', pa.status,
    'description', pa.description,
    'address', pa.address,
    'updated_at', pa.updated_at,
    'permissions', jsonb_build_object(
      'quotes', pa.can_view_quotes,
      'documents', pa.can_view_documents,
      'deliveries', pa.can_view_deliveries,
      'approve', pa.can_approve
    ),
    'quotes', case when pa.can_view_quotes then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'quote_number', q.quote_number,
        'status', q.status,
        'title', q.title,
        'current_revision', q.current_revision,
        'currency', q.currency,
        'subtotal', q.subtotal,
        'tax', q.tax,
        'total', q.total,
        'quote_date', q.quote_date,
        'expiry_date', q.expiry_date,
        'updated_at', q.updated_at
      ) order by q.updated_at desc)
      from public.quotes q
      where q.organization_id = pa.organization_id and q.project_id = pa.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'deliveries', case when pa.can_view_deliveries then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'delivery_number', d.delivery_number,
        'status', d.status,
        'scheduled_start', d.scheduled_start,
        'scheduled_end', d.scheduled_end,
        'direction', d.direction,
        'address', d.address,
        'truck', d.truck,
        'driver', d.driver,
        'load_type', d.load_type,
        'notes', d.notes
      ) order by d.scheduled_start nulls last)
      from public.deliveries d
      where d.organization_id = pa.organization_id and d.project_id = pa.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'documents', case when pa.can_view_documents then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id,
        'title', doc.title,
        'original_filename', doc.original_filename,
        'document_type', doc.document_type,
        'status', doc.status,
        'mime_type', doc.mime_type,
        'file_size_bytes', doc.file_size_bytes,
        'storage_bucket', doc.storage_bucket,
        'storage_path', doc.storage_path,
        'created_at', doc.created_at
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.organization_id = pa.organization_id and doc.project_id = pa.id
    ), '[]'::jsonb) else '[]'::jsonb end
  ) as row_json,
  pa.updated_at
  from project_access pa
  join public.organizations o on o.id = pa.organization_id
  left join public.customers c on c.id = pa.customer_id
)
select jsonb_build_object(
  'user_id', auth.uid(),
  'grants', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.id,
      'organization_id', g.organization_id,
      'customer_id', g.customer_id,
      'project_id', g.project_id,
      'access_level', g.access_level,
      'can_view_quotes', g.can_view_quotes,
      'can_view_documents', g.can_view_documents,
      'can_view_deliveries', g.can_view_deliveries,
      'can_approve', g.can_approve,
      'expires_at', g.expires_at
    ) order by g.created_at)
    from active_grants g
  ), '[]'::jsonb),
  'projects', coalesce((select jsonb_agg(row_json order by updated_at desc) from project_rows), '[]'::jsonb)
);
$$;

create or replace function public.portal_project_detail_v1(p_project_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
select project_item
from jsonb_array_elements(coalesce(public.portal_dashboard_v1()->'projects', '[]'::jsonb)) as project_item
where project_item->>'id' = p_project_id::text
limit 1;
$$;

create or replace function public.portal_can_access_document_v1(p_bucket text, p_name text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
select exists (
  select 1
  from public.documents d
  join public.portal_access_grants g
    on g.organization_id = d.organization_id
   and g.user_id = auth.uid()
   and g.status = 'active'
   and g.can_view_documents
   and (g.expires_at is null or g.expires_at > now())
  where d.storage_bucket = p_bucket
    and d.storage_path = p_name
    and (
      (g.project_id is not null and d.project_id = g.project_id)
      or (
        g.customer_id is not null
        and (
          d.customer_id = g.customer_id
          or exists (
            select 1 from public.projects p
            where p.id = d.project_id
              and p.organization_id = g.organization_id
              and p.customer_id = g.customer_id
          )
        )
      )
    )
);
$$;

revoke all on function public.grant_portal_access_by_email_v1(uuid,text,uuid,uuid,text,boolean,boolean,boolean,boolean,timestamptz) from public, anon;
revoke all on function public.portal_dashboard_v1() from public, anon;
revoke all on function public.portal_project_detail_v1(uuid) from public, anon;
revoke all on function public.portal_can_access_document_v1(text,text) from public, anon;

grant execute on function public.grant_portal_access_by_email_v1(uuid,text,uuid,uuid,text,boolean,boolean,boolean,boolean,timestamptz) to authenticated;
grant execute on function public.portal_dashboard_v1() to authenticated;
grant execute on function public.portal_project_detail_v1(uuid) to authenticated;
grant execute on function public.portal_can_access_document_v1(text,text) to authenticated;

drop policy if exists "Portal document read access" on storage.objects;
create policy "Portal document read access"
on storage.objects
for select
to authenticated
using (public.portal_can_access_document_v1(bucket_id, name));

commit;
