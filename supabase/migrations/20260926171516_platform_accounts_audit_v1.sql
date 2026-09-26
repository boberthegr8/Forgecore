-- Additive platform administration. Existing tenant policies remain authoritative
-- for writes; platform-wide reads and user administration require MFA.
create schema if not exists forge_private;
revoke all on schema forge_private from public, anon;
grant usage on schema forge_private to authenticated;

create table forge_private.platform_owners (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table forge_private.platform_owners enable row level security;
revoke all on forge_private.platform_owners from public, anon, authenticated;

-- Bind the verified existing owner by immutable identity, never email metadata.
insert into forge_private.platform_owners(user_id)
select id from auth.users
where id = '05cef0c7-b5e4-45c8-967e-20e0c14c84f5'
  and email_confirmed_at is not null;

create function forge_private.is_platform_owner(require_mfa boolean default true)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and (not require_mfa or coalesce(auth.jwt()->>'aal', '') = 'aal2')
    and exists (select 1 from forge_private.platform_owners o
      join auth.users u on u.id=o.user_id
      where o.user_id=auth.uid() and o.active and u.email_confirmed_at is not null
        and (u.banned_until is null or u.banned_until < now()));
$$;
revoke all on function forge_private.is_platform_owner(boolean) from public, anon;
grant execute on function forge_private.is_platform_owner(boolean) to authenticated;

create table public.forge_access_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 120),
  company_name text not null check (length(company_name) between 1 and 160),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);
alter table public.forge_access_requests enable row level security;
revoke all on public.forge_access_requests from public, anon, authenticated;
grant select on public.forge_access_requests to authenticated;
create policy access_request_read on public.forge_access_requests for select to authenticated
using (user_id=(select auth.uid()) or (select forge_private.is_platform_owner()));
create index forge_access_requests_status_time on public.forge_access_requests(status,created_at);
create index forge_access_requests_reviewer on public.forge_access_requests(reviewed_by);

create table public.forge_audit_log (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default clock_timestamp(),
  actor_user_id uuid,
  organization_id uuid,
  entity_type text not null,
  entity_id text,
  action text not null,
  changed_fields text[] not null default '{}'
);
alter table public.forge_audit_log enable row level security;
revoke all on public.forge_audit_log from public, anon, authenticated;
revoke all on sequence public.forge_audit_log_id_seq from public, anon, authenticated;
grant select on public.forge_audit_log to authenticated;
create policy audit_owner_read on public.forge_audit_log for select to authenticated
using ((select forge_private.is_platform_owner()));
create index forge_audit_time on public.forge_audit_log(occurred_at desc,id desc);
create index forge_audit_org_time on public.forge_audit_log(organization_id,occurred_at desc,id desc);

-- Trigger-only definer: writes trusted actor + identifiers, never record contents,
-- credentials, tokens, or arbitrary user-supplied event payloads.
create function forge_private.audit_business_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare row_data jsonb; old_data jsonb; changed text[];
begin
  if TG_OP='DELETE' then row_data:=to_jsonb(old); else row_data:=to_jsonb(new); end if;
  if TG_OP='UPDATE' then
    old_data:=to_jsonb(old);
    select coalesce(array_agg(k order by k),'{}') into changed
    from jsonb_object_keys(row_data) k where row_data->k is distinct from old_data->k;
    if cardinality(changed)=0 then return null; end if;
  else changed:='{}'; end if;
  insert into public.forge_audit_log(actor_user_id,organization_id,entity_type,entity_id,action,changed_fields)
  values(auth.uid(),nullif(row_data->>'organization_id','')::uuid,TG_TABLE_NAME,
    coalesce(row_data->>'id',row_data->>'user_id'),lower(TG_OP),changed);
  return null;
end;
$$;
revoke all on function forge_private.audit_business_change() from public,anon,authenticated;

do $$
declare t text;
begin
  foreach t in array array['organizations','locations','profiles','organization_memberships',
    'customers','contacts','projects','documents','document_analysis_runs','scopes','scope_versions',
    'takeoffs','takeoff_items','quotes','quote_revisions','quote_items','activities','tasks','deliveries',
    'events','vendors','purchase_orders','purchase_order_items','purchase_receipts','purchase_receipt_items',
    'work_orders','work_order_items','production_operations','portal_access_grants','portal_quote_responses',
    'forge_access_requests']
  loop
    execute format('create trigger forge_audit_change after insert or update or delete on public.%I for each row execute function forge_private.audit_business_change()',t);
    if t <> 'forge_access_requests' then
      execute format('create policy platform_owner_read on public.%I for select to authenticated using ((select forge_private.is_platform_owner()))',t);
    end if;
  end loop;
end $$;

create function forge_private.request_access(p_display_name text,p_company_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then
    raise exception 'Verify your email before requesting access.' using errcode='42501';
  end if;
  if exists(select 1 from public.organization_memberships where user_id=auth.uid() and status='active') then
    raise exception 'Your account already has workspace access.';
  end if;
  insert into public.forge_access_requests(user_id,display_name,company_name)
  values(auth.uid(),trim(p_display_name),trim(p_company_name))
  on conflict(user_id) do nothing;
end;
$$;

create function forge_private.account_context()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode='42501'; end if;
  return jsonb_build_object('is_owner',forge_private.is_platform_owner(false),
    'admin_unlocked',forge_private.is_platform_owner(true),
    'has_portal_access',exists(select 1 from public.portal_access_grants where user_id=auth.uid() and status='active' and (expires_at is null or expires_at>now())),
    'request',(select to_jsonb(r) from public.forge_access_requests r where r.user_id=auth.uid()),
    'memberships',coalesce((select jsonb_agg(jsonb_build_object('organization_id',m.organization_id,'organization_name',o.name,'role',m.role))
      from public.organization_memberships m join public.organizations o on o.id=m.organization_id
      where m.user_id=auth.uid() and m.status='active' and o.status='active'),'[]'));
end;
$$;

create function forge_private.admin_directory()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not forge_private.is_platform_owner() then raise exception 'Owner access with MFA required.' using errcode='42501'; end if;
  insert into public.forge_audit_log(actor_user_id,entity_type,action) values(auth.uid(),'admin_console','directory.read');
  return jsonb_build_object(
    'users',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,'confirmed',u.email_confirmed_at is not null,'created_at',u.created_at))
      from (select id,email,email_confirmed_at,created_at from auth.users order by created_at desc limit 500) u),'[]'),
    'organizations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.organizations where status='active'),'[]'),
    'memberships',coalesce((select jsonb_agg(to_jsonb(m)) from public.organization_memberships m),'[]'),
    'requests',coalesce((select jsonb_agg(to_jsonb(r)) from public.forge_access_requests r where status='pending'),'[]'));
end;
$$;

create function forge_private.set_membership(p_user_id uuid,p_organization_id uuid,p_role public.forge_member_role,p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not forge_private.is_platform_owner() then raise exception 'Owner access with MFA required.' using errcode='42501'; end if;
  if p_status is null or p_status not in ('active','suspended') or p_role is null then raise exception 'Invalid role or status.'; end if;
  if exists(select 1 from forge_private.platform_owners where user_id=p_user_id and active) then
    raise exception 'Platform owner memberships are managed separately.';
  end if;
  if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then
    raise exception 'The user must verify their email first.';
  end if;
  if not exists(select 1 from public.organizations where id=p_organization_id and status='active') then raise exception 'Choose an active organization.'; end if;
  insert into public.organization_memberships(user_id,organization_id,role,status)
  values(p_user_id,p_organization_id,p_role,p_status)
  on conflict(organization_id,user_id) do update set role=excluded.role,status=excluded.status,updated_at=now();
  if p_status='active' then
    update public.forge_access_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where user_id=p_user_id;
  end if;
end;
$$;

-- Thin invoker wrappers are the only exposed RPC surface. Every privileged
-- implementation above checks the caller inside the private schema.
create function public.forge_request_access(p_display_name text,p_company_name text)
returns void language sql security invoker set search_path='' as $$ select forge_private.request_access(p_display_name,p_company_name); $$;
create function public.forge_account_context()
returns jsonb language sql security invoker set search_path='' as $$ select forge_private.account_context(); $$;
create function public.forge_admin_directory()
returns jsonb language sql security invoker set search_path='' as $$ select forge_private.admin_directory(); $$;
create function public.forge_set_membership(p_user_id uuid,p_organization_id uuid,p_role public.forge_member_role,p_status text)
returns void language sql security invoker set search_path='' as $$ select forge_private.set_membership(p_user_id,p_organization_id,p_role,p_status); $$;

revoke all on function forge_private.request_access(text,text),forge_private.account_context(),forge_private.admin_directory(),forge_private.set_membership(uuid,uuid,public.forge_member_role,text) from public,anon;
grant execute on function forge_private.request_access(text,text),forge_private.account_context(),forge_private.admin_directory(),forge_private.set_membership(uuid,uuid,public.forge_member_role,text) to authenticated;
revoke all on function public.forge_request_access(text,text),public.forge_account_context(),public.forge_admin_directory(),public.forge_set_membership(uuid,uuid,public.forge_member_role,text) from public,anon;
grant execute on function public.forge_request_access(text,text),public.forge_account_context(),public.forge_admin_directory(),public.forge_set_membership(uuid,uuid,public.forge_member_role,text) to authenticated;

-- Persist Scope -> CRM handoff atomically under the caller's existing RLS.
create function public.forge_link_scope_to_crm(p_scope_id uuid)
returns uuid language plpgsql security invoker set search_path='' as $$
declare s public.scopes; customer uuid; project uuid; customer_name text; project_name text;
begin
  select * into s from public.scopes where id=p_scope_id for update;
  if s.id is null or not exists(select 1 from public.organization_memberships
    where organization_id=s.organization_id and user_id=auth.uid() and status='active' and role<>'viewer') then
    raise exception 'Workspace write access required.' using errcode='42501';
  end if;
  if s.project_id is not null then return s.project_id; end if;
  customer:=s.customer_id;
  customer_name:=nullif(trim(s.structured_data#>>'{fields,customer,value}'),'');
  project_name:=coalesce(nullif(trim(s.structured_data#>>'{fields,projectName,value}'),''),s.title,'Scope project');
  if customer is null and customer_name is not null then
    select id into customer from public.customers where organization_id=s.organization_id
      and lower(display_name)=lower(customer_name) order by created_at,id limit 1;
    if customer is null then
      insert into public.customers(organization_id,location_id,display_name,source,created_by)
      values(s.organization_id,s.location_id,customer_name,'forge-scope',auth.uid()) returning id into customer;
    end if;
  end if;
  insert into public.projects(organization_id,location_id,customer_id,name,source,created_by)
    values(s.organization_id,s.location_id,customer,project_name,'forge-scope',auth.uid()) returning id into project;
  update public.scopes set project_id=project,customer_id=customer where id=s.id;
  insert into public.events(organization_id,entity_type,entity_id,action,source,actor_user_id)
    values(s.organization_id,'scope',s.id,'scope.linked_to_project','forge-scope',auth.uid());
  return project;
end;
$$;
revoke all on function public.forge_link_scope_to_crm(uuid) from public,anon;
grant execute on function public.forge_link_scope_to_crm(uuid) to authenticated;
