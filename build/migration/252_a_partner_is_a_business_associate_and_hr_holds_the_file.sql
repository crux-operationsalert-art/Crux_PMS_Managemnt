-- A partner is a Business Associate, and HR holds the file (252)
--
-- "one major update for Partners, is that we would be calling them and would
--  have a designation of Business Associates and not Branch Manager or
--  Location Head below and above them no change its as per the current
--  structure"
-- "in their profile HR has to confirm if all the agreements are signed and
--  submitted, if not then expected dates and if we have received a security
--  cheque and its details, Rates (Documents rate ITR, Statement, KYC and
--  Other, then OGL Rates, and any other) and the Partnership Ratio (this is
--  only for partners)"
--
-- TWO THINGS, AND THEY ARE DELIBERATELY SEPARATE.
--
-- 1. WHAT THEY ARE CALLED. A partner's designation becomes Business
--    Associate. Nothing else moves: not the chair, not the reporting line,
--    not who they cover. The owner was explicit -- "below and above them no
--    change its as per the current structure" -- and that matters more than
--    it reads, because every visibility rule in this tool is built on
--    person.manager_id and every measure on the chair. Changing a title is a
--    change to a label; changing either of those is a change to who can see
--    whose numbers.
--
--    So this writes designation_id and touches nothing else, and the guard
--    below asserts that the reporting line and the chairs came out the same
--    on the other side.
--
-- 2. WHAT HR HOLDS ABOUT THEM. A partner is a commercial relationship as
--    well as a person, and the paperwork behind it lives nowhere today: the
--    agreements, the security cheque, the rates they are paid at, and the
--    share they are on. HR has been holding all of it outside the tool,
--    which is the same as saying nobody can answer "is this one signed" from
--    their desk.
--
-- WHY THE RATES ARE NOT `rate`. The rate master prices CLIENT work by branch
-- and month, and a report for a past month reads the rate that was valid
-- then. A partner's rate is a different thing with the same word on it: it
-- is what Crux pays this associate per document or per OGL case. Putting it
-- in `rate` would make every MIS figure read a number that is not a client
-- price. It gets its own table, named for what it is.
--
-- WHAT IS ONLY FOR PARTNERS. The partnership ratio, and the functions refuse
-- it for anybody else rather than storing a null nobody can interpret. The
-- rest -- agreements, a security cheque -- is written the same way for
-- anybody HR holds a file on, because an employee can have an undertaking
-- too and a second table for that would be the same table twice.

-- =====================================================================
-- 1. The designation.
-- =====================================================================
insert into designation (title, seniority, is_desk_head)
select 'Business Associate', 45, false
 where not exists (select 1 from designation where lower(btrim(title)) = 'business associate');

do $do$
declare v_d uuid; n int; v_line text; v_chair text;
begin
  select id into v_d from designation where lower(btrim(title)) = 'business associate';

  -- Measured before and after, because "nothing else moved" is a claim and a
  -- claim about somebody's visibility is worth proving.
  select md5(string_agg(p.id::text || '>' || coalesce(p.manager_id::text,'-'), ','
                        order by p.id))
    into v_line from person p where p.employment_status = 'ACTIVE';
  select md5(coalesce(string_agg(h.person_id::text || '>' || h.chair_id::text, ','
                        order by h.person_id, h.chair_id), ''))
    into v_chair from chair_holder h where h.to_date is null;

  update person p
     set designation_id = v_d
   where p.employee_type = 'PARTNER'
     and p.employment_status = 'ACTIVE' and p.superseded_by is null
     and p.designation_id is distinct from v_d;
  get diagnostics n = row_count;

  if n > 0 then
    insert into person_event (person_id, kind, note, at)
    select p.id, 'DETAILS_CHANGED',
           'Designation set to Business Associate (252)', now()
      from person p
     where p.employee_type = 'PARTNER'
       and p.employment_status = 'ACTIVE' and p.superseded_by is null;
  end if;

  if v_line is distinct from
     (select md5(string_agg(p.id::text || '>' || coalesce(p.manager_id::text,'-'), ','
                            order by p.id)) from person p where p.employment_status = 'ACTIVE') then
    raise exception 'Migration 252: the reporting line moved. It must not.';
  end if;
  if v_chair is distinct from
     (select md5(coalesce(string_agg(h.person_id::text || '>' || h.chair_id::text, ','
                            order by h.person_id, h.chair_id), ''))
        from chair_holder h where h.to_date is null) then
    raise exception 'Migration 252: a chair moved. It must not.';
  end if;

  raise notice 'Migration 252: % partner(s) are now Business Associates; the '
               'reporting line and the chairs are unchanged.', n;
end
$do$;

-- =====================================================================
-- 2. The file HR holds.
-- =====================================================================
create table if not exists partner_file (
  person_id        uuid primary key references person(id) on delete cascade,
  -- The one question the owner asked first: is everything signed and in.
  -- Not derived from the agreement rows, because "all of them" is a
  -- judgement about whether the list is complete, and only HR knows that.
  agreements_all   boolean not null default false,
  -- The partnership ratio -- "80-20", where the associate takes 80% of the
  -- revenue and Crux 20%. It is held for understanding and nothing reads it
  -- to price or pay anything, which is why one number is enough: Crux's share
  -- is what is left, worked out where it is read rather than stored twice and
  -- allowed to disagree with itself.
  --
  -- It is a different thing from partner_rate below, which is what Crux pays
  -- per document or per OGL case. Both are "a rate" in conversation and they
  -- are not the same number.
  partner_share_pct numeric,
  ratio_note       text,
  cheque_held      boolean not null default false,
  cheque_no        text,
  cheque_bank      text,
  cheque_amount    numeric,
  cheque_dated_on  date,
  cheque_received_on date,
  cheque_note      text,
  note             text,
  confirmed_by     uuid references person(id),
  confirmed_at     timestamptz,
  updated_by       uuid references person(id),
  updated_at       timestamptz not null default now(),
  constraint partner_file_share_is_a_share check (
    partner_share_pct is null or (partner_share_pct >= 0 and partner_share_pct <= 100)),
  -- A cheque that is held is a cheque somebody can find. A tick with no
  -- number against it is the thing that reads as cover and is not.
  constraint partner_file_cheque_has_details check (
    not cheque_held or (btrim(coalesce(cheque_no,'')) <> ''
                        and btrim(coalesce(cheque_bank,'')) <> ''))
);

create table if not exists partner_agreement (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references person(id) on delete cascade,
  label       text not null,
  state       text not null default 'PENDING',
  signed_on   date,
  expected_on date,
  note        text,
  position    int not null default 0,
  removed_at  timestamptz,
  constraint partner_agreement_said  check (btrim(label) <> ''),
  constraint partner_agreement_state check (state in ('SIGNED','PENDING','WAIVED')),
  -- The owner's own rule: "if not then expected dates". An agreement that is
  -- not signed and carries no date by which it will be is an open item with
  -- nobody holding it.
  constraint partner_agreement_pending_has_a_date check (
    state <> 'PENDING' or expected_on is not null),
  constraint partner_agreement_signed_has_a_date check (
    state <> 'SIGNED' or signed_on is not null)
);
create unique index if not exists partner_agreement_once
  on partner_agreement (person_id, lower(btrim(label)));

create table if not exists partner_rate (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references person(id) on delete cascade,
  -- What family of work this prices. DOC_* are the document rates the owner
  -- listed, OGL is the case rate, OTHER is anything a branch agreed that
  -- nobody has given a name to yet.
  kind        text not null,
  label       text not null,
  amount      numeric,
  unit        text,
  effective_from date,
  note        text,
  position    int not null default 0,
  removed_at  timestamptz,
  constraint partner_rate_said check (btrim(label) <> ''),
  constraint partner_rate_kind check (kind in
    ('DOC_ITR','DOC_STATEMENT','DOC_KYC','DOC_OTHER','OGL','OTHER')),
  constraint partner_rate_not_negative check (amount is null or amount >= 0)
);
create unique index if not exists partner_rate_once
  on partner_rate (person_id, kind, lower(btrim(label)));

alter table partner_file      enable row level security;
alter table partner_agreement enable row level security;
alter table partner_rate      enable row level security;

comment on table partner_file is
  'What HR holds about a Business Associate: whether the agreements are all '
  'signed and in, the security cheque and its details, and the share they are '
  'on. The rates are partner_rate and the agreements partner_agreement.';
comment on table partner_rate is
  'What CRUX PAYS this associate, per document or per OGL case. Not the rate '
  'master: that prices client work by branch and month, and a partner rate in '
  'it would make every MIS figure read a number that is not a client price.';

-- =====================================================================
-- Who may look, and who may write.
--
-- Writing is HR's and the administrator's: it is HR who confirms the file,
-- which is what the owner asked for in those words.
--
-- Reading is wider, because a branch manager asking "what are we paying this
-- associate" is a fair question from inside the line -- but the cheque
-- details and the ratio are not, so they come back only for HR, the
-- administrator and the associate themselves.
-- =====================================================================
create or replace function partner_file_may_set(p_actor uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (select 1 from person a
                  where a.id = p_actor
                    and a.employment_status = 'ACTIVE' and a.superseded_by is null
                    and (a.app_role = 'ADMIN'
                         or coalesce(a.department,'') = 'Human Resources'));
$$;

create or replace function partner_file_get(p_actor uuid, p_person uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  a person; s person; f partner_file;
  v_set boolean; v_close boolean; v_see_money boolean;
begin
  select * into a from person
   where id = p_actor and employment_status = 'ACTIVE' and superseded_by is null;
  if a.id is null then
    return jsonb_build_object('error','not_permitted','reason','Who is asking?');
  end if;
  select * into s from person where id = p_person;
  if s.id is null then return jsonb_build_object('error','no_such_person'); end if;

  v_set   := partner_file_may_set(p_actor);
  v_close := p_actor = p_person or perf_rel(p_actor, p_person) is not null;
  if not (v_set or v_close) then
    return jsonb_build_object('mayUse', false,
      'reason','This is the file HR holds on a Business Associate. It is theirs, '
            || 'the associate''s and their line''s.');
  end if;

  -- The cheque and the share are commercial terms between Crux and this
  -- person. Their manager needs the rates to run the work and has no business
  -- with either.
  v_see_money := v_set or p_actor = p_person;

  select * into f from partner_file where person_id = p_person;

  return jsonb_build_object(
    'mayUse', true,
    'personId', p_person,
    'name', s.full_name,
    'isPartner', coalesce(s.employee_type,'') = 'PARTNER',
    'maySet', v_set,
    'seesTerms', v_see_money,
    'agreementsAll', coalesce(f.agreements_all, false),
    'confirmedBy', (select full_name from person where id = f.confirmed_by),
    'confirmedAt', f.confirmed_at,
    'note', f.note,
    'agreements', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.id, 'label', g.label, 'state', g.state,
               'signedOn', g.signed_on, 'expectedOn', g.expected_on,
               'note', g.note,
               'overdue', g.state = 'PENDING' and g.expected_on < current_date)
             order by g.position, g.label)
        from partner_agreement g
       where g.person_id = p_person and g.removed_at is null), '[]'::jsonb),
    'rates', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', rt.id, 'kind', rt.kind, 'label', rt.label,
               'amount', rt.amount, 'unit', rt.unit,
               'effectiveFrom', rt.effective_from, 'note', rt.note)
             order by rt.kind, rt.position, rt.label)
        from partner_rate rt
       where rt.person_id = p_person and rt.removed_at is null), '[]'::jsonb),
    'cheque', case when v_see_money then jsonb_build_object(
        'held', coalesce(f.cheque_held, false),
        'no', f.cheque_no, 'bank', f.cheque_bank, 'amount', f.cheque_amount,
        'datedOn', f.cheque_dated_on, 'receivedOn', f.cheque_received_on,
        'note', f.cheque_note) else null end,
    'ratio', case when v_see_money and coalesce(s.employee_type,'') = 'PARTNER'
      then jsonb_build_object(
        'partnerPct', f.partner_share_pct,
        'cruxPct', case when f.partner_share_pct is null then null
                        else 100 - f.partner_share_pct end,
        'note', f.ratio_note) else null end,
    -- What is still open, said once so three screens do not each work it out.
    'openCount', (select count(*) from partner_agreement g
                   where g.person_id = p_person and g.removed_at is null
                     and g.state = 'PENDING'),
    'overdueCount', (select count(*) from partner_agreement g
                      where g.person_id = p_person and g.removed_at is null
                        and g.state = 'PENDING' and g.expected_on < current_date),
    'rateKinds', jsonb_build_array(
       jsonb_build_array('DOC_ITR','Documents — ITR'),
       jsonb_build_array('DOC_STATEMENT','Documents — Statement'),
       jsonb_build_array('DOC_KYC','Documents — KYC'),
       jsonb_build_array('DOC_OTHER','Documents — Other'),
       jsonb_build_array('OGL','OGL'),
       jsonb_build_array('OTHER','Anything else')));
end
$function$;

comment on function partner_file_get(uuid, uuid) is
  'The file HR holds on a Business Associate. HR, the administrator, the '
  'associate and their line may read it; the cheque details and the share are '
  'commercial terms and come back only for HR, the administrator and the '
  'associate themselves.';

-- =====================================================================
-- Writing it.
--
-- The whole file in one call, validated whole and written whole, for the
-- reason perf_split_set and plb_kpi_part_set are written that way: the
-- invariant is about the SET -- is everything signed, does the list cover
-- what it should -- and a set is checked once when it is complete.
-- =====================================================================
create or replace function partner_file_set(p_actor uuid, p_person uuid, p_in jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  s person; x jsonb; i int := 0;
  v_bad jsonb := '[]'::jsonb;
  v_all boolean; v_held boolean; v_share numeric;
  v_state text; v_kind text; v_signed date; v_expected date;
  n_open int;
begin
  if not partner_file_may_set(p_actor) then
    return jsonb_build_object('error','not_permitted',
      'reason','Confirming a Business Associate''s file is Human Resources'' '
            || 'and the administrator''s.');
  end if;
  select * into s from person
   where id = p_person and employment_status = 'ACTIVE' and superseded_by is null;
  if s.id is null then return jsonb_build_object('error','no_such_person'); end if;
  if p_in is null or jsonb_typeof(p_in) <> 'object' then
    return jsonb_build_object('error','nothing_to_set',
      'reason','Send the file. This call carried '
            || coalesce(jsonb_typeof(p_in),'nothing') || '.');
  end if;

  -- ------------------------------------------------------------- validate
  v_all  := coalesce((p_in->>'agreementsAll')::boolean, false);
  v_held := coalesce((p_in#>>'{cheque,held}')::boolean, false);

  if v_held and (btrim(coalesce(p_in#>>'{cheque,no}','')) = ''
                 or btrim(coalesce(p_in#>>'{cheque,bank}','')) = '') then
    v_bad := v_bad || jsonb_build_object('field','cheque',
      'reason','A cheque that is held is a cheque somebody can find. Give the '
            || 'number and the bank.');
  end if;

  if p_in ? 'ratio' and jsonb_typeof(p_in->'ratio') = 'object'
     and (p_in#>>'{ratio,partnerPct}') is not null
     and btrim(p_in#>>'{ratio,partnerPct}') <> '' then
    if coalesce(s.employee_type,'') <> 'PARTNER' then
      v_bad := v_bad || jsonb_build_object('field','ratio',
        'reason','A partnership ratio is only for a partner. ' || s.full_name ||
                 ' is on the books as ' ||
                 lower(coalesce(s.employee_type,'an employee')) || '.');
    else
      begin
        v_share := (p_in#>>'{ratio,partnerPct}')::numeric;
      exception when others then
        v_share := null;
        v_bad := v_bad || jsonb_build_object('field','ratio',
          'reason','A share is a number out of a hundred.');
      end;
      if v_share is not null and (v_share < 0 or v_share > 100) then
        v_bad := v_bad || jsonb_build_object('field','ratio',
          'reason','A share is between nought and a hundred. Crux takes what '
                || 'is left, so there is only one number to type.');
      end if;
    end if;
  end if;

  if jsonb_typeof(coalesce(p_in->'agreements','[]'::jsonb)) <> 'array' then
    v_bad := v_bad || jsonb_build_object('field','agreements',
      'reason','Send the agreements as a list.');
  else
    for x in select jsonb_array_elements(coalesce(p_in->'agreements','[]'::jsonb)) loop
      i := i + 1;
      if btrim(coalesce(x->>'label','')) = '' then
        v_bad := v_bad || jsonb_build_object('field','agreements',
          'reason','Agreement ' || i || ' has no name.');
      end if;
      v_state := upper(coalesce(nullif(btrim(coalesce(x->>'state','')),''),'PENDING'));
      if v_state not in ('SIGNED','PENDING','WAIVED') then
        v_bad := v_bad || jsonb_build_object('field','agreements',
          'reason','Agreement ' || i || ': signed, pending or waived.');
      end if;
      if v_state = 'PENDING'
         and nullif(btrim(coalesce(x->>'expectedOn','')),'') is null then
        v_bad := v_bad || jsonb_build_object('field','agreements',
          'reason','Agreement ' || i || ' is not signed, so say when it is '
                || 'expected. An open item with no date is an open item '
                || 'nobody is holding.');
      end if;
      if v_state = 'SIGNED'
         and nullif(btrim(coalesce(x->>'signedOn','')),'') is null then
        v_bad := v_bad || jsonb_build_object('field','agreements',
          'reason','Agreement ' || i || ' is signed, so say when.');
      end if;
    end loop;
  end if;

  i := 0;
  if jsonb_typeof(coalesce(p_in->'rates','[]'::jsonb)) <> 'array' then
    v_bad := v_bad || jsonb_build_object('field','rates',
      'reason','Send the rates as a list.');
  else
    for x in select jsonb_array_elements(coalesce(p_in->'rates','[]'::jsonb)) loop
      i := i + 1;
      v_kind := upper(coalesce(nullif(btrim(coalesce(x->>'kind','')),''),'OTHER'));
      if v_kind not in ('DOC_ITR','DOC_STATEMENT','DOC_KYC','DOC_OTHER','OGL','OTHER') then
        v_bad := v_bad || jsonb_build_object('field','rates',
          'reason','Rate ' || i || ': ITR, Statement, KYC, Other document, OGL '
                || 'or anything else.');
      end if;
      if btrim(coalesce(x->>'label','')) = '' then
        v_bad := v_bad || jsonb_build_object('field','rates',
          'reason','Rate ' || i || ' has no name. "250" against nothing is not '
                || 'a rate.');
      end if;
      if nullif(btrim(coalesce(x->>'amount','')),'') is not null
         and (x->>'amount')::numeric < 0 then
        v_bad := v_bad || jsonb_build_object('field','rates',
          'reason','Rate ' || i || ' is negative.');
      end if;
    end loop;
  end if;

  if jsonb_array_length(v_bad) > 0 then
    return jsonb_build_object('error','invalid', 'fields', v_bad,
      'reason','Nothing was saved. Put these right and send it again.');
  end if;

  -- ---------------------------------------------------------------- write
  insert into partner_file (person_id, agreements_all, partner_share_pct,
      ratio_note, cheque_held, cheque_no, cheque_bank, cheque_amount,
      cheque_dated_on, cheque_received_on, cheque_note, note,
      confirmed_by, confirmed_at, updated_by, updated_at)
  values (p_person, v_all, v_share,
          nullif(btrim(coalesce(p_in#>>'{ratio,note}','')),''),
          v_held,
          nullif(btrim(coalesce(p_in#>>'{cheque,no}','')),''),
          nullif(btrim(coalesce(p_in#>>'{cheque,bank}','')),''),
          nullif(btrim(coalesce(p_in#>>'{cheque,amount}','')),'')::numeric,
          nullif(btrim(coalesce(p_in#>>'{cheque,datedOn}','')),'')::date,
          nullif(btrim(coalesce(p_in#>>'{cheque,receivedOn}','')),'')::date,
          nullif(btrim(coalesce(p_in#>>'{cheque,note}','')),''),
          nullif(btrim(coalesce(p_in->>'note','')),''),
          case when v_all then p_actor else null end,
          case when v_all then now() else null end,
          p_actor, now())
  on conflict (person_id) do update
     set agreements_all = excluded.agreements_all,
         partner_share_pct = excluded.partner_share_pct,
         ratio_note = excluded.ratio_note,
         cheque_held = excluded.cheque_held,
         cheque_no = excluded.cheque_no,
         cheque_bank = excluded.cheque_bank,
         cheque_amount = excluded.cheque_amount,
         cheque_dated_on = excluded.cheque_dated_on,
         cheque_received_on = excluded.cheque_received_on,
         cheque_note = excluded.cheque_note,
         note = excluded.note,
         -- Who confirmed it, and when, survives a later edit that leaves the
         -- confirmation standing. A tick that silently re-dates itself every
         -- time somebody saves a note is not a confirmation of anything.
         confirmed_by = case when excluded.agreements_all
                             then coalesce(partner_file.confirmed_by, excluded.confirmed_by)
                             else null end,
         confirmed_at = case when excluded.agreements_all
                             then coalesce(partner_file.confirmed_at, excluded.confirmed_at)
                             else null end,
         updated_by = excluded.updated_by,
         updated_at = now();

  -- A list that is SENT is replaced whole; a list that is not sent is left
  -- alone. The difference matters: ticking "all signed" on a form that
  -- carries no rates must not withdraw the rates, and "replace whole" read
  -- as "replace everything every time" is how a save of one field empties
  -- three others.
  --
  -- What a replacement replaces is withdrawn rather than erased: "the rate
  -- used to be 250" is a question somebody asks three months later, about an
  -- invoice that was raised at it.
  if p_in ? 'agreements' then
    update partner_agreement set removed_at = now()
     where person_id = p_person and removed_at is null;
  end if;
  if p_in ? 'rates' then
    update partner_rate set removed_at = now()
     where person_id = p_person and removed_at is null;
  end if;

  i := 0;
  for x in select jsonb_array_elements(coalesce(p_in->'agreements','[]'::jsonb)) loop
    i := i + 1;
    v_state := upper(coalesce(nullif(btrim(coalesce(x->>'state','')),''),'PENDING'));
    v_signed := nullif(btrim(coalesce(x->>'signedOn','')),'')::date;
    v_expected := nullif(btrim(coalesce(x->>'expectedOn','')),'')::date;
    insert into partner_agreement (person_id, label, state, signed_on, expected_on,
                                   note, position)
    values (p_person, btrim(x->>'label'), v_state, v_signed, v_expected,
            nullif(btrim(coalesce(x->>'note','')),''), i)
    on conflict (person_id, lower(btrim(label))) do update
       set state = excluded.state, signed_on = excluded.signed_on,
           expected_on = excluded.expected_on, note = excluded.note,
           position = excluded.position, removed_at = null;
  end loop;

  i := 0;
  for x in select jsonb_array_elements(coalesce(p_in->'rates','[]'::jsonb)) loop
    i := i + 1;
    v_kind := upper(coalesce(nullif(btrim(coalesce(x->>'kind','')),''),'OTHER'));
    insert into partner_rate (person_id, kind, label, amount, unit,
                              effective_from, note, position)
    values (p_person, v_kind, btrim(x->>'label'),
            nullif(btrim(coalesce(x->>'amount','')),'')::numeric,
            nullif(btrim(coalesce(x->>'unit','')),''),
            nullif(btrim(coalesce(x->>'effectiveFrom','')),'')::date,
            nullif(btrim(coalesce(x->>'note','')),''), i)
    on conflict (person_id, kind, lower(btrim(label))) do update
       set amount = excluded.amount, unit = excluded.unit,
           effective_from = excluded.effective_from, note = excluded.note,
           position = excluded.position, removed_at = null;
  end loop;

  select count(*) into n_open from partner_agreement
   where person_id = p_person and removed_at is null and state = 'PENDING';

  insert into audit_entry (actor_id, action, entity_type, entity_ref,
                           old_value, new_value)
  values (p_actor, 'PARTNER_FILE_SET', 'person', p_person::text, null, p_in);

  return jsonb_build_object('ok', true, 'personId', p_person,
    'agreementsAll', v_all, 'open', n_open,
    -- The tick and the list can disagree, and saying so is the whole value of
    -- holding both: HR ticking "all signed" while three are pending is
    -- either a mistake or a list that is out of date, and either way
    -- somebody should look.
    'note', case
      when v_all and n_open > 0 then
        'Saved. You have marked everything signed and ' || n_open ||
        ' agreement(s) are still pending on the list below. One of the two '
        'is out of date.'
      when v_all then 'Saved, and confirmed as all signed and in.'
      when n_open > 0 then 'Saved. ' || n_open || ' agreement(s) still to come.'
      else 'Saved.' end);
end
$function$;

comment on function partner_file_set(uuid, uuid, jsonb) is
  'Write a Business Associate''s whole file in one call -- agreements, '
  'security cheque, rates and the partnership ratio. Human Resources'' and '
  'the administrator''s. Validates everything before writing anything, and '
  'says when the "all signed" tick and the list disagree.';

-- ------------------------------------------------------------- the guard
do $guard$
declare
  v_hr uuid; v_p uuid; v_other uuid; o jsonb; n int;
begin
  select id into v_hr from person
   where employment_status='ACTIVE' and superseded_by is null
     and (app_role='ADMIN' or coalesce(department,'')='Human Resources')
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  if v_hr is null then
    raise notice 'Migration 252: nobody in HR to check against.';
    return;
  end if;

  select id into v_other from person
   where employment_status='ACTIVE' and superseded_by is null
     and app_role is distinct from 'ADMIN'
     and coalesce(department,'') <> 'Human Resources'
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  if v_other is not null then
    if partner_file_set(v_other, v_hr, '{}'::jsonb)->>'error'
       is distinct from 'not_permitted' then
      raise exception 'Migration 252: somebody outside HR wrote a partner file.';
    end if;
  end if;

  -- Every partner now carries the designation, and nobody else gained it.
  select count(*) into n from person p
    join designation d on d.id = p.designation_id
   where p.employee_type <> 'PARTNER' and p.employment_status='ACTIVE'
     and p.superseded_by is null
     and lower(btrim(d.title)) = 'business associate';
  if n > 0 then
    raise exception 'Migration 252: % non-partner(s) were made Business '
                    'Associates.', n;
  end if;

  -- A ratio is only for a partner.
  select id into v_p from person
   where employment_status='ACTIVE' and superseded_by is null
     and employee_type <> 'PARTNER'
     and coalesce(employee_type,'EMPLOYEE') not in ('CLIENT_CONTACT','SERVICE_ACCOUNT')
   limit 1;
  if v_p is not null then
    o := partner_file_set(v_hr, v_p, jsonb_build_object(
           'ratio', jsonb_build_object('partnerPct', 40)));
    if o->>'error' is distinct from 'invalid' then
      raise exception 'Migration 252: a partnership ratio was set on somebody '
                      'who is not a partner: %', o;
    end if;
  end if;

  raise notice 'partner_file: HR holds the agreements, the cheque, the rates '
               'and the ratio.';
end $guard$;
