# Security

Vouch decides whether an AI agent may use your logins, so security reports are
taken seriously.

## Reporting a vulnerability

Please report privately through GitHub: **Security → Report a vulnerability** on
this repository. That page is the only contact for security reports: there is
no email address, and replies come on the report itself.

Include what you found, how to reproduce it, and what an attacker could do with
it. Fixes are released as soon as they're ready, and reporters are credited
unless they'd rather not be.

If that page is not offered, open an issue that says only that you have a
security report and asks for a private contact. Do not put details in it.

Security fixes go into the latest release of each part (server, broker and
app). Older releases are not patched: upgrade to get a fix.

## Scope

In scope: the server (`server/`), the app (`app/`), the credential broker
(`broker/`), the browser setup (`browser/`), the API contract (`api/`) and the
install and deploy scripts.

Out of scope: weaknesses in an installer's own setup (their reverse proxy,
Firebase project, Cloudflare account, 1Password account or network), and issues that need a
compromised phone or root on the server.

## How Vouch is meant to be secure

- Every app request that reads or changes anything is signed by a key that
  never leaves the phone. Two are not: the health check, and pairing, which
  the one-time setup code guards instead. Every
  decision is signed by a second key that the app creates in the phone's secure
  hardware so that it needs a fingerprint or Face ID for each use.
- A phone joins only with a one-time setup code that the server's owner makes
  on the server. It works once and for ten minutes. Treat it like a password.
- The signed decision includes a digest of the request as the phone displayed
  it, so an answer can't be moved to a request the owner never saw.
- Push notifications carry only ids, never what is being approved.
- Requests reach Vouch only through local Unix sockets, and file permissions
  decide which unix users may open them.

If you find a way around any of these, that is exactly what we want to hear.

## The credential broker

What it is meant to guarantee:

- **The password is never given to the agent.** The broker reads the login from
  1Password and types it into the page itself. No reply to the agent, log line
  or event carries a username, password or security answer, or any text the
  page shows. A reply can name the page's host and the kind of field the
  broker found (its tag and type). So the password stays out of the agent's conversation and
  transcripts, unless the agent sets out to take it (next list).
- **No sign-in without you.** Every sign-in needs your approval on the phone,
  or a standing approval you gave there for that agent and that login. Agents
  can't grant themselves one.
- **A login goes only to its own site.** The broker fills a login only on a
  page that matches a website on the 1Password item, and types a password only
  into a password field.
- **An agent is who the kernel says it is.** The broker identifies a caller by
  the unix user on the other end of its socket, never by anything the caller
  says, and each agent reads only its own 1Password vault through its own
  read-only service account.

What it does not protect, by design:

- **An agent that sets out to read the password from its own browser can.**
  See "Known limits".
- **The agent is signed in afterwards.** It drives the browser, so it can do
  anything that account can do on that site, and it can read pages that show
  account details. Approve a sign-in only for an agent you would let use the
  account. The broker does not hand over the password; it does not limit what
  the session is used for, or for how long (see "Known limits").
- **A site that shows or emails the password back** gives it to the agent.
- **Root on the machine**, and anything running as the `credbroker` user, can
  read the tokens.

Two things to guard on your machine:

- **The token store.** `/etc/credbroker/secrets.env` (or your Vault secret)
  holds each agent's 1Password service account token. An agent that can read
  its token can ask 1Password directly and skip approval. Keep the file as the
  installer made it: root and the broker only. Give each service account read
  access to one vault and nothing else.
- **The DevTools port and the display.** Chrome's DevTools port has no login:
  any process that can connect to it controls a browser with live sessions.
  `browser/setup` loads a firewall rule that refuses connections to each
  agent's port on this machine from every unix user except that agent and the
  broker. `chrome-start` and the broker refuse a port the rule does not cover,
  and a port some other user is listening on. Each agent's display has its own
  key, and `chrome-start` starts it without the X shared memory extension
  (MIT-SHM). With that extension Chrome keeps its window's frames in shared
  memory that any unix user on the machine can read, key or no key. A display
  that an older `chrome-start` started keeps the extension until it is
  restarted: `chrome-start` replaces it when it next runs with Chrome closed,
  and prints a warning while Chrome is still open on it. If you start the
  display yourself, turn the extension off (see `browser/README.md`). Don't
  expose the port beyond `127.0.0.1`, and don't run agents that
  should be kept apart as one unix user. What this does not cover is under
  "Known limits".

The daily leak check looks for a password that has ended up in an agent's files
anyway, and says where.

## Known limits

- **The broker types the password into a browser the agent controls.** The
  agent's Chrome runs as the agent's own unix user and the agent drives it. An
  agent that tries can read the password field after it is filled, record the
  keystrokes with a script it put in the page, or put a program of its own on
  its port in place of Chrome. Reading the field takes no exploit: the agent
  only has to choose to look. Usernames and answers to security questions are
  typed into ordinary text fields, which any page script can read. With
  "Always allow" there is no request on your phone, so an agent that has been
  taken over can start a sign-in and take that password at any time. What the
  broker prevents is the password being
  handed over: it is in no reply, log or event, so an agent that isn't trying
  to take it never has it, and it doesn't end up in transcripts. That stops
  accidents and casual prompt injection. It does not stop an agent that has
  been taken over and goes after the password on purpose. Closing this needs
  the browser to run as a separate unix user that the agent reaches only
  through the broker, with each sign-in done in a browser context the agent has
  never touched. That is not built. Until then, give an agent only
  logins you would accept it knowing, and use a password that is unique to
  each site. Give each agent its own vault. Use "Always allow" only for logins
  of low value. If an agent misbehaves, change the passwords in its vault.

- **"Approve once" approves one sign-in, not one task.** The agent's browser
  keeps its profile, so after one approval the agent stays signed in to that
  site until the site ends the session, which can be weeks, and through
  browser restarts. Vouch is not asked again in that time, because the agent
  does not need the password again. After a sign-in you approved once, the
  broker tells the agent to sign out when its task is done. That is an
  instruction, not a control: an agent that ignores it, or that has been taken
  over, stays signed in. To be sure a session has ended, sign out that
  session from the site's own account settings, or change the password.

- **The port guard is a firewall rule, and root can change it.** It keeps
  other unix users off an agent's DevTools port. It does not stop root, or
  anything allowed to change the firewall. `chrome-start` and the broker check
  the record of what the guard last loaded, not the rules in force at that
  moment, so if another tool replaces the machine's nftables rules the port is
  open until `vouch-cdp-guard load` runs again.

- **Another user on the machine can stop an agent's browser from starting.**
  Each agent's display has a fixed number. A unix user who starts a display
  server on that number first, or leaves a file in its place, blocks it:
  `chrome-start` sees that the display is not the agent's own and refuses to
  use it. That user cannot watch or drive the agent's browser this way. The
  agent has no browser until root removes what is in the way.

- **Whatever is in the `vouch-broker` group decides what your phone shows.**
  A member of that group sends the agent name, the site and the login title of
  a request, and can send alerts. Vouch checks their form (one line of visible
  text, a host name for the site), not whether they are true. It does not cap
  how many requests a member has waiting. So keep agents out of that group: it
  is for the broker.

- **A site name can still look like another.** The app marks hidden
  characters, and anything in a site name that is not plain ASCII, as
  `[U+XXXX]`, so odd text looks odd on your phone. It cannot catch a name made
  of ordinary letters that reads like another (`rn` for `m`, `l` for `1`). An
  international name is shown in its `xn--` form, which says nothing about
  what it looks like in a browser. An alert's text can run over several
  lines. Read the site before you approve.
- **A very long site name is cut at its start, and the approve buttons can need a scroll.**
  Above the buttons the site is shown in at most three lines. A name that does
  not fit loses its start to "…" and keeps its end.
  It is cut at a dot, so what is left begins on a whole part of the name. It
  always keeps its last two parts. That is the real domain for a name that
  ends in `.com`. Under an ending of two parts it is only the ending: a long
  name before `.co.uk` shows as `…co.uk`, without the part that says whose
  site it is. If the last two parts alone do not fit, they are shown whole on
  as many lines as they need. The
  headline above holds the whole name, but at a large text size it can be out
  of view until you scroll to it, and the start of a long name is
  whatever its owner chose. Deny does not scroll: it is fixed below the part
  that does. The site, "Approve once" and "Always allow" are above it and
  scroll, with a scrollbar shown, so on a short screen or at a large text
  size the approve buttons can need a scroll. In the app's tests Deny is in
  view the moment a request opens, and a tap there sends Deny, on five screen
  sizes (320 by 568 and 384 by 832 upright, each on its side, and 384 by 400
  for a split screen), at up to three and a half times the normal text size,
  for a short site, a 253-character site, a very long agent name and a
  request to text someone. The tests give the screen no notch and no system
  bars, and say nothing about other sizes. On a phone the fixed Deny has been
  seen once, on an iPhone held upright: not on its side, not in a split
  screen and not on Android. The part above, with the agent's name, the
  headline and the login, scrolls on its own. On that iPhone at the largest
  text size the headline was out of view until it was scrolled. At a large
  text size, scroll both parts and read them before you approve. Read the end
  of the site before you approve.

- **The server, the app and the broker can disagree about a new character.**
  Each decides which characters are hidden or not yet assigned from the
  Unicode tables it was built with. After a new Unicode version, one may let
  through a newly assigned character that another does not know. The app
  shows a character it does not know as `[U+XXXX]`, and the server refuses
  one it does not know. So the worst case is text that looks odd on your
  phone, or a request that is refused, until all three are updated.

- **An agent can keep asking.** Through the credential broker an agent has one
  request on your phone at a time, but nothing limits how often it asks or
  makes it wait after you deny one.

- **1Password is asked before you are.** For every sign-in request the broker
  reads the login from 1Password first and asks your phone second. The read
  counts against the limits 1Password sets on service accounts whether or not
  a request then reaches your phone. `sign_in` on a login that has no
  password, for example, is refused after the read, with no request. An agent
  that repeats such calls can use up the allowance, and sign-ins then fail
  until 1Password allows reads again. 1Password counts part of that
  allowance for the whole account, so your other agents can be stopped too.

- **Any concealed field on a login can be typed, in either kind of sign-in.**
  Every concealed field on the item other than the password counts as an
  answer to a security question. In an ordinary sign-in, if the site shows
  another page with a password field after the password is sent, the broker
  looks for the one concealed field whose label is in that page's text and
  types it into that field. The page's own text makes the choice. With
  "Always allow" this happens with no request on your phone. In an assisted
  sign-in you approved, the agent is given the label of every concealed field
  on the item. It names a question, and the broker types the concealed field
  whose label matches it into a password field or an ordinary text field on
  the login's own site. A script in the page can read an ordinary text field. So
  keep on a Login item only the concealed fields you would accept the agent
  knowing, and keep recovery codes and other secrets somewhere else.

- **A sign-in goes on if the agent stops waiting.** If the program that asked
  for a sign-in disconnects while the request is on your phone, the request
  stays there. If you then approve it, the broker still types the login into
  the agent's browser.

- **"Always allow" takes one tap.** It has no second step: one tap and the
  same fingerprint or face check as "Approve once". The button sits between
  "Approve once" and "Deny". On a phone that checks your face, the check can
  pass at a glance, because the app does not ask for a confirming tap after
  it. On an iPhone with Face ID the check shows no words saying which button
  it is for. After any answer the app leaves the request at once (opened
  from a notification on Android, the app closes), and no page says what was
  chosen. Read which button you are pressing. To check afterwards, run
  `credbroker approvals --all` as a unix user the broker's config marks
  `admin = true`, and end a standing approval you did not mean with
  `credbroker revoke <agent> <login title>` (see `docs/broker.md`).

- **Alerts share one allowance.** Vouch passes on ten alerts an hour in total,
  whatever their severity. An alert over that is refused, not kept: after ten
  unimportant ones, an important one sent in the same hour never reaches your
  phone. The server logs that it refused one. The leak check logs a warning
  and does not send its alert again.

- **Standing approvals can't be listed or revoked from the phone yet.** "Always
  allow" is kept by the broker. To end one, ask the agent to revoke its own, or
  use the broker's command line (see `docs/broker.md`). Revoking stops future
  sign-ins. It does not sign out a session the agent already has open.

- **The leak check looks only where it is told.** By default that is each
  agent's `~/.claude`, the broker's own data and the broker's journal. A
  password an agent wrote somewhere else, or changed before writing (split,
  encoded), is not found. It also skips: values shorter than 6 characters,
  files larger than 64 MB, folders named `cache`, `.cache`, `.git`,
  `node_modules`, `.venv`, `plugins` or `chrome-profile`, and journal entries
  older than two days. It does not enter another filesystem mounted inside a
place it searches, or a place reached through a link an agent could have
made. It finds a value as written or as escaped in JSON, not
  in base64 or URL encoding. The check's time is shared equally between the
  places `roots` matches. A wildcard in a part of the path an agent can write
  lets that agent add places, which shortens every other place's share. Keep
  wildcards above the agents' own folders, as in `/home/*/.claude`. A path in
  `roots` that matches nothing is skipped without a word, unless none match.
  An agent chooses its own file names, so read the
  check's log lines with that in mind. The alert on your phone is built to
  fit in 2,000 characters. It opens with how many places were found for each
  agent's logins (the first 12 agents by name, then how many more agents
  there are). Then it lists places, one from each agent in turn, at most 20
  and fewer if they do not fit. Each place is cut to 150 characters: a long
  login title loses its end, and a long path keeps its end, where the file's
  name is. If places are left out, the last line says "and
  N more, see the log". So however many places one agent's logins are found
  in, and however long its file names are, it cannot take another agent's
  turn in the list. What an agent can still do is make the list shorter:
  with many hits it has a place in every turn, the places that do not fit
  are left out, and the alert ends with "and N more". If more agents have
  hits than the list has room for, the last ones by name are counted and not
  listed. The check's log has up to 200 places for each password or security
  answer in each place the check looks, each with the last 4,096 characters
  of its path, and after that how many more there were. The check holds no
  more than that, so that an agent cannot use up its memory by giving one
  file many thousands of names or by putting it very deep.

- **A leak can be found and your phone not told.** If the alert cannot be
  sent, the check logs a warning and still ends the way it does when the
  alert was sent, so the unit does not show as failed. A run that fails, or
  that is killed for passing its time or its memory limit (`MemoryMax=` in
  the unit), shows in `systemctl status credbroker-leakcheck`, and systemd
  then starts a second unit, `credbroker-leakcheck-failed.service`, which
  sends one alert with a fixed text. That has been run once on one machine,
  with the units as installed and the leak-check unit given a memory limit
  too small to start under: the kernel killed it, the second unit sent the
  alert through Vouch, and it arrived on a phone. Only that one way of
  failing was tried with the installed units. The second alert goes through
  Vouch too, so if Vouch
  cannot be reached, neither arrives, and it is run by the same Python as
  the check, though with none of the check's code or packages. A run that
  failed sends its own alert first where it can, so one failure can bring
  two alerts, or three when a leak was found as well.
  An agent can make the check fail on purpose, every day if it chooses: by
  putting a link where its `~/.claude` was, by making that folder too large
  to search in its share of the time or of the check's memory, or by using
  up the 1Password allowance (see "1Password is asked before you are"). Your
  phone is then told that the check failed or which places it could not
  search, not what it would have found there. If 1Password hands over no
  list of logins, or the run is killed, the places not yet reached were not
  searched that day, other agents' included. A leak check that fails day
  after day is a reason to look at what the agents are doing.

- **The broker's units are sandboxed less tightly than the server's.**
  `credbroker.service` and the root leak check have fewer systemd restrictions
  than `vouch.service`.

- **On Android the server checks the phone's key; on iPhone it takes the app's
  word.** An Android phone proves with Google's key attestation that its
  decision key is in secure hardware and needs the user for every use, and the
  server refuses it otherwise. iOS has no equivalent for these keys, so the
  server records an iPhone's key as `client_asserted`: the Vouch app does
  create it in the Secure Enclave behind Face ID or Touch ID, but the server
  can't verify that. Anything that holds a valid setup code and says it is an
  iPhone can pair a key with no biometric protection, even with
  `require_user_auth = true`. The setup code is therefore the gate: only hand
  it to a phone you are holding. Apple's App Attest is the planned way to close
  this.
- **Android attestation is checked up to Google's roots, and no further yet.**
  The server does not check the revocation list, whether each issuing
  certificate is marked as a certificate authority, or whether the phone's boot
  is verified.

- **A paired phone is taken at its word for its name.** The device name sent
  at pairing is stored as it arrives.

- **An Android phone answers the server's check-in only when Vouch is open.**
  The server sends every phone a data push each `[heartbeat] interval_hours`
  and logs a phone that has not checked in for `silent_after_hours`. On
  Android the app cannot reach its key while it is in the background, so it
  keeps the check-in and sends it when Vouch is next opened. In use, an
  iPhone answered within two seconds and an Android phone hours or days
  later. So for an Android phone the last check-in means "last opened", not
  "last reached": a phone can be logged as silent only because nobody opened
  the app, and its answer does not show that a push just got through.

- **"Forget this server" does not unpair the phone on the server.** It
  deletes the phone's keys and its pairing, and tells the server nothing. The server still lists the phone and still sends it a
  push for every request, so the phone keeps showing the fixed-text
  notification. It cannot answer one: its keys are gone. To stop the
  notifications, run `vouch devices` on the server, then `vouch unpair <id>`.

- **One agent can stop the broker for every agent.** The broker does not cap
  how many connections an agent opens. It writes a record for every sign-in
  call before it looks at the browser or the vault, and never deletes one. It
  reads the list of tabs from the agent's browser port whole, however long,
  and the agent decides what answers on that port. An agent that sets out to
  can use up the broker's memory or disk. While the broker is down no agent
  is signed in: it fails closed.

- **A Cloudflare Access token goes to the host you confirm.** If you enter the
  token before pairing, the app shows the server's host name and sends the
  token only when you tap Pair. It cannot tell whether that host is yours. A
  lookalike host name gets the token if you confirm it, so read the name
  before you pair.

- **An alert's own text is shown only while Vouch is open.** A request's
  notification has fixed text: it says that an agent is asking, not which
  agent or for which site, and on Android a request cannot be answered while
  the phone is locked. An alert that arrives while Vouch is not on screen
  has fixed text too, on both phones: it says that your server reported a
  problem, and you open Vouch to read what. By the app's code and the
  phone's own rules (not yet seen on a phone), an alert that arrives while
  Vouch is on screen is shown as a notification with the alert's title and
  text, which whatever sent the alert chose: the leak check's alert lists
  file names, for example. A notification stays until it is cleared, so that
  one can still be there when the phone is next locked. Whether its text
  shows on the lock screen follows the phone's own setting: with sensitive
  notification content hidden, the lock screen shows only that Vouch has a
  notification. With it shown, anyone holding the locked phone can read it.

- **Small things the app does not do yet.** "Forget this server" leaves a saved
  Cloudflare Access token on the phone. The saved server address is not checked
  again for plain HTTP after pairing.

- **Rate limits behind a reverse proxy need `trusted_proxies`.** With it empty,
  which is the default, every phone looks like the proxy and shares one
  allowance, so one busy or hostile client can use up everyone's. Nothing
  warns about this at startup. Over IPv6 the limit is per address, and one
  network has a great many addresses.

- **Over plain HTTP the phone cannot tell your server from an impostor.** The
  app allows plain HTTP only to a private address, a `.local` name or the same
  machine, for trying things on a home network. There, anyone on that network
  can read the setup code as the phone sends it at pairing, and can answer in
  the server's place. Use HTTPS for anything you keep.

- **Some answers come before the signature is checked.** A request whose
  shape is wrong, or that is over a rate limit, is refused without a
  signature, so anyone who can reach the server can learn which fields a
  route expects. The health check needs no signature and gives the exact
  server version.

- **One "Approve once" in assisted sign-in covers several typed secrets.**
  After one approval the broker types the login's username, password and
  security answers as the agent asks for them, for up to three minutes, each
  only into a field of the right kind on the matching site.

- **A wrong setup code still leaves a small record.** A pairing attempt is
  stored before its setup code is checked, so someone who can reach the server
  can make its database grow.

- **The SMS module.** Whatever is in the `vouch-sms` group chooses the
  contact name and the reason your phone shows when it asks to text someone
  new. Vouch checks their form, not whether they are true. Every member of
  the `vouch-sms` group is the same caller to Vouch: the socket does not tell
  them apart. Any member can read the whole message history and the contact
  list, and sends from the one number. One log line carries the full phone number of a contact
  being asked about. A text from the owner's number reaches the agent as the
  owner's, without the "untrusted" label other senders get, and a sender's
  number can be forged. The daily cap can be passed by a few messages when
  several are sent at the same moment.

- **Releases are not signed yet.** The installers check each download against
  the SHA-256 published beside it, which catches a corrupted download, not a
  tampered release. The Docker image carries basic build provenance; the
  server and broker bundles and the Android app do not.

- **Some of what the build uses is updated by hand.** Automatic update checks
  cover the packages of the server, the broker and the app, the Docker
  images, the Android build and the workflows. They do not cover the
  Playwright version that `browser/setup` installs, the Flutter SDK, the
  generator that writes the app's API client, or the checking tools that CI
  downloads. Each of those is pinned to a version that is changed by hand.
  The tool that builds the broker's package (`hatchling`) is not pinned: a
  build uses the newest version.

- **The broker installer does not re-tighten a secrets file.** It creates
  `/etc/credbroker/secrets.env` readable by root and the broker only, and
  leaves an existing one as it finds it. If you loosen it, running the
  installer again does not put it back.
