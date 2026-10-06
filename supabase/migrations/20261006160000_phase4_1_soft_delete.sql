-- Phase 4.1 — Soft delete (tombstones) + hard-delete lockout + parent guards
-- Entities carrying deleted_at: months, students, roster.
-- Children (session_records, month_summary) have NO column; their deletion is
-- DERIVED from the parent tombstone, both client-side and via server guards.
-- delete-wins policy; NO updated_at / LWW here.

begin;

-- 1) tombstone columns (additive) + partial live indexes
alter table public.months   add column if not exists deleted_at timestamptz;
alter table public.students  add column if not exists deleted_at timestamptz;
alter table public.roster    add column if not exists deleted_at timestamptz;

create index if not exists idx_months_live   on public.months   (id)       where deleted_at is null;
create index if not exists idx_students_live  on public.students (month_id) where deleted_at is null;
create index if not exists idx_roster_live    on public.roster   (id)       where deleted_at is null;

-- 2) guard_soft_delete: only active owner/admin may SET a tombstone;
--    restore (timestamp->NULL) and re-date (timestamp->timestamp) forbidden for everyone.
create or replace function public.guard_soft_delete() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if NEW.deleted_at is distinct from OLD.deleted_at then
    if OLD.deleted_at is not null and NEW.deleted_at is null then
      raise exception 'restore is not allowed in phase 4.1';
    elsif OLD.deleted_at is not null and NEW.deleted_at is not null then
      raise exception 'cannot re-date an existing tombstone';
    elsif OLD.deleted_at is null and NEW.deleted_at is not null then
      if not (public.current_is_active() and public.current_role() in ('owner','admin')) then
        raise exception 'only active owner/admin can delete';
      end if;
    end if;
  end if;
  return NEW;
end; $$;
revoke execute on function public.guard_soft_delete() from public, anon, authenticated;

drop trigger if exists trg_guard_del_months   on public.months;
drop trigger if exists trg_guard_del_students  on public.students;
drop trigger if exists trg_guard_del_roster    on public.roster;
create trigger trg_guard_del_months   before update of deleted_at on public.months   for each row execute function public.guard_soft_delete();
create trigger trg_guard_del_students  before update of deleted_at on public.students  for each row execute function public.guard_soft_delete();
create trigger trg_guard_del_roster    before update of deleted_at on public.roster    for each row execute function public.guard_soft_delete();

-- 3) block hard DELETE on the three entities (no path may hard-delete / cascade past tombstones)
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies
           where schemaname='public' and tablename in ('months','students','roster') and cmd='DELETE'
  loop execute format('drop policy %I on public.%I', r.policyname, r.tablename); end loop;
end $$;

create or replace function public.block_hard_delete() returns trigger
  language plpgsql as $$
begin raise exception 'hard delete disabled; use soft delete (deleted_at)'; end; $$;

drop trigger if exists trg_block_del_months   on public.months;
drop trigger if exists trg_block_del_students  on public.students;
drop trigger if exists trg_block_del_roster    on public.roster;
create trigger trg_block_del_months   before delete on public.months   for each row execute function public.block_hard_delete();
create trigger trg_block_del_students  before delete on public.students  for each row execute function public.block_hard_delete();
create trigger trg_block_del_roster    before delete on public.roster    for each row execute function public.block_hard_delete();

-- 4) parent guards: reject writing a LIVE child under a dead parent (ghost-write prevention)
create or replace function public.guard_live_student() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if NEW.deleted_at is null then
    if exists(select 1 from public.months m where m.id = NEW.month_id and m.deleted_at is not null)
    or exists(select 1 from public.roster r where r.id = NEW.roster_id and r.deleted_at is not null) then
      raise exception 'cannot write a live student under a deleted month/roster';
    end if;
  end if;
  return NEW;
end; $$;
revoke execute on function public.guard_live_student() from public, anon, authenticated;
drop trigger if exists trg_guard_live_student on public.students;
create trigger trg_guard_live_student before insert or update on public.students
  for each row execute function public.guard_live_student();

create or replace function public.guard_live_session_record() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if exists(
     select 1 from public.students s
     left join public.months m on m.id = s.month_id
     left join public.roster  r on r.id = s.roster_id
     where s.id = NEW.student_id
       and (s.deleted_at is not null or m.deleted_at is not null or r.deleted_at is not null)
  ) then
     raise exception 'cannot write a session_record under a deleted student';
  end if;
  return NEW;
end; $$;
revoke execute on function public.guard_live_session_record() from public, anon, authenticated;
drop trigger if exists trg_guard_live_srec on public.session_records;
create trigger trg_guard_live_srec before insert or update on public.session_records
  for each row execute function public.guard_live_session_record();

create or replace function public.guard_live_month_summary() returns trigger
  language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from public.months m where m.id = NEW.month_id and m.deleted_at is not null) then
     raise exception 'cannot write a month_summary under a deleted month';
  end if;
  return NEW;
end; $$;
revoke execute on function public.guard_live_month_summary() from public, anon, authenticated;
drop trigger if exists trg_guard_live_msum on public.month_summary;
create trigger trg_guard_live_msum before insert or update on public.month_summary
  for each row execute function public.guard_live_month_summary();

commit;
