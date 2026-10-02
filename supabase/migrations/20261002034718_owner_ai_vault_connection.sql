-- Owner credentials never appear in public tables or browser-readable RPCs.
create or replace function forge_private.owner_ai_secret(p_user uuid, p_key text default null)
returns text language plpgsql security definer set search_path='' as $$
declare secret_id uuid; result text;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'Server access only.' using errcode='42501';
  end if;
  if not exists(select 1 from forge_private.platform_owners o join auth.users u on u.id=o.user_id
    where o.user_id=p_user and o.active and u.email_confirmed_at is not null
    and (u.banned_until is null or u.banned_until<now())) then
    raise exception 'Owner access required.' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('forge-owner-gemini:'||p_user::text,0));
  select id into secret_id from vault.secrets where name='forge-owner-gemini:'||p_user::text;
  if p_key is not null then
    if length(trim(p_key))<20 or length(trim(p_key))>256 then raise exception 'Invalid Gemini key.'; end if;
    if secret_id is null then
      perform vault.create_secret(trim(p_key),'forge-owner-gemini:'||p_user::text,'Personal Forge owner AI credential');
    else
      perform vault.update_secret(secret_id,trim(p_key));
    end if;
    return null;
  end if;
  select decrypted_secret into result from vault.decrypted_secrets where id=secret_id;
  return result;
end $$;
revoke all on function forge_private.owner_ai_secret(uuid,text) from public,anon,authenticated;
grant usage on schema forge_private to service_role;
grant execute on function forge_private.owner_ai_secret(uuid,text) to service_role;
create or replace function public.forge_owner_ai_secret(p_user uuid,p_key text default null)
returns text language sql security invoker set search_path='' as $$
  select forge_private.owner_ai_secret(p_user,p_key);
$$;
revoke all on function public.forge_owner_ai_secret(uuid,text) from public,anon,authenticated;
grant execute on function public.forge_owner_ai_secret(uuid,text) to service_role;

