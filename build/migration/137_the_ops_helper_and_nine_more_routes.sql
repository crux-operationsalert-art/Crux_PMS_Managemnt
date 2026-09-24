-- The remaining nine screens are served by a second Edge Function, `ops`,
-- because one Edge Function deploys in one call and `api` had outgrown what
-- that call carries -- the deploy came back as truncated JSON at about 127KB.
-- Same session token, same scope rules, same shim, so the page needs one more
-- base URL and nothing else changes.
do $$
declare v_body text; v_new text;
begin
  select html into v_body from app_page where slug = 'app';
  if v_body is null then raise exception 'no app page'; end if;
  if position('var crux = function(p,o){ return call(CRUX, p, o); };' in v_body) = 0 then
    raise exception 'the helper anchor is not there';
  end if;

  v_new := replace(v_body,
    'var crux = function(p,o){ return call(CRUX, p, o); };',
    'var OPS  = "https://oxpwqfbtbxlvuqpztbwg.supabase.co/functions/v1/ops";' || E'\n' ||
    'var ops  = function(p,o){ return call(OPS,  p, o); };' || E'\n' ||
    'var crux = function(p,o){ return call(CRUX, p, o); };');

  v_new := replace(v_new, '["clients","Clients"] ] }',
    '["clients","Clients"], ["visits","Visits & claims"] ] }');
  v_new := replace(v_new, '["history","History"] ] }',
    '["history","History"], ["hr","HR"], ["joining","Joining"], ["access","Report access"], ["ideas","Ideathon"] ] }');
  v_new := replace(v_new, '{ label:"Keep",       items:[ ["coverage","Coverage"],',
    '{ label:"Numbers",    items:[ ["mis","MIS"], ["tenday","10-day view"], ["reports","Reports"], ["rates","Rate master"] ] },' || E'\n' ||
    '  { label:"Keep",       items:[ ["coverage","Coverage"],');
  v_new := replace(v_new, 'clients:vClients, history:vHistory,',
    'clients:vClients, history:vHistory, visits:vVisits, ideas:vIdeas, hr:vHR, joining:vJoining, access:vAccess, mis:vMis, tenday:vTenday, reports:vReports, rates:vRates,');

  if position('var ops  = function' in v_new) = 0 then raise exception 'ops helper not added'; end if;
  if position('["visits","Visits & claims"]' in v_new) = 0 then raise exception 'visits nav missing'; end if;
  if position('["mis","MIS"]' in v_new) = 0 then raise exception 'numbers group missing'; end if;
  if position('reports:vReports' in v_new) = 0 then raise exception 'routes missing'; end if;

  update app_page set html = v_new, updated_at = now() where slug = 'app';
end $$;
