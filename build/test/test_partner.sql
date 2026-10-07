-- A Business Associate's file (migration 252)
--
-- "we would be calling them ... Business Associates and not Branch Manager or
--  Location Head below and above them no change its as per the current
--  structure"
-- "HR has to confirm if all the agreements are signed and submitted, if not
--  then expected dates and if we have received a security cheque and its
--  details, Rates ... and the Partnership Ratio (this is only for partners)"
--
-- Each assertion is one of those sentences:
--
--   the title changes, and nothing else does
--   HR writes it, and nobody else
--   not signed -> say when it is expected
--   a cheque that is held is a cheque somebody can find
--   a ratio is only for a partner
--   the rates are per document and per OGL case, named
--   the manager sees the rates and not the terms
--   a tick that disagrees with the list says so
--
-- Everything is rolled back.

begin;

do $t$
declare
  p_hr uuid; p_boss uuid; p_par uuid; p_emp uuid; p_other uuid;
  v_d uuid; o jsonb; n int; v_line text;
begin
  insert into person (full_name, work_email, app_role, department)
    values ('BA HR','ba.hr@example.invalid','MANAGER','Human Resources') returning id into p_hr;
  insert into person (full_name, work_email, app_role)
    values ('BA Boss','ba.boss@example.invalid','MANAGER') returning id into p_boss;
  insert into person (full_name, work_email, app_role, manager_id, employee_type)
    values ('BA Partner','ba.p@example.invalid','VIEWER', p_boss, 'PARTNER')
    returning id into p_par;
  insert into person (full_name, work_email, app_role, manager_id)
    values ('BA Employee','ba.e@example.invalid','VIEWER', p_boss) returning id into p_emp;
  insert into person (full_name, work_email, app_role)
    values ('BA Other','ba.o@example.invalid','VIEWER') returning id into p_other;

  -- --------------------------------------------- the title, and only the title
  select id into v_d from designation where lower(btrim(title)) = 'business associate';
  if v_d is null then
    raise exception 'FAIL  there is no Business Associate designation';
  end if;
  select md5(coalesce(manager_id::text,'-')) into v_line from person where id = p_par;
  update person set designation_id = v_d where id = p_par;
  if md5(coalesce((select manager_id::text from person where id = p_par),'-'))
     is distinct from v_line then
    raise exception 'FAIL  naming them a Business Associate moved their '
                    'reporting line. Every visibility rule in the tool is '
                    'built on that line.';
  end if;
  raise notice 'PASS  a partner is a Business Associate, and nothing above or '
               'below them moved';

  -- ----------------------------------------------------------- who may write
  if partner_file_set(p_other, p_par, '{}'::jsonb)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  somebody outside HR wrote a partner file';
  end if;
  if partner_file_set(p_boss, p_par, '{}'::jsonb)->>'error'
     is distinct from 'not_permitted' then
    raise exception 'FAIL  their own manager wrote the file HR confirms';
  end if;
  raise notice 'PASS  confirming the file is Human Resources'' and the '
               'administrator''s';

  -- ------------------------------------------------- an open item has a date
  if partner_file_set(p_hr, p_par, jsonb_build_object(
       'agreements', jsonb_build_array(
         jsonb_build_object('label','Franchise agreement','state','PENDING'))))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  an unsigned agreement was accepted with no date by '
                    'which it is expected';
  end if;
  if partner_file_set(p_hr, p_par, jsonb_build_object(
       'agreements', jsonb_build_array(
         jsonb_build_object('label','Franchise agreement','state','SIGNED'))))
     ->>'error' is distinct from 'invalid' then
    raise exception 'FAIL  a signed agreement was accepted with no date';
  end if;
  raise notice 'PASS  not signed means say when, and signed means say when it was';

  -- ---------------------------------------------------------- the cheque
  if partner_file_set(p_hr, p_par, jsonb_build_object(
       'cheque', jsonb_build_object('held', true)))->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  a security cheque was ticked as held with no number '
                    'and no bank. A tick with nothing behind it reads as cover '
                    'and is not.';
  end if;
  raise notice 'PASS  a cheque that is held is a cheque somebody can find';

  -- ------------------------------------------------- the ratio, partners only
  if partner_file_set(p_hr, p_emp, jsonb_build_object(
       'ratio', jsonb_build_object('partnerPct', 40)))->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  a partnership ratio was set on an employee';
  end if;
  if partner_file_set(p_hr, p_par, jsonb_build_object(
       'ratio', jsonb_build_object('partnerPct', 140)))->>'error'
     is distinct from 'invalid' then
    raise exception 'FAIL  a share of a hundred and forty per cent was accepted';
  end if;
  raise notice 'PASS  a partnership ratio is only for a partner, and is a share';

  -- --------------------------------------------------- the whole file saves
  o := partner_file_set(p_hr, p_par, jsonb_build_object(
    'agreementsAll', false,
    'agreements', jsonb_build_array(
      jsonb_build_object('label','Franchise agreement','state','SIGNED',
                         'signedOn', current_date - 30),
      jsonb_build_object('label','Non-disclosure','state','PENDING',
                         'expectedOn', current_date + 7)),
    'cheque', jsonb_build_object('held', true, 'no','000123',
                                 'bank','State Bank of India',
                                 'amount', 100000, 'receivedOn', current_date - 10),
    'ratio', jsonb_build_object('partnerPct', 60),
    'rates', jsonb_build_array(
      jsonb_build_object('kind','DOC_ITR','label','ITR','amount',120,'unit','per document'),
      jsonb_build_object('kind','DOC_STATEMENT','label','Statement','amount',90,'unit','per document'),
      jsonb_build_object('kind','DOC_KYC','label','KYC','amount',60,'unit','per document'),
      jsonb_build_object('kind','OGL','label','OGL case','amount',350,'unit','per case'))));
  if o->>'error' is not null then
    raise exception 'FAIL  the whole file would not save: %', o;
  end if;
  if (o->>'open')::int <> 1 then
    raise exception 'FAIL  the reply does not count what is still to come';
  end if;
  raise notice 'PASS  the agreements, the cheque, the rates and the ratio save '
               'together';

  -- The lists are withdrawn, not erased: "the rate used to be 250" is a
  -- question somebody asks three months later, about an invoice.
  o := partner_file_set(p_hr, p_par, jsonb_build_object(
    'rates', jsonb_build_array(
      jsonb_build_object('kind','OGL','label','OGL case','amount',400,'unit','per case'))));
  select count(*) into n from partner_rate where person_id = p_par and removed_at is null;
  if n <> 1 then
    raise exception 'FAIL  % rates are live after replacing the list with one', n;
  end if;
  select count(*) into n from partner_rate where person_id = p_par;
  if n < 4 then
    raise exception 'FAIL  the rates that were replaced were erased. An invoice '
                    'raised last month was raised at one of them.';
  end if;
  raise notice 'PASS  a replaced rate is withdrawn, never erased';

  -- A list that is NOT sent is left alone. "Replace whole" read as "replace
  -- everything every time" means ticking a box on a form that carries no
  -- rates withdraws the rates.
  o := partner_file_set(p_hr, p_par, jsonb_build_object('note','just a note'));
  select count(*) into n from partner_rate where person_id = p_par and removed_at is null;
  if n <> 1 then
    raise exception 'FAIL  saving a note withdrew the rates. A list that was '
                    'not sent was not being changed.';
  end if;
  raise notice 'PASS  a list that is sent is replaced; a list that is not is '
               'left alone';

  -- -------------------------------------------------- the tick and the list
  o := partner_file_set(p_hr, p_par, jsonb_build_object(
    'agreementsAll', true,
    'agreements', jsonb_build_array(
      jsonb_build_object('label','Non-disclosure','state','PENDING',
                         'expectedOn', current_date + 7))));
  if o->>'note' not like '%out of date%' then
    raise exception 'FAIL  "all signed" was ticked with an agreement still '
                    'pending and nothing said so: %', o;
  end if;
  raise notice 'PASS  and a tick that disagrees with the list says so';

  -- ------------------------------------------------------------- who reads it
  o := partner_file_get(p_boss, p_par);
  if not coalesce((o->>'mayUse')::boolean,false) then
    raise exception 'FAIL  their own manager cannot read the file';
  end if;
  if jsonb_array_length(o->'rates') = 0 then
    raise exception 'FAIL  their manager cannot see what we pay them, which is '
                    'what they need to run the work';
  end if;
  if o->'cheque' <> 'null'::jsonb or o->'ratio' <> 'null'::jsonb then
    raise exception 'FAIL  their manager was shown the security cheque or the '
                    'share. Those are terms between Crux and the associate.';
  end if;
  o := partner_file_get(p_par, p_par);
  if o->'ratio' = 'null'::jsonb then
    raise exception 'FAIL  the associate cannot see their own share';
  end if;
  if coalesce((o->>'maySet')::boolean,false) then
    raise exception 'FAIL  the associate can confirm their own file';
  end if;
  if coalesce((partner_file_get(p_other, p_par)->>'mayUse')::boolean,false) then
    raise exception 'FAIL  somebody outside the line read the file';
  end if;
  raise notice 'PASS  the line sees the rates, the associate and HR see the terms';

  raise notice '--- the Business Associate file: every assertion passed ---';
end $t$;

rollback;
