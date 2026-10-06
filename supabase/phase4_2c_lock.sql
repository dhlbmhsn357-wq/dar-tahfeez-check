-- Phase 4.2c — LOCK (apply ONLY after 4.2b client is deployed and every device has
-- updated). This closes the compatibility window: direct client writes are revoked, so
-- revision becomes fully server-controlled and CAS is the ONLY write path.
-- Until this runs, an old client's direct write still bumps revision but can stale-overwrite.

begin;
revoke insert, update on public.months          from authenticated;
revoke insert, update on public.roster          from authenticated;
revoke insert, update on public.students        from authenticated;
revoke insert, update on public.session_records from authenticated;
revoke insert, update on public.month_summary   from authenticated;
-- SELECT stays (refresh). DELETE already blocked (4.1). Writes go only through
-- rev_apply / rev_soft_delete (SECURITY DEFINER). anon already fully revoked (3B).
commit;

-- Verify after apply (should all hold):
--   direct update months set name=name  -> permission denied for authenticated
--   select has_function_privilege('authenticated','public.rev_apply(text,jsonb,text)','execute')  -> true
