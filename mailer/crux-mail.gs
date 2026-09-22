/**
 * Crux — the mail relay.
 *
 * Sends what Crux has queued, from the Google account that deploys this
 * script. There is no OAuth client to register, no client secret and no
 * refresh token that expires: Apps Script is already authorised to send as
 * the account it runs as, which is the whole reason this route works where
 * the Gmail API route kept failing.
 *
 * This is the same mechanism as the internship programme's mailer, which has
 * been sending for months. The one difference is that this script holds no
 * data and no templates. It sends what it is handed and nothing else.
 *
 * DEPLOY IT FROM operations.alert@cruxindia.co.in. Whichever account deploys
 * it is the address every message comes from.
 *
 * Setup is in mailer/README.md — four steps, about five minutes.
 */

// The shared secret lives in Script Properties, not here, so this file can be
// read by anyone without handing them the ability to send as the company.
var SECRET_KEY = 'CRUX_MAIL_SECRET';

/** Anyone with the URL can reach this. The secret is what decides. */
function authorised_(body) {
  var want = PropertiesService.getScriptProperties().getProperty(SECRET_KEY);
  if (!want) return false;
  var got = String((body && body.secret) || '');
  // Length first, then contents. This is a public URL.
  return got.length === want.length && got === want;
}

function out_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Is the link alive, and who does it send as?
 *
 * Crux calls this from the Mail screen so an administrator sees the real
 * sending address rather than the one they typed, and the real remaining
 * quota rather than a guess. Getting these from Google is the point: a
 * setting that says operations.alert@ while the script runs as somebody
 * else is exactly the kind of quiet wrongness this replaces.
 */
function doGet(e) {
  var body = { secret: (e && e.parameter && e.parameter.secret) || '' };
  if (!authorised_(body)) return out_({ error: 'unauthorised' });
  return out_({
    ok: true,
    sendsAs: Session.getEffectiveUser().getEmail(),
    aliases: GmailApp.getAliases(),
    remainingToday: MailApp.getRemainingDailyQuota(),
    timeZone: Session.getScriptTimeZone()
  });
}

/**
 * Send one message.
 *
 * One at a time on purpose. Crux already owns the queue, the retries, the
 * daily cap and the idempotency key; a batch endpoint here would be a second
 * place where those decisions live, and they would drift.
 */
function doPost(e) {
  var body;
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return out_({ error: 'bad_request', reason: 'The body was not JSON.' });
  }
  if (!authorised_(body)) return out_({ error: 'unauthorised' });

  var to = String(body.to || '').trim();
  var subject = String(body.subject || '').trim();
  var text = String(body.text || '').trim();
  if (!to) return out_({ error: 'no_recipient' });
  if (!subject) return out_({ error: 'no_subject' });
  // A message with nothing to read is not a message. Crux refuses one at the
  // queue; refusing it here as well means a direct call cannot bypass that.
  if (!text) return out_({ error: 'no_body',
    reason: 'A message must carry the text a person will read.' });

  var options = { htmlBody: body.html || undefined };
  if (body.fromName) options.name = String(body.fromName);
  if (body.replyTo) options.replyTo = String(body.replyTo);
  if (body.cc) options.cc = String(body.cc);
  if (body.bcc) options.bcc = String(body.bcc);

  // An alias may be used only if Gmail actually holds it. Asking to send as
  // an address the account does not own fails inside Google with a message
  // nobody reads; this fails here, saying which addresses are available.
  if (body.from) {
    var aliases = GmailApp.getAliases();
    var self = Session.getEffectiveUser().getEmail();
    if (body.from !== self && aliases.indexOf(body.from) === -1) {
      return out_({ error: 'not_an_alias',
        reason: 'This account cannot send as ' + body.from + '.',
        sendsAs: self, aliases: aliases });
    }
    if (body.from !== self) options.from = body.from;
  }

  try {
    GmailApp.sendEmail(to, subject, text, options);
  } catch (err) {
    return out_({ error: 'send_failed', reason: String(err && err.message || err) });
  }

  // GmailApp returns no message id, so there is no provider reference to give
  // back and inventing one would be worse than none. The copy in Sent is the
  // record on this side; Crux keeps its own row on the other.
  return out_({
    ok: true,
    sentAs: Session.getEffectiveUser().getEmail(),
    remainingToday: MailApp.getRemainingDailyQuota()
  });
}

/**
 * Run this once, by hand, from the editor. It makes the shared secret and
 * prints it. Copy it into Crux and never anywhere else.
 */
function makeSecret() {
  var s = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '');
  PropertiesService.getScriptProperties().setProperty(SECRET_KEY, s);
  Logger.log('Paste this into Crux, on the Mail screen, as the relay secret:');
  Logger.log(s);
  return s;
}

/**
 * Run this once, by hand, after deploying, to prove the whole path works
 * before Crux is pointed at it. It sends one message to the account itself.
 */
function selfTest() {
  var me = Session.getEffectiveUser().getEmail();
  GmailApp.sendEmail(me, 'Crux mail relay — test',
    'If you are reading this, the relay can send.\n\n' +
    'It sends as ' + me + '. Remaining today: ' +
    MailApp.getRemainingDailyQuota() + '.');
  Logger.log('Sent to ' + me + '. Remaining today: ' + MailApp.getRemainingDailyQuota());
}
