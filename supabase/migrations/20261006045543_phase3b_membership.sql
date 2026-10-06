-- ================================================================
-- Phase 3B (نهائية) — نموذج متعدد المستخدمين لمؤسسة واحدة + إغلاق anon.
-- يستبدل الـ migration المتجاوَزة 20261006044201_phase3b_lockdown_anon.sql
-- (التي لم تُطبَّق على production إطلاقاً).
-- تطبيق ذرّي عبر Supabase Management API (query endpoint).
-- لا يحذف app_users ولا عمود password.
-- ================================================================
begin;

-- 1) طبقة العضوية/الملف الشخصي مرتبطة بـ auth.uid()
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  role       text not null default 'assistant'
             check (role in ('owner','admin','sheikh','assistant')),
  active     boolean not null default false,       -- لا وصول حتى تفعّله الإدارة
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) دوال مساعدة (SECURITY DEFINER + search_path ثابت) لتفادي التكرار في السياسات
create or replace function public.current_is_active() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.active);
$$;
create or replace function public.current_role() returns text
  language sql stable security definer set search_path = public as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;
revoke execute on function public.current_is_active() from public, anon;
grant  execute on function public.current_is_active() to authenticated;
revoke execute on function public.current_role() from public, anon;
grant  execute on function public.current_role() to authenticated;

-- 3) إنشاء ملف شخصي غير مُفعَّل تلقائياً عند إضافة مستخدم Auth جديد (دالة تريجر فقط)
create or replace function public.handle_new_user() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, active)
  values (new.id, new.raw_user_meta_data->>'full_name', false)
  on conflict (id) do nothing;
  return new;
end; $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- 4) Bootstrap: حساب المالك الحالي فقط (مستخدم Auth موجود). لا مستخدمين آخرين.
insert into public.profiles (id, full_name, role, active)
values ('29e6c6eb-efe1-4b69-84d5-fabfacaf8e05', 'المالك', 'owner', true)
on conflict (id) do update set role = 'owner', active = true;

-- 5) RLS وسياسات profiles (إدارة الأدوار/التفعيل: owner/admin فقط؛ قراءة ذاتية للجميع)
alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
grant select, insert, update, delete on public.profiles to authenticated;
create policy "profiles self select"  on public.profiles for select to authenticated using (id = auth.uid());
create policy "profiles admin select" on public.profiles for select to authenticated using (public.current_role() in ('owner','admin'));
create policy "profiles admin insert" on public.profiles for insert to authenticated with check (public.current_role() in ('owner','admin'));
create policy "profiles admin update" on public.profiles for update to authenticated
  using (public.current_role() in ('owner','admin')) with check (public.current_role() in ('owner','admin'));
create policy "profiles admin delete" on public.profiles for delete to authenticated using (public.current_role() in ('owner','admin'));

-- 6) جداول البيانات: سياسات منفصلة لكل أمر + سحب anon
--    SELECT/INSERT/UPDATE: أي عضو active ؛ DELETE: owner/admin فقط (وactive).
do $$
declare t text;
begin
  foreach t in array array['months','roster','students','session_records','month_summary'] loop
    execute format('drop policy if exists %I on public.%I', 'allow all on '||t, t);
    execute format('create policy %I on public.%I for select to authenticated using (public.current_is_active())', t||' select active', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.current_is_active())', t||' insert active', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.current_is_active()) with check (public.current_is_active())', t||' update active', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.current_is_active() and public.current_role() in (''owner'',''admin''))', t||' delete admin', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- 7) قفل app_users (anon + authenticated). لا يُحذف الجدول ولا عمود password.
drop policy if exists "allow all on app_users" on public.app_users;
revoke all on public.app_users from anon;
revoke all on public.app_users from authenticated;

-- 8) سحب EXECUTE غير اللازم عن set_updated_at (ترجع trigger، غير مستخدمة)
revoke execute on function public.set_updated_at() from anon, public;

commit;
