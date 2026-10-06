-- ================================================================
-- Phase 3B — تراجع كامل (ليس داخل migrations/ حتى لا يُطبَّق تلقائياً).
-- يعيد الحالة تماماً إلى ما قبل الإغلاق: allow-all للجميع + منح anon،
-- وإعادة EXECUTE على set_updated_at لـ anon وPUBLIC.
-- ================================================================
begin;

drop policy if exists "authenticated full access" on public.months;
create policy "allow all on months" on public.months
  for all to public using (true) with check (true);
grant all on public.months to anon;

drop policy if exists "authenticated full access" on public.roster;
create policy "allow all on roster" on public.roster
  for all to public using (true) with check (true);
grant all on public.roster to anon;

drop policy if exists "authenticated full access" on public.students;
create policy "allow all on students" on public.students
  for all to public using (true) with check (true);
grant all on public.students to anon;

drop policy if exists "authenticated full access" on public.session_records;
create policy "allow all on session_records" on public.session_records
  for all to public using (true) with check (true);
grant all on public.session_records to anon;

drop policy if exists "authenticated full access" on public.month_summary;
create policy "allow all on month_summary" on public.month_summary
  for all to public using (true) with check (true);
grant all on public.month_summary to anon;

create policy "allow all on app_users" on public.app_users
  for all to public using (true) with check (true);
grant all on public.app_users to anon;
grant all on public.app_users to authenticated;

grant execute on function public.set_updated_at() to anon;
grant execute on function public.set_updated_at() to public;

commit;
