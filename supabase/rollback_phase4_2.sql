-- Rollback for Phase 4.2 (revision + RPCs + lock).
-- If 4.2c lock was applied, RE-GRANT first (step 0) so writes work again, THEN drop.
-- Safe: no row rewrite, deleted_at/tombstones untouched.

begin;

-- step 0 (only if 4.2c lock was applied): restore direct write grants
grant insert, update on public.months          to authenticated;
grant insert, update on public.roster          to authenticated;
grant insert, update on public.students        to authenticated;
grant insert, update on public.session_records to authenticated;
grant insert, update on public.month_summary   to authenticated;

-- drop RPCs
drop function if exists public.rev_apply(text,jsonb,text);
drop function if exists public.rev_soft_delete(text,uuid);

-- drop revision triggers
drop trigger if exists trg_bump_rev_months          on public.months;
drop trigger if exists trg_bump_rev_roster          on public.roster;
drop trigger if exists trg_bump_rev_students        on public.students;
drop trigger if exists trg_bump_rev_session_records on public.session_records;
drop trigger if exists trg_bump_rev_month_summary   on public.month_summary;
drop function if exists public.bump_revision();

-- restore prior updated_at triggers (UPDATE-only on students/roster; remove the new ones)
drop trigger if exists trg_set_upd_students        on public.students;
drop trigger if exists trg_set_upd_roster          on public.roster;
drop trigger if exists trg_set_upd_session_records on public.session_records;
drop trigger if exists trg_set_upd_month_summary   on public.month_summary;
create trigger trg_students_updated_at before update on public.students for each row execute function public.set_updated_at();
create trigger trg_roster_updated_at   before update on public.roster   for each row execute function public.set_updated_at();

-- drop revision columns (last)
alter table public.months          drop column if exists revision;
alter table public.roster          drop column if exists revision;
alter table public.students        drop column if exists revision;
alter table public.session_records drop column if exists revision;
alter table public.month_summary   drop column if exists revision;

commit;
