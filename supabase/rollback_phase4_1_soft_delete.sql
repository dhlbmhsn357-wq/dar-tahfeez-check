-- Rollback for Phase 4.1 soft delete.
-- WARNING: safe ONLY before any production soft-delete. After tombstones exist,
-- dropping deleted_at RESURRECTS deleted rows. To roll back after use, first
-- hard-delete rows WHERE deleted_at IS NOT NULL (with a backup) after dropping
-- block_hard_delete below. Re-adding the Phase 3B DELETE policies (owner/admin)
-- is intentionally NOT included here because it restores hard delete.

begin;

drop trigger if exists trg_guard_live_student on public.students;
drop trigger if exists trg_guard_live_srec    on public.session_records;
drop trigger if exists trg_guard_live_msum    on public.month_summary;
drop function if exists public.guard_live_student();
drop function if exists public.guard_live_session_record();
drop function if exists public.guard_live_month_summary();

drop trigger if exists trg_block_del_months   on public.months;
drop trigger if exists trg_block_del_students  on public.students;
drop trigger if exists trg_block_del_roster    on public.roster;
drop function if exists public.block_hard_delete();

drop trigger if exists trg_guard_del_months   on public.months;
drop trigger if exists trg_guard_del_students  on public.students;
drop trigger if exists trg_guard_del_roster    on public.roster;
drop function if exists public.guard_soft_delete();

drop index if exists public.idx_months_live;
drop index if exists public.idx_students_live;
drop index if exists public.idx_roster_live;

alter table public.months   drop column if exists deleted_at;
alter table public.students  drop column if exists deleted_at;
alter table public.roster    drop column if exists deleted_at;

commit;
