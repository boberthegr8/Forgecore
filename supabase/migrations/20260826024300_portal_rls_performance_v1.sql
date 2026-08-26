begin;

create index if not exists idx_portal_access_customer_fk on public.portal_access_grants(customer_id);
create index if not exists idx_portal_access_project_fk on public.portal_access_grants(project_id);

-- Consolidate internal-member and external-portal SELECT access so each table
-- has one permissive authenticated SELECT policy.
drop policy if exists "Portal organization read access" on public.organizations;
drop policy if exists organizations_select_member on public.organizations;
create policy organizations_select_member on public.organizations
for select to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = organizations.id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
  or exists (
    select 1 from public.portal_access_grants g
    where g.organization_id = organizations.id
      and g.user_id = (select auth.uid())
      and g.status = 'active'
      and (g.expires_at is null or g.expires_at > now())
  )
);

drop policy if exists "Portal customer read access" on public.customers;
drop policy if exists customers_select_org on public.customers;
create policy customers_select_org on public.customers
for select to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = customers.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
  or exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
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
drop policy if exists projects_select_org on public.projects;
create policy projects_select_org on public.projects
for select to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = projects.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
  or exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
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
drop policy if exists quotes_select_org on public.quotes;
create policy quotes_select_org on public.quotes
for select to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = quotes.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
  or exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
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
drop policy if exists deliveries_select_org on public.deliveries;
create policy deliveries_select_org on public.deliveries
for select to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = deliveries.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
  or exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
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
drop policy if exists documents_select_org on public.documents;
create policy documents_select_org on public.documents
for select to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = documents.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
  or exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
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

-- One SELECT policy for Portal grants; mutation policies are action-specific.
drop policy if exists "Portal users read own grants" on public.portal_access_grants;
drop policy if exists "Portal grants managed by tenant managers" on public.portal_access_grants;
create policy "Portal grants select own or managed"
on public.portal_access_grants for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role::text in ('owner','admin','manager')
  )
);
create policy "Portal grants insert managed"
on public.portal_access_grants for insert to authenticated
with check (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role::text in ('owner','admin','manager')
  )
);
create policy "Portal grants update managed"
on public.portal_access_grants for update to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role::text in ('owner','admin','manager')
  )
);
create policy "Portal grants delete managed"
on public.portal_access_grants for delete to authenticated
using (
  exists (
    select 1 from public.organization_memberships m
    where m.organization_id = portal_access_grants.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role::text in ('owner','admin','manager')
  )
);

commit;
