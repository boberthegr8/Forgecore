begin;

-- Portal users remain external to organization_memberships. These policies add
-- read-only access only when an explicit active Portal grant matches the row.

drop policy if exists "Portal organization read access" on public.organizations;
create policy "Portal organization read access"
on public.organizations
for select to authenticated
using (
  exists (
    select 1 from public.portal_access_grants g
    where g.user_id = auth.uid()
      and g.organization_id = organizations.id
      and g.status = 'active'
      and (g.expires_at is null or g.expires_at > now())
  )
);

drop policy if exists "Portal customer read access" on public.customers;
create policy "Portal customer read access"
on public.customers
for select to authenticated
using (
  exists (
    select 1
    from public.portal_access_grants g
    where g.user_id = auth.uid()
      and g.organization_id = customers.organization_id
      and g.status = 'active'
      and (g.expires_at is null or g.expires_at > now())
      and (
        g.customer_id = customers.id
        or exists (
          select 1 from public.projects p
          where p.id = g.project_id
            and p.organization_id = customers.organization_id
            and p.customer_id = customers.id
        )
      )
  )
);

drop policy if exists "Portal project read access" on public.projects;
create policy "Portal project read access"
on public.projects
for select to authenticated
using (
  exists (
    select 1 from public.portal_access_grants g
    where g.user_id = auth.uid()
      and g.organization_id = projects.organization_id
      and g.status = 'active'
      and (g.expires_at is null or g.expires_at > now())
      and (
        g.project_id = projects.id
        or (g.customer_id is not null and g.customer_id = projects.customer_id)
      )
  )
);

drop policy if exists "Portal quote read access" on public.quotes;
create policy "Portal quote read access"
on public.quotes
for select to authenticated
using (
  exists (
    select 1 from public.portal_access_grants g
    where g.user_id = auth.uid()
      and g.organization_id = quotes.organization_id
      and g.status = 'active'
      and g.can_view_quotes
      and (g.expires_at is null or g.expires_at > now())
      and (
        g.project_id = quotes.project_id
        or g.customer_id = quotes.customer_id
        or (
          g.customer_id is not null
          and exists (
            select 1 from public.projects p
            where p.id = quotes.project_id
              and p.organization_id = g.organization_id
              and p.customer_id = g.customer_id
          )
        )
      )
  )
);

drop policy if exists "Portal delivery read access" on public.deliveries;
create policy "Portal delivery read access"
on public.deliveries
for select to authenticated
using (
  exists (
    select 1 from public.portal_access_grants g
    where g.user_id = auth.uid()
      and g.organization_id = deliveries.organization_id
      and g.status = 'active'
      and g.can_view_deliveries
      and (g.expires_at is null or g.expires_at > now())
      and (
        g.project_id = deliveries.project_id
        or g.customer_id = deliveries.customer_id
        or (
          g.customer_id is not null
          and exists (
            select 1 from public.projects p
            where p.id = deliveries.project_id
              and p.organization_id = g.organization_id
              and p.customer_id = g.customer_id
          )
        )
      )
  )
);

drop policy if exists "Portal document metadata read access" on public.documents;
create policy "Portal document metadata read access"
on public.documents
for select to authenticated
using (
  exists (
    select 1 from public.portal_access_grants g
    where g.user_id = auth.uid()
      and g.organization_id = documents.organization_id
      and g.status = 'active'
      and g.can_view_documents
      and (g.expires_at is null or g.expires_at > now())
      and (
        g.project_id = documents.project_id
        or g.customer_id = documents.customer_id
        or (
          g.customer_id is not null
          and exists (
            select 1 from public.projects p
            where p.id = documents.project_id
              and p.organization_id = g.organization_id
              and p.customer_id = g.customer_id
          )
        )
      )
  )
);

-- Email lookup belongs in a server-side admin workflow, not an exposed RPC.
revoke all on function public.grant_portal_access_by_email_v1(uuid,text,uuid,uuid,text,boolean,boolean,boolean,boolean,timestamptz) from authenticated;
drop function public.grant_portal_access_by_email_v1(uuid,text,uuid,uuid,text,boolean,boolean,boolean,boolean,timestamptz);

alter function public.portal_dashboard_v1() security invoker;
alter function public.portal_project_detail_v1(uuid) security invoker;
alter function public.portal_can_access_document_v1(text,text) security invoker;

-- Re-assert the narrow authenticated API surface after the security-mode change.
revoke all on function public.portal_dashboard_v1() from public, anon;
revoke all on function public.portal_project_detail_v1(uuid) from public, anon;
revoke all on function public.portal_can_access_document_v1(text,text) from public, anon;
grant execute on function public.portal_dashboard_v1() to authenticated;
grant execute on function public.portal_project_detail_v1(uuid) to authenticated;
grant execute on function public.portal_can_access_document_v1(text,text) to authenticated;

commit;
