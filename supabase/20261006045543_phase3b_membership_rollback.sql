-- ================================================================
-- Phase 3B (نهائية) — تراجع كامل إلى حالة ما قبل الإغلاق.
-- خارج migrations/ حتى لا يُطبَّق تلقائياً.
-- تحذير: يحذف جدول profiles وكل بيانات العضوية؛ لا تستخدمه إلا لإرجاع فوري
--        قبل إنشاء حسابات أعضاء حقيقيين.
-- ================================================================
begin;

-- 1) إرجاع سياسات جداول البيانات إلى allow-all + منح anon
do $$
declare t text;
begin
  foreach t in array array['months','roster','students','session_records','month_summary'] loop
    execute format('drop policy if exists %I on public.%I', t||' select active', t);
    execute format('drop policy if exists %I on public.%I', t||' insert active', t);
    execute format('drop policy if exists %I on public.%I', t||' update active', t);
    execute format('drop policy if exists %I on public.%I', t||' delete admin', t);
    execute format('create policy %I on public.%I for all to public using (true) with check (true)', 'allow all on '||t, t);
    execute format('grant all on public.%I to anon', t);
  end loop;
end $$;

-- 2) إرجاع app_users
create policy "allow all on app_users" on public.app_users for all to public using (true) with check (true);
grant all on public.app_users to anon;
grant all on public.app_users to authenticated;

-- 3) إرجاع EXECUTE على set_updated_at
grant execute on function public.set_updated_at() to anon;
grant execute on function public.set_updated_at() to public;

-- 4) إزالة طبقة العضوية بالكامل
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
-- السياسات تُحذف تلقائياً مع الجدول
drop table if exists public.profiles;
drop function if exists public.current_is_active();
drop function if exists public.current_role();

commit;
