begin;

create table if not exists public.portal_quote_responses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  quote_id uuid not null references public.quotes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  response text not null check (response in ('approved','changes_requested','declined')),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_portal_quote_responses_org on public.portal_quote_responses(organization_id);
create index if not exists idx_portal_quote_responses_project on public.portal_quote_responses(project_id);
create index if not exists idx_portal_quote_responses_quote on public.portal_quote_responses(quote_id, created_at desc);
create index if not exists idx_portal_quote_responses_user on public.portal_quote_responses(user_id, created_at desc);

alter table public.portal_quote_responses enable row level security;
revoke all on table public.portal_quote_responses from anon;
grant select, insert on table public.portal_quote_responses to authenticated;

drop policy if exists "Portal quote responses select" on public.portal_quote_responses;
create policy "Portal quote responses select"
on public.portal_quote_responses for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.organization_memberships m
    where m.organization_id = portal_quote_responses.organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
);

drop policy if exists "Portal quote responses insert" on public.portal_quote_responses;
create policy "Portal quote responses insert"
on public.portal_quote_responses for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.quotes q
    where q.id = portal_quote_responses.quote_id
      and q.organization_id = portal_quote_responses.organization_id
      and q.project_id is not distinct from portal_quote_responses.project_id
  )
  and exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
      and g.organization_id = portal_quote_responses.organization_id
      and g.status = 'active'
      and g.can_approve
      and (g.expires_at is null or g.expires_at > now())
      and (
        g.project_id = portal_quote_responses.project_id
        or exists (
          select 1
          from public.quotes q2
          where q2.id = portal_quote_responses.quote_id
            and q2.customer_id = g.customer_id
        )
      )
  )
);

create or replace function public.submit_portal_quote_response_v1(
  p_quote_id uuid,
  p_response text,
  p_note text default null
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
  v_org uuid;
  v_project uuid;
  v_customer uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_response not in ('approved','changes_requested','declined') then
    raise exception 'Unsupported quote response' using errcode = '22023';
  end if;

  select q.organization_id, q.project_id, q.customer_id
    into v_org, v_project, v_customer
  from public.quotes q
  where q.id = p_quote_id;

  if v_org is null then
    raise exception 'Quote is not available in your Portal' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.portal_access_grants g
    where g.user_id = (select auth.uid())
      and g.organization_id = v_org
      and g.status = 'active'
      and g.can_approve
      and (g.expires_at is null or g.expires_at > now())
      and (g.project_id = v_project or g.customer_id = v_customer)
  ) then
    raise exception 'Approval access is not enabled for this quote' using errcode = '42501';
  end if;

  insert into public.portal_quote_responses (
    organization_id, project_id, quote_id, user_id, response, note
  ) values (
    v_org, v_project, p_quote_id, auth.uid(), p_response, nullif(trim(p_note), '')
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_portal_quote_response_v1(uuid,text,text) from public, anon;
grant execute on function public.submit_portal_quote_response_v1(uuid,text,text) to authenticated;

commit;
