-- Phase 3C rollback (خارج migrations/). يعيد حالة ما قبل إدارة الأعضاء.
begin;
drop function if exists public.admin_update_member(uuid, text, boolean);
drop function if exists public.admin_list_members();
drop trigger   if exists trg_protect_owner on public.profiles;
drop function if exists public.protect_owner_profile();
grant insert, update, delete on public.profiles to authenticated;
create policy "profiles admin select" on public.profiles for select to authenticated using (public.current_role() in ('owner','admin'));
create policy "profiles admin insert" on public.profiles for insert to authenticated with check (public.current_role() in ('owner','admin'));
create policy "profiles admin update" on public.profiles for update to authenticated using (public.current_role() in ('owner','admin')) with check (public.current_role() in ('owner','admin'));
create policy "profiles admin delete" on public.profiles for delete to authenticated using (public.current_role() in ('owner','admin'));
commit;
