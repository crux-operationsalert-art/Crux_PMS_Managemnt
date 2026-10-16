/* ================================================ MAIL-SWITCHES (270)
   The two mail switches, at the top of Messaging, E-mail.

   "Add that pause and unpause button for admin ... And same but different
   button for normal internal mails too, as tool is not 100% live" -- the
   owner, 16 Oct.

   Two switches, not one, because they stop different things: the client
   escalation matrix is a letter to a bank, and internal mail is everything
   the tool writes to staff. Pausing one must never quietly pause or release
   the other.

   Nothing is decided here. The database holds the messages back
   (mail_held, read by outbox_claim and both WhatsApp claims) and refuses
   the matrix (matrix_send); this card only shows each switch, says what it
   is holding, and asks before releasing it -- because unpausing internal
   mail sends whatever has been waiting, and the card must say how much
   before it is pressed, not after.                                        */
var MP_KINDS = [
  { kind: "internal", title: "Internal mail",
    what: "Everything the tool writes to staff: welcome letters, daily-count " +
          "reminders, overdue notices and escalations. While paused, each message " +
          "waits in the queue, intact, and its WhatsApp copy waits with it. A test " +
          "you send yourself from this screen still goes." },
  { kind: "client", title: "Client escalation matrix",
    what: "The monthly letter to client branches saying who to call at which " +
          "level. While paused, nobody can send it and nothing reaches a client." }
];

/* "12 e-mails and 721 WhatsApp copies", or "" when nothing is waiting. */
function mpHeld(s){
  s = s || {};
  var parts = [];
  if (s.heldMail) parts.push(s.heldMail + " e-mail" + (s.heldMail === 1 ? "" : "s"));
  if (s.heldWhatsapp) parts.push(s.heldWhatsapp + " WhatsApp cop" +
                                 (s.heldWhatsapp === 1 ? "y" : "ies"));
  return parts.join(" and ");
}

/* A switch the server did not describe is drawn as paused: the database
   reads a missing switch as paused, and the screen must not say otherwise. */
function mpIsPaused(s){ return !s || s.paused !== false; }

function mpCard(m){
  var p = m && m.pause;
  if (!p) return "";
  return '<div class="mpwrap">' + MP_KINDS.map(function(k){
    var s = p[k.kind] || {}, paused = mpIsPaused(s), held = mpHeld(s);
    return '<div class="card mpcard ' + (paused ? 'mppaused' : 'mpon') + '">' +
      '<h2>' + esc(k.title) + ' <span class="mpstate">' +
        (paused ? 'Paused' : 'Sending') + '</span></h2>' +
      '<p class="mute">' + esc(k.what) + '</p>' +
      '<p>' + esc(paused
          ? (held ? held + " waiting. They go when this is unpaused."
                  : "Nothing is waiting.")
          : "On. New messages go out within a minute.") + '</p>' +
      (s.since ? '<p class="mute">Last changed ' + esc(when(s.since)) +
                 (s.by ? ' by ' + esc(s.by) : '') + '.</p>' : '') +
      '<button' + (paused ? '' : ' class="ghost"') +
        ' data-mpkind="' + k.kind + '" data-mpto="' + (paused ? 'on' : 'off') + '">' +
        (paused ? 'Unpause ' : 'Pause ') + esc(k.title.toLowerCase()) + '</button>' +
      '<div id="mpmsg-' + k.kind + '"></div></div>';
  }).join("") + '</div>';
}

/* What unpausing will release, in the words of the confirm box. */
function mpConfirm(kind, s){
  if (kind === "client") {
    return "Unpause client escalation-matrix mail?\n\nOperations will be able to " +
           "send the monthly matrix to client branches.";
  }
  var held = mpHeld(s);
  return "Unpause internal mail?\n\n" +
         (held ? held + " waiting will start going out within a minute."
               : "New messages will go out within a minute.");
}

function mpWire(m, reload){
  Array.prototype.forEach.call(document.querySelectorAll("[data-mpkind]"), function(b){
    b.onclick = async function(){
      var kind = b.getAttribute("data-mpkind");
      var on = b.getAttribute("data-mpto") === "on";
      if (on && !confirm(mpConfirm(kind, ((m && m.pause) || {})[kind]))) return;
      b.disabled = true;
      var out = await crux("/api/mail/pause", { method: "POST",
                                                body: { kind: kind, paused: !on } });
      b.disabled = false;
      var box = el("mpmsg-" + kind);
      if (out.error) { if (box) box.innerHTML = msg("bad", out.reason || out.error); return; }
      if (box) box.innerHTML = msg("ok", out.note || "Done.");
      setTimeout(reload, 900);
    };
  });
}
