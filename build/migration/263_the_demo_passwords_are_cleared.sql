-- The fourteen demo passwords are cleared
--
-- Minted on 30 September so the owner could present, one per chair from a
-- field executive to the Managing Director, and written in plain text into
-- the demo-logins page with the instruction "Clear them when the demo is
-- over". The demo was that day. Two weeks on they were still live: real
-- staff addresses, guessable passwords, on the production tool.
--
-- Only those fourteen addresses, by name -- not "every password_hash that
-- is set", which is what the demo page's own one-liner said and which would
-- also take any password set since for a real reason. Google sign-in is
-- untouched and keeps working for all fourteen; an administrator who needs
-- to see the tool as one of them uses Act as (D12), which needs no password.
update person set password_hash = null, password_salt = null
 where lower(work_email) in (
   'vicky.salvi@cruxindia.co.in', 'aniket.chalke@cruxindia.co.in',
   'shantanu.suravase@cruxindia.co.in', 'manish.s@cruxindia.co.in',
   'virendra.pal@cruxindia.co.in', 'arun.bodupali@cruxindia.co.in',
   'valsan.p@cruxindia.co.in', 'sneha.radhe@cruxindia.co.in',
   'anuja.adhali@cruxindia.co.in', 'nitish.bhope@cruxindia.co.in',
   'avinash.chaskar@cruxindia.co.in', 'maruf.shaikh@cruxindia.co.in',
   'mahesh.more@cruxindia.co.in', 'bo.reports@cruxindia.co.in')
   and password_hash is not null;

do $guard$
begin
  if exists (select 1 from person where password_hash is not null and lower(work_email) in (
       'vicky.salvi@cruxindia.co.in', 'aniket.chalke@cruxindia.co.in',
       'shantanu.suravase@cruxindia.co.in', 'manish.s@cruxindia.co.in',
       'virendra.pal@cruxindia.co.in', 'arun.bodupali@cruxindia.co.in',
       'valsan.p@cruxindia.co.in', 'sneha.radhe@cruxindia.co.in',
       'anuja.adhali@cruxindia.co.in', 'nitish.bhope@cruxindia.co.in',
       'avinash.chaskar@cruxindia.co.in', 'maruf.shaikh@cruxindia.co.in',
       'mahesh.more@cruxindia.co.in', 'bo.reports@cruxindia.co.in')) then
    raise exception 'Migration 263: a demo password is still set.';
  end if;
  raise notice 'Migration 263: the demo passwords are gone; % password(s) remain set.',
    (select count(*) from person where password_hash is not null);
end $guard$;
