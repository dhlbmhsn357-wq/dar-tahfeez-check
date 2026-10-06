-- Phase 4.2a — server-controlled monotonic revision (ADDITIVE; no behavior lock yet).
-- revision is owned by the DB (single bump source = bump_revision trigger). Clients
-- can never choose/pin/decrease it. updated_at stays informational, server-set.
-- Direct client writes remain allowed during the compatibility window; CAS enforcement
-- and the REVOKE lock come later (4.2c), only after all devices run 4.2b code.

begin;

-- (a) revision columns (existing rows backfill to 1 via default; no row rewrite)
alter table public.months          add column revision bigint not null default 1;
alter table public.roster          add column revision bigint not null default 1;
alter table public.students        add column revision bigint not null default 1;
alter table public.session_records add column revision bigint not null default 1;
alter table public.month_summary   add column revision bigint not null default 1;

-- (b) SINGLE bump source: forces revision server-side on every insert/update,
--     including legacy PWA direct upserts during the compatibility window.
create or replace function public.bump_revision() returns trigger
  language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    new.revision := 1;                    -- client cannot choose
  else
    new.revision := old.revision + 1;     -- client cannot pin/decrease
  end if;
  return new;
end; $$;

create trigger trg_bump_rev_months          before insert or update on public.months          for each row execute function public.bump_revision();
create trigger trg_bump_rev_roster          before insert or update on public.roster          for each row execute function public.bump_revision();
create trigger trg_bump_rev_students        before insert or update on public.students        for each row execute function public.bump_revision();
create trigger trg_bump_rev_session_records before insert or update on public.session_records for each row execute function public.bump_revision();
create trigger trg_bump_rev_month_summary   before insert or update on public.month_summary   for each row execute function public.bump_revision();

-- (c) updated_at = server-set, informational only (INSERT+UPDATE) on the 4 tables that have it.
--     months has no updated_at (unchanged).
drop trigger if exists trg_students_updated_at on public.students;
drop trigger if exists trg_roster_updated_at   on public.roster;
create trigger trg_set_upd_students        before insert or update on public.students        for each row execute function public.set_updated_at();
create trigger trg_set_upd_roster          before insert or update on public.roster          for each row execute function public.set_updated_at();
create trigger trg_set_upd_session_records before insert or update on public.session_records for each row execute function public.set_updated_at();
create trigger trg_set_upd_month_summary   before insert or update on public.month_summary   for each row execute function public.set_updated_at();

commit;
