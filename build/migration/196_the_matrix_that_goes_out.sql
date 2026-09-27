-- The escalation matrix as a thing that is SENT, not only a thing that is
-- kept.
--
-- The tool already held the matrix: five levels a branch, matrix_contact for
-- the rows, branch_effective_matrix for the client default a branch falls
-- back on, branch_matrix_state for completeness computed and never stored.
-- What it had nowhere was the monthly act -- the pack that goes to the
-- client, who it went to, when, and what it said at the moment it left.
--
-- Three things follow from that being a record rather than a screen:
--
--   A snapshot is frozen at the moment of sending. A contact who changes on
--   the 20th must not silently rewrite what the client was told on the 3rd,
--   or the trail answers a question nobody asked.
--
--   A branch with a blank level is held back and named, never sent with a
--   gap in it. An escalation matrix with a hole is worse than no matrix: it
--   reads as complete.
--
--   Sending twice in a month is not sending twice. The dispatch is unique on
--   (client, period), and re-sending re-uses the row and says so.

create table if not exists matrix_dispatch (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid not null references client(id),
  period         date not null,                    -- the first of the month
  snapshot       jsonb not null,                   -- what was sent, frozen
  branch_count   int not null,
  held_back      int not null default 0,
  recipients     text[] not null default '{}',
  prepared_by    uuid not null references person(id),
  prepared_at    timestamptz not null default now(),
  sent_at        timestamptz,
  note           text,
  constraint matrix_dispatch_once unique (client_id, period)
);

comment on table matrix_dispatch is
  'One month''s escalation matrix for one client: what was sent, to whom, when, and what it said at the moment it left.';

create index if not exists matrix_dispatch_period on matrix_dispatch (period desc, client_id);

revoke all on table matrix_dispatch from public, anon, authenticated;

-- The branches a person may see. This is branchScope() from scope.ts, in SQL,
-- because the service is not allowed to be the only thing that knows. An
-- administrator sees every branch, which is the owner's own rule about
-- operations.alert and not an accident of coverage.
create or replace function public.matrix_scope_branches(p_person uuid)
returns table (branch_id uuid) language sql stable security definer
set search_path to 'public' as $fn$
  select b.id from branch b
   where exists (select 1 from person p where p.id = p_person and p.app_role = 'ADMIN')
  union
  select distinct b.id
    from coverage_rule r
    cross join lateral coverage_resolve(r) cr(branch_id)
    join branch b on b.id = cr.branch_id
   where r.person_id = p_person
     and (r.effective_to is null or r.effective_to >= current_date);
$fn$;

-- May this person see client data at all? The same table the services read,
-- asked here so the answer cannot differ between them.
create or replace function public.matrix_client_view(p_person uuid)
returns text language sql stable security definer set search_path to 'public' as $fn$
  select case when p.app_role = 'ADMIN' then 'full'
              else coalesce(v.view_kind, 'none') end
    from person p
    left join client_view_policy v on v.department = p.department
   where p.id = p_person;
$fn$;

-- ---------------------------------------------------------------- the pack
--
-- What would go out for one client this month, and what would be held back.
-- Nothing here sends anything; a person should be able to look at the pack
-- before it leaves, and a screen should be able to show it without the act
-- of looking counting as the act of sending.
create or replace function public.matrix_pack(
  p_person uuid, p_client uuid, p_period date default current_date)
returns jsonb language plpgsql stable security definer
set search_path to 'public' as $fn$
declare
  v_view text; v_period date; c client%rowtype;
  branches jsonb; held jsonb; n_ok int; n_held int; d matrix_dispatch;
begin
  v_view := matrix_client_view(p_person);
  if v_view is null or v_view = 'none' then
    return jsonb_build_object('error','no_client_view',
      'reason','Your function does not see client data, so it does not see the matrix either.');
  end if;

  v_period := date_trunc('month', p_period)::date;
  select * into c from client where id = p_client;
  if c.id is null then return jsonb_build_object('error','no_such_client'); end if;

  -- the branches of this client that this person covers, with their five
  -- levels as they currently stand
  with mine as (
    select b.id, b.code, b.name
      from branch b
      join matrix_scope_branches(p_person) s on s.branch_id = b.id
     where b.client_id = p_client and b.status = 'ACTIVE'
  ),
  lv as (
    select m.id as branch_id, m.code, m.name,
           coalesce(jsonb_agg(jsonb_build_object(
             'level', e.level, 'levelName', e.level_name, 'name', e.name,
             'mobile', case when v_view = 'contacts' then null else e.mobile end,
             'email',  case when v_view = 'contacts' then null else e.email end,
             'inherited', e.inherited) order by e.level)
             filter (where e.level is not null), '[]'::jsonb) as levels,
           count(*) filter (
             where e.name is not null and btrim(e.name) <> ''
               and (coalesce(btrim(e.mobile),'') <> '' or coalesce(btrim(e.email),'') <> '')
           ) as complete,
           bool_or(e.inherited) as using_default
      from mine m
      left join branch_effective_matrix e on e.branch_id = m.id
     group by m.id, m.code, m.name
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'branchId', branch_id, 'code', code, 'name', name,
      'levels', levels, 'complete', complete,
      'usingClientDefault', coalesce(using_default, false))
      order by name) filter (where complete = 5), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'branchId', branch_id, 'code', code, 'name', name,
      'complete', complete, 'missing', 5 - complete)
      order by name) filter (where complete < 5), '[]'::jsonb),
    count(*) filter (where complete = 5),
    count(*) filter (where complete < 5)
    into branches, held, n_ok, n_held
  from lv;

  select * into d from matrix_dispatch
   where client_id = p_client and period = v_period;

  return jsonb_build_object(
    'client', jsonb_build_object('clientId', c.id, 'code', c.code, 'name', c.name),
    'period', v_period,
    'view', v_view,
    'branches', branches, 'heldBack', held,
    'ready', n_ok, 'incomplete', n_held,
    'recipients', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k.kind, 'name', k.name, 'email', k.email)
             order by k.kind, k.email)
        from client_contact k where k.client_id = p_client), '[]'::jsonb),
    'dispatch', case when d.id is null then null else jsonb_build_object(
      'dispatchId', d.id, 'sentAt', d.sent_at, 'recipients', to_jsonb(d.recipients),
      'branchCount', d.branch_count, 'heldBack', d.held_back) end,
    'says', case
      when n_ok = 0 and n_held = 0 then
        'You cover no active branch of this client, so there is nothing to send.'
      when n_ok = 0 then
        'Every branch you cover is missing a level, so there is nothing that can be sent. '
        || 'A matrix with a gap in it reads as complete, which is worse than no matrix.'
      when n_held > 0 then
        n_ok || ' branch(es) are ready. ' || n_held || ' are held back until their '
        || 'missing levels are filled, and are named below rather than sent with a gap.'
      else 'All ' || n_ok || ' branch(es) are complete.' end);
end $fn$;

revoke all on function public.matrix_scope_branches(uuid) from public, anon, authenticated;
revoke all on function public.matrix_client_view(uuid) from public, anon, authenticated;
revoke all on function public.matrix_pack(uuid, uuid, date) from public, anon, authenticated;

-- ------------------------------------------------------- the month's state
--
-- What a branch manager opens their page to: every client they cover, how
-- many of its branches are ready, and whether this month's matrix has gone
-- out. One row per client, because that is the unit the thing is sent in.
create or replace function public.matrix_month(
  p_person uuid, p_period date default current_date)
returns jsonb language plpgsql stable security definer
set search_path to 'public' as $fn$
declare v_view text; v_period date; rows jsonb; n_clients int; n_sent int; n_gap int;
begin
  v_view := matrix_client_view(p_person);
  if v_view is null or v_view = 'none' then
    return jsonb_build_object('clients','[]'::jsonb, 'period', date_trunc('month', p_period)::date,
      'says','Your function does not see client data, so the matrix is not yours to send.');
  end if;
  v_period := date_trunc('month', p_period)::date;

  with mine as (
    select b.id, b.client_id
      from branch b
      join matrix_scope_branches(p_person) s on s.branch_id = b.id
     where b.status = 'ACTIVE'
  ),
  per as (
    select m.client_id,
           count(*) as branches,
           count(*) filter (where st.complete_levels = 5) as ready,
           count(*) filter (where st.complete_levels < 5) as incomplete
      from mine m
      join branch_matrix_state st on st.branch_id = m.id
     group by m.client_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'clientId', c.id, 'code', c.code, 'name', c.name,
           'branches', p.branches, 'ready', p.ready, 'incomplete', p.incomplete,
           'recipients', (select count(*) from client_contact k where k.client_id = c.id),
           'sentAt', d.sent_at, 'dispatchId', d.id,
           'sentCount', d.branch_count, 'heldBack', d.held_back)
           order by c.name), '[]'::jsonb),
         count(*), count(*) filter (where d.sent_at is not null),
         count(*) filter (where p.incomplete > 0)
    into rows, n_clients, n_sent, n_gap
    from per p
    join client c on c.id = p.client_id
    left join matrix_dispatch d on d.client_id = c.id and d.period = v_period
   where c.status = 'ACTIVE';

  return jsonb_build_object(
    'period', v_period, 'clients', rows,
    'total', n_clients, 'sent', n_sent, 'withGaps', n_gap,
    'maySend', v_view = 'matrix' or v_view = 'full',
    'says', case
      when n_clients = 0 then 'You cover no active branch, so there is no matrix to send.'
      when n_sent = n_clients then 'This month''s matrix has gone to all ' || n_clients || ' client(s).'
      else (n_clients - n_sent) || ' of ' || n_clients || ' client(s) are still waiting for '
           || 'this month''s matrix'
           || case when n_gap > 0 then ', and ' || n_gap || ' have a branch with a missing level.'
                   else '.' end end);
end $fn$;

-- --------------------------------------------------------------- sending
--
-- Freezes what is ready, records who it went to, and hands the caller the
-- text to put in the post. The service queues the mail through the same
-- outbox as everything else; this decides whether it may, what it says, and
-- what the trail records.
create or replace function public.matrix_send(
  p_person uuid, p_client uuid, p_period date, p_to text[], p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  pack jsonb; v_view text; v_period date; d matrix_dispatch;
  body text; b jsonb; lv jsonb; again boolean := false;
begin
  v_view := matrix_client_view(p_person);
  if v_view not in ('matrix','full') then
    return jsonb_build_object('error','read_only',
      'reason','Operations owns the matrix. Your function may read it and not send it.');
  end if;

  v_period := date_trunc('month', p_period)::date;
  pack := matrix_pack(p_person, p_client, v_period);
  if pack ? 'error' then return pack; end if;
  if (pack->>'ready')::int = 0 then
    return jsonb_build_object('error','nothing_complete', 'reason', pack->>'says');
  end if;
  if p_to is null or array_length(p_to, 1) is null then
    return jsonb_build_object('error','no_recipient',
      'reason','Nobody was named to send it to. The client''s contacts are on the pack; pick at least one.');
  end if;

  -- the letter. Plain text on purpose: an escalation matrix is read on a
  -- phone by somebody who is already having a bad morning.
  body := 'Escalation matrix for ' || (pack#>>'{client,name}') || ' -- '
       || to_char(v_period, 'FMMonth YYYY') || E'\n\n';
  for b in select jsonb_array_elements(pack->'branches') loop
    body := body || (b->>'name') || ' (' || coalesce(b->>'code','') || ')' || E'\n';
    for lv in select jsonb_array_elements(b->'levels') loop
      body := body || '  L' || (lv->>'level') || '  ' || coalesce(lv->>'levelName','')
           || ' -- ' || coalesce(lv->>'name','')
           || case when coalesce(lv->>'mobile','') <> '' then ', ' || (lv->>'mobile') else '' end
           || case when coalesce(lv->>'email','')  <> '' then ', ' || (lv->>'email')  else '' end
           || E'\n';
    end loop;
    body := body || E'\n';
  end loop;
  if (pack->>'incomplete')::int > 0 then
    body := body || 'Not included this month, because a level is still blank:' || E'\n';
    for b in select jsonb_array_elements(pack->'heldBack') loop
      body := body || '  ' || (b->>'name') || ' (' || coalesce(b->>'code','') || ') -- '
           || (b->>'missing') || ' level(s) missing' || E'\n';
    end loop;
    body := body || E'\n';
  end if;
  if coalesce(btrim(p_note),'') <> '' then body := body || p_note || E'\n'; end if;

  select * into d from matrix_dispatch where client_id = p_client and period = v_period;
  again := d.id is not null and d.sent_at is not null;

  insert into matrix_dispatch (client_id, period, snapshot, branch_count, held_back,
                               recipients, prepared_by, sent_at, note)
  values (p_client, v_period, pack, (pack->>'ready')::int, (pack->>'incomplete')::int,
          p_to, p_person, now(), p_note)
  on conflict (client_id, period) do update
    set snapshot = excluded.snapshot, branch_count = excluded.branch_count,
        held_back = excluded.held_back, recipients = excluded.recipients,
        prepared_by = excluded.prepared_by, sent_at = now(), note = excluded.note
  returning * into d;

  insert into audit_entry (actor_id, action, entity_type, entity_ref, old_value, new_value)
  values (p_person, case when again then 'MATRIX_RESENT' else 'MATRIX_SENT' end,
          'client', p_client::text, null,
          jsonb_build_object('period', v_period, 'to', to_jsonb(p_to),
                             'branches', (pack->>'ready')::int,
                             'heldBack', (pack->>'incomplete')::int));

  return jsonb_build_object('ok', true, 'dispatchId', d.id, 'period', v_period,
    'subject', 'Escalation matrix -- ' || (pack#>>'{client,name}') || ' -- '
               || to_char(v_period, 'FMMonth YYYY'),
    'body', body, 'to', to_jsonb(p_to),
    'branches', (pack->>'ready')::int, 'heldBack', (pack->>'incomplete')::int,
    'note', case when again
      then 'Sent again for ' || to_char(v_period, 'FMMonth YYYY')
           || '. The earlier send is in the trail; this one replaces the snapshot.'
      else (pack->>'ready') || ' branch(es) sent to ' || array_length(p_to,1) || ' recipient(s).'
      end
      || case when (pack->>'incomplete')::int > 0
              then ' ' || (pack->>'incomplete') || ' held back and named in the letter.'
              else '' end);
end $fn$;

revoke all on function public.matrix_month(uuid, date) from public, anon, authenticated;
revoke all on function public.matrix_send(uuid, uuid, date, text[], text) from public, anon, authenticated;
