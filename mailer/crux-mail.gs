/**
 * Crux mail relay.  —  PASTE ALL OF THIS FILE. It ends with the line
 * // ===== END OF FILE ===== . If you cannot see that line at the bottom of
 * the editor after pasting, the copy was cut short: paste it again.
 *
 * Sends what Crux has queued, from the Google account that deploys this
 * script. No OAuth client, no client secret, no refresh token to expire:
 * Apps Script is already allowed to send as the account it runs as.
 *
 * DEPLOY IT FROM operations.alert@cruxindia.co.in — whichever account deploys
 * it is the address every message comes from. Steps: mailer/README.md.
 */

var SECRET_KEY = 'CRUX_MAIL_SECRET';

// Anyone with the URL can reach this. The secret is what decides.
function authorised_(given) {
  var want = PropertiesService.getScriptProperties().getProperty(SECRET_KEY);
  if (!want) return false;
  var got = String(given || '');
  return got.length === want.length && got === want;
}

function out_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * Who does this relay send as, and how much quota is left?
 * Crux shows the answer on its Mail screen. It comes from Google, so a relay
 * deployed from the wrong account says so instead of quietly sending from
 * the wrong address.
 */
function doGet(e) {
  if (!authorised_(e && e.parameter && e.parameter.secret)) {
    return out_({ error: 'unauthorised' });
  }
  return out_({
    ok: true,
    sendsAs: Session.getEffectiveUser().getEmail(),
    remainingToday: MailApp.getRemainingDailyQuota()
  });
}

/**
 * Send one message. One at a time on purpose: Crux owns the queue, the
 * retries, the daily cap and the key that makes a duplicate impossible, and
 * a second place for those decisions would drift from the first.
 */
function doPost(e) {
  var b;
  try {
    b = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return out_({ error: 'bad_request', reason: 'The body was not JSON.' });
  }
  if (!authorised_(b.secret)) return out_({ error: 'unauthorised' });

  var to = String(b.to || '').trim();
  var subject = String(b.subject || '').trim();
  var text = String(b.text || '').trim();
  if (!to) return out_({ error: 'no_recipient' });
  if (!subject) return out_({ error: 'no_subject' });
  // A message with nothing to read is not a message.
  if (!text) return out_({ error: 'no_body' });

  var options = {};
  if (b.html) options.htmlBody = b.html;
  if (b.fromName) options.name = String(b.fromName);
  if (b.replyTo) options.replyTo = String(b.replyTo);
  if (b.cc) options.cc = String(b.cc);

  try {
    GmailApp.sendEmail(to, subject, text, options);
  } catch (err) {
    return out_({ error: 'send_failed', reason: String((err && err.message) || err) });
  }

  // GmailApp returns no message id, so there is no reference to hand back.
  // Inventing one would look like something that could be looked up.
  return out_({
    ok: true,
    sentAs: Session.getEffectiveUser().getEmail(),
    remainingToday: MailApp.getRemainingDailyQuota()
  });
}

// Run once, by hand. Makes the shared secret and prints it. Copy it into
// Crux and nowhere else. Running it again replaces the old one.
function makeSecret() {
  var s = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '');
  PropertiesService.getScriptProperties().setProperty(SECRET_KEY, s);
  Logger.log('Paste this into Crux, on the Mail screen, as the relay secret:');
  Logger.log(s);
}

// Run once, by hand, before involving Crux. Proves the account can send.
function selfTest() {
  var me = Session.getEffectiveUser().getEmail();
  GmailApp.sendEmail(me, 'Crux mail relay - test',
    'If you are reading this, the relay can send.\n\nIt sends as ' + me +
    '. Remaining today: ' + MailApp.getRemainingDailyQuota() + '.');
  Logger.log('Sent to ' + me + '.');
}

// ===== END OF FILE =====
