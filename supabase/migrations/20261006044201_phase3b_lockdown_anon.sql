-- ================================================================
-- Phase 3B — إغلاق anon وتقييد الوصول على authenticated فقط.
-- يُطبَّق بعد نشر كود Auth-only وتأكيد دخول المستخدم الحقيقي على كل جهاز.
-- لا يحذف app_users ولا عمود password (يُؤجَّل لمرحلة لاحقة).
-- مُصمَّم للتطبيق الذرّي عبر Supabase Management API (query endpoint).
-- ================================================================
begin;

-- ---- الجداول الخمسة للبيانات: سياسة authenticated فقط + سحب anon ----
drop policy if exists "allow all on months" on public.months;
create policy "authenticated full access" on public.months
  for all to authenticated using (true) with check (true);
revoke all on public.months from anon;

drop policy if exists "allow all on roster" on public.roster;
create policy "authenticated full access" on public.roster
  for all to authenticated using (true) with check (true);
revoke all on public.roster from anon;

drop policy if exists "allow all on students" on public.students;
create policy "authenticated full access" on public.students
  for all to authenticated using (true) with check (true);
revoke all on public.students from anon;

drop policy if exists "allow all on session_records" on public.session_records;
create policy "authenticated full access" on public.session_records
  for all to authenticated using (true) with check (true);
revoke all on public.session_records from anon;

drop policy if exists "allow all on month_summary" on public.month_summary;
create policy "authenticated full access" on public.month_summary
  for all to authenticated using (true) with check (true);
revoke all on public.month_summary from anon;

-- ---- app_users: يُقفَل تماماً (anon + authenticated)، يبقى موجوداً للتنظيف لاحقاً ----
drop policy if exists "allow all on app_users" on public.app_users;
revoke all on public.app_users from anon;
revoke all on public.app_users from authenticated;

-- ---- الدالة set_updated_at: سحب EXECUTE غير اللازم عن anon وPUBLIC ----
-- (الدالة ترجع trigger وغير مستخدمة ولا قابلة للاستدعاء عبر REST؛ نقفلها احتياطاً)
revoke execute on function public.set_updated_at() from anon;
revoke execute on function public.set_updated_at() from public;

commit;
