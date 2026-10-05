-- Phase 1 (additive only): add the two month_summary columns the current app writes
-- (sheikh_att / assistant_att) as nullable jsonb. No existing column is dropped or altered.
-- Shape: object keyed by session number -> "حضر" | "غاب", e.g. {"1":"حضر","2":"غاب"}.
-- Idempotent via IF NOT EXISTS so re-applying is safe.
alter table public.month_summary
  add column if not exists sheikh_att jsonb,
  add column if not exists assistant_att jsonb;
