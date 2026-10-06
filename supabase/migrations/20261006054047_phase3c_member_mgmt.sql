-- ================================================================
-- Phase 3C — إدارة الأعضاء عبر RPC آمنة (SECURITY DEFINER) فقط.
-- لا UPDATE مباشر على profiles من الواجهة؛ لا كشف auth.users؛ لا service-role.
-- تطبيق ذرّي عبر Supabase Management API.
-- ================================================================
begin;

-- 1) تضييق profiles: الإدارة عبر RPC فقط. نُبقي self-select فقط.
drop policy if exists "profiles admin select" on public.profiles;
drop policy if exists "profiles admin insert" on public.profiles;
drop policy if exists "profiles admin update" on public.profiles;
drop policy if exists "profiles admin delete" on public.profiles;
revoke insert, update, delete on public.profiles from authenticated; -- select يبقى لـ self-select

-- 2) حماية المالك على مستوى القاعدة (ضمان صلب ضد أي مسار)
create or replace function public.protect_owner_profile() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if OLD.role = 'owner' and (NEW.role <> 'owner' or NEW.active = false) then
    raise exception 'owner profile cannot be demoted or deactivated';
  end if;
  return NEW;
end; $$;
revoke execute on function public.protect_owner_profile() from public, anon, authenticated;
drop trigger if exists trg_protect_owner on public.profiles;
create trigger trg_protect_owner before update on public.profiles
  for each row execute function public.protect_owner_profile();

-- 3) قائمة الأعضاء: active + owner/admin فقط (تُرجع البريد من auth.users)
create or replace function public.admin_list_members()
  returns table(id uuid, full_name text, email text, role text, active boolean)
  language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.current_is_active() and public.current_role() in ('owner','admin')) then
    raise exception 'not authorized';
  end if;
  return query
    select p.id, p.full_name, u.email::text, p.role, p.active
    from public.profiles p join auth.users u on u.id = p.id
    order by (p.role = 'owner') desc, p.full_name nulls last, u.email;
end; $$;
revoke execute on function public.admin_list_members() from public, anon;
grant  execute on function public.admin_list_members() to authenticated;

-- 4) تعديل عضو: active owner/admin فقط؛ لا نفس؛ لا owner هدفاً؛ لا إسناد owner.
--    owner يدير admin/sheikh/assistant؛ admin يدير sheikh/assistant فقط.
--    قفل صف الهدف (FOR UPDATE) لأمان التزامن.
create or replace function public.admin_update_member(p_target uuid, p_role text default null, p_active boolean default null)
  returns void language plpgsql security definer set search_path = public as $$
declare
  v_caller text := public.current_role();
  v_role   text;
begin
  if not (public.current_is_active() and v_caller in ('owner','admin')) then
    raise exception 'not authorized';
  end if;
  if p_target = auth.uid() then
    raise exception 'cannot modify your own membership';
  end if;
  select role into v_role from public.profiles where id = p_target for update; -- row lock
  if v_role is null then raise exception 'member not found'; end if;
  if v_role = 'owner' then raise exception 'cannot modify an owner'; end if;
  if p_role is not null and p_role not in ('admin','sheikh','assistant') then
    raise exception 'invalid role';
  end if;
  if v_caller = 'admin' then
    if v_role = 'admin' then raise exception 'admins cannot modify another admin'; end if;
    if p_role = 'admin' then raise exception 'admins cannot assign the admin role'; end if;
  end if;
  update public.profiles
     set role   = coalesce(p_role, role),
         active = coalesce(p_active, active),
         updated_at = now()
   where id = p_target;
end; $$;
revoke execute on function public.admin_update_member(uuid, text, boolean) from public, anon;
grant  execute on function public.admin_update_member(uuid, text, boolean) to authenticated;

commit;
