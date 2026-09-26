-- Run after the migration inside BEGIN ... ROLLBACK. No test identity persists.
insert into auth.users(id,email,email_confirmed_at) values
 ('11111111-1111-4111-8111-111111111111','forge-test-one@example.invalid',now()),
 ('22222222-2222-4222-8222-222222222222','forge-test-two@example.invalid',now());
insert into public.organizations(id,name,slug) values
 ('33333333-3333-4333-8333-333333333333','Rollback test organization','forge-rollback-test');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","aal":"aal1"}',true);
select public.forge_request_access('Test user','Test company');
select public.forge_request_access('Duplicate','Duplicate');
do $$ begin
  if (select count(*) from public.forge_access_requests)<>1 then raise exception 'Request visibility/idempotency failed'; end if;
  if exists(select 1 from public.customers) then raise exception 'Unassigned user can read customers'; end if;
  if exists(select 1 from public.forge_audit_log) then raise exception 'Unassigned user can read audit'; end if;
  begin
    perform public.forge_admin_directory();
    raise exception 'Unassigned user can administer';
  exception when insufficient_privilege then null; end;
  begin
    update public.forge_access_requests set status='approved';
    raise exception 'User can approve own request';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated","aal":"aal2"}',true);
do $$ begin
  if exists(select 1 from public.forge_access_requests) then raise exception 'User can read another request'; end if;
  if forge_private.is_platform_owner() then raise exception 'MFA alone grants owner'; end if;
  begin
    perform public.forge_set_membership('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','owner','active');
    raise exception 'User can elevate own role';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"05cef0c7-b5e4-45c8-967e-20e0c14c84f5","role":"authenticated","aal":"aal1"}',true);
do $$ begin
  if not forge_private.is_platform_owner(false) then raise exception 'Owner identity missing'; end if;
  if forge_private.is_platform_owner() then raise exception 'Owner MFA not enforced'; end if;
  begin
    perform public.forge_admin_directory();
    raise exception 'Owner without MFA can administer';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"05cef0c7-b5e4-45c8-967e-20e0c14c84f5","role":"authenticated","aal":"aal2"}',true);
select public.forge_set_membership('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333','viewer','active');
do $$ begin
  if not forge_private.is_platform_owner() then raise exception 'Owner MFA recognition failed'; end if;
  if not exists(select 1 from public.organizations where id='33333333-3333-4333-8333-333333333333') then raise exception 'Owner cross-organization visibility failed'; end if;
  if not exists(select 1 from public.forge_audit_log where entity_type='organization_memberships' and actor_user_id=auth.uid()) then raise exception 'Membership audit missing'; end if;
  if (select status from public.forge_access_requests where user_id='11111111-1111-4111-8111-111111111111')<>'approved' then raise exception 'Approval failed'; end if;
  begin
    delete from public.forge_audit_log;
    raise exception 'Audit log mutable through client';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","aal":"aal1"}',true);
do $$ begin
  if (select count(*) from public.organizations)<>1 then raise exception 'Tenant isolation failed'; end if;
  if exists(select 1 from public.customers) then raise exception 'New tenant can read existing customers'; end if;
end $$;
reset role;
insert into public.scopes(id,organization_id,title,structured_data) values
 ('44444444-4444-4444-8444-444444444444','33333333-3333-4333-8333-333333333333','Integration test','{"fields":{"customer":{"value":"Test customer"},"projectName":{"value":"Test project"}}}');
set local role authenticated;
do $$ begin
  begin
    perform public.forge_link_scope_to_crm('44444444-4444-4444-8444-444444444444');
    raise exception 'Viewer can create CRM project';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.organization_memberships set role='estimator' where user_id='11111111-1111-4111-8111-111111111111';
set local role authenticated;
do $$ declare linked uuid; begin
  linked:=public.forge_link_scope_to_crm('44444444-4444-4444-8444-444444444444');
  if linked is distinct from public.forge_link_scope_to_crm('44444444-4444-4444-8444-444444444444') then raise exception 'Handoff not idempotent'; end if;
  if (select count(*) from public.projects)<>1 or (select count(*) from public.customers)<>1 then raise exception 'Handoff missing or duplicate'; end if;
  if not exists(select 1 from public.projects where id=linked and name='Test project') then raise exception 'Project fields missing'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated","aal":"aal2"}',true);
do $$ begin
  begin
    perform public.forge_link_scope_to_crm('44444444-4444-4444-8444-444444444444');
    raise exception 'Handoff crosses tenant boundary';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: onboarding, idempotency, tenant isolation, privilege escalation, MFA and immutable audit' as result;
