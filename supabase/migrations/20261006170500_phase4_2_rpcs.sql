-- Phase 4.2 — write RPCs. revision is NEVER written here (single bump source is the
-- bump_revision trigger from 4.2a; no double increment). All amounts/ids as before.
-- SECURITY DEFINER: bypasses table RLS but auth.uid() still reflects the CALLER, so
-- guard_soft_delete / guard_live_* still enforce membership/role/no-ghost on the write.
-- revision is passed/returned as TEXT (decimal string) to avoid JS number precision.

begin;

-- ============ content write (insert or CAS update) ============
create or replace function public.rev_apply(p_table text, p_payload jsonb, p_base_revision text)
  returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_allowed text[] := array['months','roster','students','session_records','month_summary'];
  v_has_del boolean;
  v_key text; v_conflict text; v_set text; v_cols text; v_vals text;
  v_existing jsonb; v_rev bigint; v_del timestamptz; v_newrev bigint; v_cnt int;
  v_a jsonb; v_b jsonb;
begin
  if not (p_table = any(v_allowed)) then raise exception 'rev_apply: table not allowed: %', p_table; end if;
  if not public.current_is_active() then raise exception 'rev_apply: not an active member'; end if;

  -- never let a content write set protected columns
  p_payload := p_payload - 'revision' - 'deleted_at';
  v_has_del := p_table in ('months','roster','students');

  -- natural key predicate (qualified with t. so UPDATE ... FROM r is unambiguous) + ON CONFLICT target
  if p_table in ('months','roster','students') then
    v_key := format('t.id = %L::uuid', p_payload->>'id');              v_conflict := '(id)';
  elsif p_table = 'session_records' then
    v_key := format('t.student_id = %L::uuid and t.session_number = %L::int', p_payload->>'student_id', p_payload->>'session_number');
    v_conflict := '(student_id, session_number)';
  else -- month_summary
    v_key := format('t.month_id = %L::uuid', p_payload->>'month_id');  v_conflict := '(month_id)';
  end if;

  -- lock existing row (if any)
  execute format(
    'select to_jsonb(t), t.revision %s from public.%I t where %s for update',
    case when v_has_del then ', t.deleted_at' else ', null::timestamptz' end, p_table, v_key)
    into v_existing, v_rev, v_del;

  ---------------- no existing row ----------------
  if v_existing is null then
    if p_base_revision is not null then
      return jsonb_build_object('status','conflict','reason','missing','cloud_row', null);
    end if;
    -- first insert: only columns present in payload (let DB defaults apply; trigger forces
    -- revision=1 and updated_at; deleted_at already stripped). guard_live_* still fires.
    select string_agg(format('%I', column_name), ', '), string_agg(format('r.%I', column_name), ', ')
      into v_cols, v_vals
      from information_schema.columns c
      where c.table_schema='public' and c.table_name=p_table
        and c.column_name <> 'revision' and p_payload ? c.column_name;
    execute format('insert into public.%I (%s) select %s from (select (jsonb_populate_record(null::public.%I,$1)).*) r on conflict %s do nothing',
                   p_table, v_cols, v_vals, p_table, v_conflict) using p_payload;
    get diagnostics v_cnt = row_count;
    if v_cnt = 1 then
      execute format('select t.revision from public.%I t where %s', p_table, v_key) into v_newrev;
      return jsonb_build_object('status','applied','revision', v_newrev::text);
    end if;
    -- create-race: a row with the same natural key already exists -> re-read it
    execute format('select to_jsonb(t), t.revision from public.%I t where %s for update', p_table, v_key)
      into v_existing, v_rev;
  end if;

  ---------------- existing row ----------------
  -- delete-wins (4.1) is always highest
  if v_has_del and v_del is not null then
    return jsonb_build_object('status','superseded_by_delete','cloud_row', v_existing);
  end if;

  -- content comparison (ignore id/revision/timestamps/tombstone). Treat NULL and '' as the same
  -- "unset" so a cloud row's default-empty columns don't differ from a payload that omits them.
  select coalesce(jsonb_object_agg(key,val),'{}'::jsonb) into v_a
    from jsonb_each(v_existing - 'id' - 'revision' - 'updated_at' - 'created_at' - 'deleted_at') e(key,val)
    where val <> 'null'::jsonb and val <> '""'::jsonb;
  select coalesce(jsonb_object_agg(key,val),'{}'::jsonb) into v_b
    from jsonb_each(p_payload  - 'id' - 'revision' - 'updated_at' - 'created_at' - 'deleted_at') e(key,val)
    where val <> 'null'::jsonb and val <> '""'::jsonb;

  if p_base_revision is null then
    -- create-race: existing row found while we tried to insert
    if v_a = v_b then
      return jsonb_build_object('status','exists_identical','cloud_row', v_existing, 'revision', v_rev::text);
    else
      return jsonb_build_object('status','conflict','reason','create_race','cloud_row', v_existing, 'cloud_revision', v_rev::text);
    end if;
  end if;

  -- CAS
  if v_rev::text <> p_base_revision then
    return jsonb_build_object('status','conflict','reason','revision_mismatch','cloud_row', v_existing, 'cloud_revision', v_rev::text);
  end if;

  -- base matches -> apply whole-row content (safe: client had latest). trigger bumps revision + updated_at.
  select string_agg(format('%I = r.%I', column_name, column_name), ', ') into v_set
    from information_schema.columns c
    where c.table_schema='public' and c.table_name=p_table
      and c.column_name not in ('id','revision','updated_at','created_at','deleted_at')
      and p_payload ? c.column_name;

  if v_set is not null then
    execute format('update public.%I t set %s from (select (jsonb_populate_record(null::public.%I, $1)).*) r where %s',
                   p_table, v_set, p_table, v_key) using p_payload;
  end if;
  execute format('select t.revision from public.%I t where %s', p_table, v_key) into v_newrev;
  return jsonb_build_object('status','applied','revision', v_newrev::text);
end; $$;

-- ============ soft delete (idempotent, delete-wins) ============
create or replace function public.rev_soft_delete(p_table text, p_id uuid)
  returns jsonb language plpgsql security definer set search_path = public as $$
declare v_existing jsonb; v_del timestamptz;
begin
  if not (p_table in ('months','roster','students')) then raise exception 'rev_soft_delete: table not allowed: %', p_table; end if;
  -- membership/role enforced by guard_soft_delete trigger on the deleted_at transition
  execute format('select to_jsonb(t), t.deleted_at from public.%I t where id = %L::uuid for update', p_table, p_id)
    into v_existing, v_del;
  if v_existing is null then
    return jsonb_build_object('status','missing');
  end if;
  if v_del is not null then
    -- already tombstoned: do nothing (no re-date, no guard clash, no revision bump)
    return jsonb_build_object('status','already_deleted','cloud_row', v_existing);
  end if;
  execute format('update public.%I set deleted_at = now() where id = %L::uuid', p_table, p_id);  -- trigger bumps revision
  return jsonb_build_object('status','applied');
end; $$;

-- only authenticated (active checked inside / by guards); never anon/public
revoke all on function public.rev_apply(text,jsonb,text)       from public, anon;
revoke all on function public.rev_soft_delete(text,uuid)        from public, anon;
grant execute on function public.rev_apply(text,jsonb,text)     to authenticated;
grant execute on function public.rev_soft_delete(text,uuid)      to authenticated;

commit;
