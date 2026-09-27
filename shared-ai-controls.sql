-- Shared Scope AI policy. Credentials are separate Edge Function secrets, never table values.
create table forge_private.ai_policy (
 id boolean primary key default true check(id),
 mode text not null default 'free' check(mode in ('free','business','disabled')),
 per_user_daily integer not null default 5 check(per_user_daily between 1 and 100),
 total_daily integer not null default 50 check(total_daily between 1 and 1000),
 monthly_requests integer not null default 500 check(monthly_requests between 1 and 10000)
);
insert into forge_private.ai_policy(id) values(true);
alter table forge_private.ai_policy enable row level security;
create table forge_private.ai_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 mode text not null, created_at timestamptz not null default now()
);
create index on forge_private.ai_requests(created_at,user_id);
alter table forge_private.ai_requests enable row level security;
revoke all on forge_private.ai_policy,forge_private.ai_requests from public,anon,authenticated;

create function forge_private.ai_settings() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required.'; end if;
 return (select to_jsonb(p)-'id' from forge_private.ai_policy p);
end $$;
create function forge_private.ai_set_policy(p_mode text,p_user integer,p_total integer,p_month integer)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not forge_private.is_platform_owner() then raise exception 'Owner verification required.' using errcode='42501'; end if;
 if p_mode is null or p_user is null or p_total is null or p_month is null then raise exception 'All settings are required.'; end if;
 update forge_private.ai_policy set mode=p_mode,per_user_daily=p_user,total_daily=p_total,monthly_requests=p_month where id;
end $$;
create function public.forge_ai_settings() returns jsonb language sql security invoker set search_path='' as $$ select forge_private.ai_settings(); $$;
create function public.forge_ai_set_policy(p_mode text,p_user integer,p_total integer,p_month integer)
returns void language sql security invoker set search_path='' as $$ select forge_private.ai_set_policy(p_mode,p_user,p_total,p_month); $$;
revoke all on function forge_private.ai_settings(),forge_private.ai_set_policy(text,integer,integer,integer),public.forge_ai_settings(),public.forge_ai_set_policy(text,integer,integer,integer) from public,anon;
grant execute on function forge_private.ai_settings(),forge_private.ai_set_policy(text,integer,integer,integer),public.forge_ai_settings(),public.forge_ai_set_policy(text,integer,integer,integer) to authenticated;

-- Only the authenticated gateway may reserve shared usage. Lock serializes quota checks.
create function public.forge_ai_reserve(p_user uuid,p_mode text) returns uuid language plpgsql security definer set search_path='' as $$
declare p forge_private.ai_policy; r uuid;
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception 'Gateway only.' using errcode='42501'; end if;
 if not exists(select 1 from auth.users u where u.id=p_user and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<now()))
 or not exists(select 1 from public.organization_memberships m where m.user_id=p_user and m.status='active') then raise exception 'Approved workspace access required.'; end if;
 select * into p from forge_private.ai_policy where id for update;
 if p.mode='disabled' or p.mode<>p_mode then raise exception 'Shared AI mode changed or is disabled. Refresh and try again.'; end if;
 if (select count(*) from forge_private.ai_requests where created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC' and user_id=p_user)>=p.per_user_daily
 or (select count(*) from forge_private.ai_requests where created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')>=p.total_daily
 or (select count(*) from forge_private.ai_requests where created_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC')>=p.monthly_requests
 then raise exception 'Shared AI allowance reached. No paid fallback will be used.'; end if;
 insert into forge_private.ai_requests(user_id,mode) values(p_user,p.mode) returning id into r;
 return r;
end $$;
revoke all on function public.forge_ai_reserve(uuid,text) from public,anon,authenticated;
grant execute on function public.forge_ai_reserve(uuid,text) to service_role;
create trigger forge_audit_change after update on forge_private.ai_policy for each row execute function forge_private.audit_business_change();

