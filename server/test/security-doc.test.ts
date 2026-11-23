import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";

const FILE = new URL("../../SECURITY.md", import.meta.url);

// SECURITY.md must not promise more than the code does, and must say what is left open.
test("SECURITY.md states its limits and does not overstate its promises", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  for (const must of ["Releases are not signed", "can't be listed or revoked from the phone",
    "does not sign out a session the agent already has open", "It does not stop root", "approves one sign-in, not one task", "That is an instruction, not a control", "A lookalike host name gets the token if you confirm it", "`vouch-broker` group decides what your phone shows",
    "on the lock screen follows the phone's own setting",
    "A site name can still look like another", "ordinary letters that reads like another", "shown in its `xn--` form"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  for (const must of ["Over plain HTTP the phone cannot tell your server from an impostor", "read the setup code as the phone sends it",
    "values shorter than 6 characters", "files larger than 64 MB", "`chrome-profile`", "journal entries older than two days",
    "not in base64 or URL encoding", "does not enter another filesystem mounted inside", "Some answers come before the signature is checked", "gives the exact server version",
    "`vouch-sms` group chooses the contact name and the reason", "covers several typed secrets"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  assert.ok(!text.includes("Every app request is signed by"), "the signing promise leaves out pairing and the health check");
  assert.ok(!text.includes("any text copied from the page"), "the reply promise leaves out the host and field kind");
  assert.ok(!text.includes("restricts each port to its agent and the broker"), "the port claim is still stated without its limits");
  assert.ok(!/password never enters the agent|out of reach/.test(text), "the password promise is overstated");
  for (const must of ["Reading the field takes no exploit", "typed into ordinary text fields",
    'With "Always allow" there is no request on your phone', "Give each agent its own vault",
    'Use "Always allow" only for logins of low value', "change the passwords in its vault"]) {
    assert.ok(limits.includes(must), `the first known limit does not say: ${must}`);
  }
  // The fingerprint prompt now names the decision, so this is no longer a limit.
  assert.ok(!limits.includes('"Confirm approval" for Deny'), "a limit that no longer applies is still listed");
});

test("the README and the broker guide do not overstate the port guard", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8").replace(/\s+/g, " ");
  assert.ok(!read("README.md").includes("only that agent and the broker can reach it"), "README.md says nobody else can reach the port; root can");
  assert.ok(!read("docs/broker.md").includes("unix user started"), "docs/broker.md says the broker checks who started the browser; it checks who listens on the port");
});

// The password promise is the narrow one everywhere it is made: the broker does not hand the
// password over, and an agent that looks in its own browser can read it.
test("every document that makes the password promise also states its limit", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const promise = /never (given|hands?) the password|password is never given|password being given|handing the password|does not hand(?: over)? the password/;
  const overstated = /can't tell you the password|password entering the agent|password never enters|safe way to sign in/;
  for (const name of ["README.md", "INSTALL.md", "SECURITY.md", "docs/broker.md", "broker/README.md", "browser/README.md",
    "examples/agent-instructions.md", "broker/pyproject.toml"]) {
    const text = readFileSync(new URL(`../../${name}`, import.meta.url), "utf8").replace(/\s+/g, " ");
    assert.ok(!overstated.test(text), `${name} overstates the password promise`);
    if (!name.endsWith(".md") || !promise.test(text)) continue;
    assert.ok(text.includes("Known limits") && /its own browser/.test(text),
      `${name} makes the password promise without saying an agent can read it from its own browser`);
  }
});

// An agent that runs as the owner's own login, or with sudo, can pair a phone of its own.
test("the guides say the agent's unix user must be unprivileged and stay out of vouch-broker", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8").replace(/\s+/g, " ");
  for (const name of ["INSTALL.md", "docs/broker.md"]) {
    const text = read(name);
    assert.ok(text.includes("must not be your own login, must not be able to use sudo"), `${name} does not say the agent's user must be unprivileged`);
    assert.ok(text.includes("`vouch`, `credbroker`, `vouch-broker`, `docker` or `sudo` groups"), `${name} does not name the groups to keep the agent out of`);
  }
  assert.ok(!read("docs/agent-api.md").includes("you grant an agent access by adding its user to a group"), "docs/agent-api.md leads an agent into vouch-broker");
  assert.ok(!/An agent, or your own tool, can ask your phone/.test(read("README.md")), "README.md leads an agent onto the broker socket");
  assert.ok(read("examples/vouch-ask.py").includes("do not put an agent's own user in that group"), "examples/vouch-ask.py does not warn about the group");
});

test("SECURITY.md gives a second way to report and says which versions get fixes", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  assert.ok(text.includes("If that page is not offered"), "no fallback when GitHub does not offer the report page");
  assert.ok(text.includes("Security fixes go into the latest release of each part"), "no supported-versions line");
});

test("the trademark statement is in NOTICE and the contributing guide names all three test suites", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8").replace(/\s+/g, " ");
  const notice = read("NOTICE");
  for (const must of ["does not grant permission to use them", "section 6", "belong to their owners", "not affiliated with or endorsed by"]) {
    assert.ok(notice.includes(must), `NOTICE does not say: ${must}`);
  }
  for (const name of ["1Password", "Android", "Apple", "Cloudflare", "Firebase"]) assert.ok(notice.includes(name), `NOTICE does not name ${name}`);
  assert.ok(read("README.md").includes("does not cover the Vouch name or logo"), "README.md does not point at the trademark statement");
  const contributing = read("CONTRIBUTING.md");
  for (const must of ["cd server && npm ci && npm test", "cd broker && uv run --frozen pytest -q", "cd app && flutter test", "`google-chrome` on the path"]) {
    assert.ok(contributing.includes(must), `CONTRIBUTING.md does not say: ${must}`);
  }
});

test("Known limits covers a blocked display and a character one part does not know", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  for (const must of ["Another user on the machine can stop an agent's browser from starting", "cannot watch or drive the agent's browser this way",
    "until root removes what is in the way", "can disagree about a new character", "from the Unicode tables it was built with",
    "text that looks odd on your phone, or a request that is refused"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
});

// A display key does not cover Chrome's frames in shared memory: the display must not offer MIT-SHM.
test("the display claim names the shared memory extension, and chrome-start turns it off", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8").replace(/\s+/g, " ");
  const security = read("SECURITY.md");
  assert.ok(!security.includes("Each agent's display has its own key. Don't"), "SECURITY.md still rests the display on its key alone");
  for (const must of ["starts it without the X shared memory extension (MIT-SHM)", "shared memory that any unix user on the machine can read, key or no key",
    "keeps the extension until it is restarted", "prints a warning while Chrome is still open on it", "If you start the display yourself, turn the extension off"]) {
    assert.ok(security.includes(must), `SECURITY.md does not say: ${must}`);
  }
  const browser = read("browser/README.md");
  assert.ok(!browser.includes("(`~/.vouch-browser/Xauthority`), so no other user"), "browser/README.md still rests the display on its key alone");
  assert.ok(!browser.includes("has no key, and any user on the machine can connect to it. `chrome-start` replaces"),
    "browser/README.md still names only a missing key as the reason to restart after upgrading");
  for (const must of ["it runs without the X shared memory extension (MIT-SHM), so no other user", "**Your own display server:** turn off MIT-SHM",
    "the display's key does not stop them", "has a key but still offers MIT-SHM"]) {
    assert.ok(browser.includes(must), `browser/README.md does not say: ${must}`);
  }
  const start = new URL("../../browser/chrome-start", import.meta.url);
  if (!existsSync(start)) return;
  const code = readFileSync(start, "utf8");
  assert.match(code, /^\s*Xvfb "\$DISPLAY_NUM" .*-extension MIT-SHM /m, "chrome-start no longer starts Xvfb without MIT-SHM: the display claim is not true");
  assert.match(code, /\*" -extension MIT-SHM "\*\) ;;/, "chrome-start no longer checks a running display for MIT-SHM: the upgrade claim is not true");
});

// The tree ships the maintainer's own mark and application id as the defaults for the app.
test("NOTICE covers the Viewbridge mark and says a distributed build must carry its own", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8");
  const notice = read("NOTICE").replace(/\s+/g, " ");
  for (const must of ['"Viewbridge" and the Viewbridge mark belong to Viewbridge AI', "application id ai.viewbridge.vouch unless you set your own",
    "A build you distribute must use your own name, mark and application id"]) {
    assert.ok(notice.includes(must), `NOTICE does not say: ${must}`);
  }
  const gradle = new URL("../../app/android/app/build.gradle.kts", import.meta.url);
  if (!existsSync(gradle)) return;
  assert.match(readFileSync(gradle, "utf8"), /getProperty\("applicationId"\) \?: "ai\.viewbridge\.vouch"/, "the default application id changed: NOTICE names it");
  assert.equal(read("app/assets/legal/NOTICE"), read("NOTICE"), "the app's copy of NOTICE is not the repository's");
});

// A request's notification is fixed text on both phones, and so is an alert's unless Vouch is
// on screen when it arrives. Only that one carries text its sender chose.
test("Known limits says what a lock screen can show: an alert's own text only if Vouch was open", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  for (const must of ["A request's notification has fixed text", "not which agent or for which site",
    "An alert that arrives while Vouch is not on screen has fixed text too, on both phones",
    "By the app's code and the phone's own rules (not yet seen on a phone), an alert that arrives while Vouch is on screen is shown as a notification with the alert's title and text",
    "can still be there when the phone is next locked", "anyone holding the locked phone can read it"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  assert.ok(!/notification names the agent and the site|read which agent is asking for which site/.test(text),
    "SECURITY.md still says the request notification names the agent and the site");
  // That one has been read in the code, not seen on a phone: the sentence must not open flat.
  assert.ok(!limits.includes("An alert that arrives while Vouch is on screen"), "Known limits still states the alert shown while Vouch is on screen as if it had been seen on a phone");
  assert.ok(!/On Android its notification shows the alert's title and text/.test(text),
    "SECURITY.md still says an Android alert always shows its sender's text");
  const notifications = new URL("../../app/lib/push/notifications.dart", import.meta.url);
  if (existsSync(notifications)) {
    const code = readFileSync(notifications, "utf8");
    assert.match(code, /title: title \?\? 'Approval request'/, "the request notification's title is no longer fixed text: is the limit still true?");
    assert.match(readFileSync(new URL("../../app/lib/push/push_handler.dart", import.meta.url), "utf8"), /notifier\.showRequest\(requestId\);/,
      "the request notification is now given text: is the limit still true?");
    const service = readFileSync(new URL("../../app/lib/push/push_service.dart", import.meta.url), "utf8");
    const background = service.slice(service.indexOf("PushHandler backgroundPushHandler("));
    assert.ok(background.length > 0 && !/onAlert:/.test(background.slice(0, background.indexOf(");"))),
      "the background push handler fetches an alert's text now: is the limit still true?");
  }
});

test("Known limits covers the leak alert's size, an unsent alert, and the broker's three open doors", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  for (const must of ["is built to fit in 2,000 characters", "how many places were found for each agent's logins", "the first 12 agents by name",
    "one from each agent in turn, at most 20 and fewer if they do not fit", "Each place is cut to 150 characters", "a long path keeps its end, where the file's name is",
    'the last line says "and N more, see the log"', "it cannot take another agent's turn in the list",
    "What an agent can still do is make the list shorter", "the last ones by name are counted and not listed", "The check's log has up to 200 places for each password or security answer in each place the check looks", "each with the last 4,096 characters of its path",
    "two alerts, or three when a leak was found as well", "run by the same Python as the check",
    "A leak can be found and your phone not told", "`credbroker-leakcheck-failed.service`, which sends one alert with a fixed text",
    "That has been run once on one machine, with the units as installed", "given a memory limit too small to start under", "the second unit sent the alert through Vouch, and it arrived on a phone", "Only that one way of failing was tried with the installed units.", "if Vouch cannot be reached, neither arrives",
    "1Password is asked before you are", "is refused after the read, with no request",
    "Any concealed field on a login can be typed", "or an ordinary text field on the login's own site",
    "A sign-in goes on if the agent stops waiting", "the broker still types the login",
    '"Always allow" takes one tap', "It has no second step", "does not ask for a confirming tap"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  // It was seen on a phone on 2026-11-22: the document must not go on saying it was not.
  for (const gone of ["The units as installed were not made to fail", "It has not been seen on a phone"]) {
    assert.ok(!limits.includes(gone), `Known limits still says: ${gone}`);
  }
  // The time is shared between the places `roots` matches, so a wildcard an agent can add places under takes time from the others.
  for (const must of ["The check's time is shared equally between the places `roots` matches",
    "A wildcard in a part of the path an agent can write lets that agent add places, which shortens every other place's share",
    "Keep wildcards above the agents' own folders, as in `/home/*/.claude`",
    "A path in `roots` that matches nothing is skipped without a word, unless none match"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  assert.ok(!/alert on your phone and the unit's result do not depend on them/.test(text), "SECURITY.md still says the alert does not depend on file names");
  assert.ok(!limits.includes("has no `OnFailure=` action"), "SECURITY.md still says the leak-check unit has no OnFailure= action");
  assert.ok(!limits.includes("The check's log has every place in full"), "SECURITY.md still says the log has every place: the check holds 200 per login per place and counts the rest");
  // The alert is built to fit now, with a turn for each agent: the old limit must not come back.
  assert.ok(!/whole alert is cut at 2,000 characters|places in alphabetical order|can push another agent's hit out of the alert/.test(text),
    "SECURITY.md still says one agent can push another's hit out of the leak alert");
  const read = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8").replace(/\s+/g, " ");
  const check = new URL("../../broker/credbroker/leakcheck.py", import.meta.url);
  if (existsSync(check)) {
    const code = readFileSync(check, "utf8");
    for (const constant of ["MAX_PLACES = 20", "PLACE_LEN = 150", "MAX_AGENTS = 12", "ALERT_LEN = 2000", "JOURNAL_TIMEOUT = 120"]) {
      assert.ok(new RegExp(`^${constant}\\b`, "m").test(code), `leakcheck.py no longer has ${constant}: the documents give that number`);
    }
    assert.match(code, /zip_longest\(\*by_agent\.values\(\)\)/, "the alert no longer takes places from each agent in turn: is the limit still true?");
    assert.match(code, /hits \+= found {3}# before they are logged.*\n {8}more\.update\(uncounted\)\n {8}_log_places\(found\)/, "a root's hits are no longer logged when that root ends: broker/README.md says they are");
    assert.match(code, /^WHERE_LEN = 4096\b/m, "leakcheck.py no longer holds 4,096 characters of a place: the documents give that number");
    assert.match(code, /^KEEP = 200\b/m, "leakcheck.py no longer holds 200 places per login per root: the documents give that number");
    assert.match(code, /if held\[s\] < KEEP:/, "the leak check no longer limits the places it holds: is the limit in SECURITY.md still true?");
    assert.match(code, /share = max\(end - time\.monotonic\(\), 0\) \/ \(len\(roots\) - i\)/, "the check's time is no longer shared between the places roots matches: SECURITY.md says it is");
    assert.match(code, /for root in cfg\.leakcheck\.roots for p in sorted\(glob\.glob\(root\)\)/, "roots are no longer expanded as wildcards, one place for each match: SECURITY.md says they are");
    assert.match(code, /if not roots: {3}# each pattern may match nothing/, "a path in roots that matches nothing is no longer skipped: SECURITY.md says it is");
    assert.match(code, /roots_own = parent\.st_uid == 0 and not parent\.st_mode & 0o022/, "the rule for following a link changed: broker/README.md states it");
  }
  const readme = read("broker/README.md");
  for (const must of ["never follows a symbolic link an agent could have made", "only in a folder that root owns and nobody else can write to",
    "if 1Password does not hand over one of the logins", "if the broker's journal cannot be read to its end", "or is not done in two minutes",
    "Unless the check crashed, anything found elsewhere is still reported", "What was found in the files is logged before the journal is read",
    "one from each agent in turn, each cut to 150 characters", 'it ends with "and N more, see the log"', "up to 20 of the places, chosen and shortened as in the alert"]) {
    assert.ok(readme.includes(must), `broker/README.md does not say: ${must}`);
  }
  assert.ok(readme.includes("so one agent's files cannot use up another's (given no wildcard in `roots` below a folder an agent can write)"),
    "broker/README.md says one agent's files cannot use up another's time without the condition on wildcards");
  assert.ok(!/it never follows a symbolic link, reads/.test(readme), "broker/README.md still says the leak check never follows any symbolic link");
  assert.ok(!/alert naming what was not checked\. Anything found elsewhere is still reported/.test(readme),
    "broker/README.md still says findings are reported even when the check crashed");
  const guide = read("docs/broker.md");
  for (const must of ["That includes a login 1Password would not hand over that day", "a broker journal that could not be read to its end"]) {
    assert.ok(guide.includes(must), `docs/broker.md does not say: ${must}`);
  }
  assert.ok(guide.includes("Keep any wildcard above the agents' own folders, as in `/home/*/.claude`"), "docs/broker.md invites more roots without the caution on wildcards");
  assert.ok(guide.includes("offers every password-type field on the item, other than the password itself, as such an answer"),
    "docs/broker.md does not say every concealed field is offered as an answer");
  assert.ok(guide.includes("a leak whose alert could not be sent does not show as failed"), "docs/broker.md overstates what a failed leak check tells the owner");
  const unit = new URL("../../broker/deploy/credbroker-leakcheck.service", import.meta.url);
  if (existsSync(unit)) {
    const text = readFileSync(unit, "utf8");
    assert.match(text, /^OnFailure=credbroker-leakcheck-failed\.service$/m, "the leak-check unit starts nothing when it fails: SECURITY.md says it does");
    assert.match(text, /^MemoryMax=\d+[MG]$/m, "the leak-check unit has no memory limit: SECURITY.md says it has");
    const failed = readFileSync(new URL("../../broker/deploy/credbroker-leakcheck-failed.service", import.meta.url), "utf8");
    assert.match(failed, /^ExecStart=\S+ -I -S \S+\/deploy\/leakcheck-failed\.py$/m, "the failure unit no longer runs its script with the standard library only");
  }
});

test("Known limits names everything that is updated by hand", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  assert.ok(!limits.includes("One dependency is updated by hand"), "the limit still says only one dependency is updated by hand");
  for (const must of ["the Flutter SDK", "the generator that writes the app's API client", "the checking tools that CI downloads", "(`hatchling`) is not pinned"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
});

// An issue is public. The fallback must not ask for the details of a weakness in one.
test("the fallback way to report does not ask for details in a public issue", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const report = text.slice(text.indexOf("## Reporting a vulnerability"), text.indexOf("## Scope"));
  assert.ok(report.includes("says only that you have a security report and asks for a private contact"), "the fallback does not say what the issue may hold");
  assert.ok(report.includes("Do not put details in it."), "the fallback does not say to keep details out of the issue");
  assert.ok(!/issue on this repository with the same details/.test(report), "the fallback still asks for details in a public issue");
});

// The site row above the buttons is capped and keeps the end of the name.
test("Known limits says a very long site name is cut at its start, Deny stays in view and the approve buttons can need a scroll", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const limits = text.slice(text.indexOf("## Known limits"));
  for (const must of ["A very long site name is cut at its start", "in at most three lines", "It always keeps its last two parts",
    "It is cut at a dot", "Read the end of the site before you approve",
    "Deny does not scroll: it is fixed below the part that does", "the approve buttons can need a scroll",
    "at up to three and a half times the normal text size", "The tests give the screen no notch and no system bars",
    "On a phone the fixed Deny has been seen once, on an iPhone held upright: not on its side, not in a split screen and not on Android",
    "The part above, with the agent's name, the headline and the login, scrolls on its own",
    "On that iPhone at the largest text size the headline was out of view until it was scrolled",
    "At a large text size, scroll both parts and read them before you approve",
    "The headline above holds the whole name, but at a large text size it can be out of view until you scroll to it"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  // Deny has been seen on one phone, and the headline can be out of view: neither old sentence is true now.
  for (const old of ["It has not been checked on a phone", "The headline above still shows the whole name"]) {
    assert.ok(!limits.includes(old), `Known limits still says: ${old}`);
  }
  // Deny was the last button in the scrolling column and the first to fall out of view. It is pinned now.
  for (const old of ["Deny can need a scroll", "Deny is reached by scrolling the buttons", "Deny is below the edge", "Deny took one swipe"]) {
    assert.ok(!limits.includes(old), `Known limits still says: ${old}`);
  }
  // Seen on a phone: Deny needs a scroll on its side at the normal text size, not only at three times.
  assert.ok(!limits.includes("at very large text Deny needs a scroll"), "Known limits still says Deny needs a scroll only at very large text");
  assert.ok(!limits.includes("at about three times the normal text size on a small phone"), "Known limits still puts the scroll only at three times the text size on a small phone");
  assert.ok(!/The site is shown whole/.test(limits), "Known limits still says the site row is shown whole");
  // Under a two-part ending the last two parts are the ending: the name's own part is cut.
  assert.ok(!limits.includes("where the real domain is"), "Known limits still says the end that is kept is always the real domain");
  assert.ok(limits.includes("shows as `…co.uk`"), "Known limits does not say a long name under a two-part ending loses its own part");
  const screen = new URL("../../app/lib/screens/request/request_screen.dart", import.meta.url);
  if (existsSync(screen)) assert.match(readFileSync(screen, "utf8"), /_TailText\(/, "the site row no longer keeps the end of a long name: is the limit still true?");
  // Deny sits after the Flexible scrolling part, inside the capped column, not inside the scroll view.
  if (existsSync(screen)) assert.match(readFileSync(screen, "utf8"), /Flexible\(\s*child: _Scrolled\([\s\S]*?\),\s*_DenyButton\(/, "Deny is no longer pinned under the scrolling part: is the limit still true?");
  // The headline and the login are in a scrolling part of their own, above the one with the site and the approve buttons.
  if (existsSync(screen)) assert.match(readFileSync(screen, "utf8"), /Expanded\(\s*child: _Scrolled\([\s\S]*?_Headline\(request: request\)[\s\S]*?_Detail\(label: 'Login'[\s\S]*?ConstrainedBox\(/,
    "the headline and the login are no longer in a scrolling part of their own: is the limit still true?");
});

const doc = (name: string) => readFileSync(new URL(`../../${name}`, import.meta.url), "utf8");
const flat = (name: string) => doc(name).replace(/\s+/g, " ");
const knownLimits = () => { const text = flat("SECURITY.md"); return text.slice(text.indexOf("## Known limits")); };

// The broker reads the login from 1Password before it asks the phone (server.py: credentials, then authorize).
test("no guide says the login is read after approval", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const readme = flat("README.md");
  assert.ok(!/reads login[^a-z]*after approval/.test(readme), "the README's diagram still says the login is read after approval");
  assert.ok(!readme.includes("You approve. The broker reads the login"), "the README's step 4 still reads the login after approval");
  assert.ok(readme.includes("You approve. The broker types the login into the page."), "the README's step 4 does not say what approval does");
  assert.ok(readme.includes("1Password vault and reads it"), "the README's step 2 does not say the login is read then");
  const guide = flat("docs/broker.md");
  assert.ok(!guide.includes("On approval the broker reads the login"), "docs/broker.md still reads the login after approval");
  assert.ok(guide.includes("matches the page, and reads it"), "docs/broker.md does not say the login is read before you are asked");
  assert.ok(!/asks the owner to approve on their phone, reads the login/.test(flat("broker/README.md")), "broker/README.md still reads the login after approval");
  const server = new URL("../../broker/credbroker/server.py", import.meta.url);
  if (existsSync(server)) {
    const code = readFileSync(server, "utf8");
    const read = code.indexOf("await vault.credentials(login.id)");
    assert.ok(read > 0 && read < code.indexOf("await self.authorize(agent, login"), "the broker no longer reads the login before asking: the guides say it does");
  }
});

test("Known limits covers a concealed field typed in an ordinary sign-in, and what Always allow does not show", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const limits = knownLimits();
  for (const must of ["In an ordinary sign-in", "The page's own text makes the choice", 'With "Always allow" this happens with no request on your phone',
    "the agent is given the label of every concealed field on the item",
    "On an iPhone with Face ID the check shows no words saying which button it is for", "no page says what was chosen",
    "`credbroker approvals --all`", "`credbroker revoke <agent> <login title>`"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  assert.ok(!limits.includes("can be typed at the agent's request"), "the concealed-field limit still covers assisted sign-in only");
  assert.ok(flat("docs/broker.md").includes("In an ordinary sign-in the broker picks the field itself"), "docs/broker.md does not say an ordinary sign-in types a concealed field too");
  const client = new URL("../../broker/credbroker/client.py", import.meta.url);
  if (existsSync(client)) {
    const code = readFileSync(client, "utf8");
    assert.match(code, /case \["approvals", "--all"\]/, "credbroker approvals --all is gone: SECURITY.md names it");
    assert.match(code, /case \["revoke", agent, \*title\]/, "credbroker revoke <agent> <login title> is gone: SECURITY.md names it");
  }
});

test("Known limits covers the Android check-in, Forget this server, the shared SMS identity and a broker one agent can stop", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const limits = knownLimits();
  for (const must of ["An Android phone answers the server's check-in only when Vouch is open", 'means "last opened"',
    '"Forget this server" does not unpair the phone on the server', "It cannot answer one: its keys are gone", "`vouch devices`", "`vouch unpair <id>`",
    "Every member of the `vouch-sms` group is the same caller", "read the whole message history",
    "One agent can stop the broker for every agent", "does not cap how many connections", "it fails closed"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
  const example = doc("server/config.example.toml");
  assert.ok(!example.includes("that each phone answers"), "config.example.toml still says each phone answers the push");
  assert.ok(example.replace(/\s*\n#\s*/g, " ").includes("An Android phone answers only when the app is open"), "config.example.toml does not say when an Android phone answers");
});

test("the alert allowance refuses, it does not hold back", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const limits = knownLimits();
  assert.ok(!limits.includes("can hold back an important one"), "Known limits still says an alert over the allowance is held back");
  for (const must of ["An alert over that is refused, not kept", "does not send its alert again"]) {
    assert.ok(limits.includes(must), `Known limits does not say: ${must}`);
  }
});

test("the maintainer's guide puts the steps in an order that works on a new public repository", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const guide = flat("docs/maintaining.md");
  for (const must of ["Create the repository public and empty", "Push one commit and no tags", "`git init -b main`", "`git push <remote> HEAD:main`", "`git ls-remote <remote>`",
    "`--tags` or `--mirror`", "publishes the history behind it", "after the first push and the first green run", "would refuse the first commit",
    "the Repository admin role", "Leave **Prevent self-review** unticked", "only if the `release` environment has a required reviewer",
    "is no defence against whoever writes the tagged commit"]) {
    assert.ok(guide.includes(must), `docs/maintaining.md does not say: ${must}`);
  }
  assert.ok(!guide.includes("put only yourself"), "docs/maintaining.md still puts a named user on a ruleset's bypass list");
  assert.ok(!guide.includes("Each workflow waits for your approval"), "docs/maintaining.md still says every release waits for approval, reviewer or not");
  const order = ["Create the repository public and empty", "**The `release` environment.**", "**Who may make a release tag.**",
    "**Private vulnerability reporting.**", "**Push one commit and no tags.**", "**The `main` branch.**", "**Announce.**"].map((s) => guide.indexOf(s));
  assert.ok(order.every((at, i) => at >= 0 && (i === 0 || at > order[i - 1]!)), `docs/maintaining.md has its steps out of order: ${order.join(", ")}`);
});

// A new repository that takes an old one's name is where every old clone already pushes.
test("the maintainer's guide keeps old clones and old tags out of a new repository that takes an old name", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const guide = flat("docs/maintaining.md");
  for (const must of ["Rename the old repository", "`git remote set-url origin <the renamed repository>`", "`git remote -v`",
    "`git -C <old clone> archive <commit> | tar -x -C <new directory>`", "A plain recursive copy can carry `.git`",
    "`git push <remote> refs/tags/server-vX.Y.Z`", "If a `vouch-server` container package already exists"]) {
    assert.ok(guide.includes(must), `docs/maintaining.md does not say: ${must}`);
  }
  // The release job of step 11 pushes an image to that name, so the old package goes before the first server tag.
  const first = "Before the first server tag, do the first part of step 12: an old `vouch-server` package must be gone before the release job pushes an image to that name.";
  const twelve = guide.indexOf("12. **The container image");
  assert.ok(guide.includes(first) && twelve > guide.indexOf(first), "docs/maintaining.md does not say, before step 12, that an old package goes before the first server tag");
  assert.ok(guide.includes("delete the package. If your own server pulls that image, `docker compose pull` fails there until the first new release."),
    "docs/maintaining.md does not say to delete the old package, or what that costs a server that pulls it");
  assert.ok(!guide.includes("delete every old version in it"), "docs/maintaining.md still offers deleting old versions: the package would stay linked to the old repository");
  const order = ["Rename the old repository", "No README, licence or `.gitignore` added by GitHub", "**Push one commit and no tags.**"].map((s) => guide.indexOf(s));
  assert.ok(order.every((at, i) => at >= 0 && (i === 0 || at > order[i - 1]!)), `docs/maintaining.md renames the old repository too late: ${order.join(", ")}`);
});

// The guide says the first CI run needs no secrets, so ci.yml must read none.
test("the maintainer's guide says the first CI run needs no secrets, and ci.yml reads none", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  assert.ok(flat("docs/maintaining.md").includes("That run needs no secrets"), "docs/maintaining.md does not say the first CI run needs no secrets");
  assert.ok(!/\bsecrets\s*[.[]/.test(doc(".github/workflows/ci.yml")), "ci.yml reads a secret: the guide says the first run needs none");
});

test("the smaller guides agree with NOTICE, the CLI and the code", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const building = flat("docs/building-the-app.md");
  assert.ok(!building.includes("if you want your own"), "docs/building-the-app.md still makes your own branding optional for a build you distribute");
  assert.ok(building.includes("A build you distribute must use your own name, mark and application id"), "docs/building-the-app.md does not say what NOTICE says");
  const install = flat("INSTALL.md");
  for (const must of ["**A phone is lost or replaced:**", "`vouch devices`", "`vouch unpair <id>`",
    "This phone no longer has its approval key. Forget this server in Settings, then pair again."]) {
    assert.ok(install.includes(must), `INSTALL.md does not say: ${must}`);
  }
  const text = new URL("../../app/lib/keys/key_error_text.dart", import.meta.url);
  if (existsSync(text)) {
    assert.ok(readFileSync(text, "utf8").includes("'This phone no longer has its approval key. Forget this server in Settings, then pair again.'"),
      "the app's message changed: INSTALL.md quotes it");
  }
  const ci = doc(".github/workflows/ci.yml");
  assert.match(ci, /cron: "23 10 \* \* 1"\s+# Mondays, 10:23 UTC/, "ci.yml's comment does not give the cron's own time");
  assert.ok(!/cron:.*\bET\b/.test(ci), "ci.yml's comment names a timezone the cron does not follow");
  assert.ok(flat("app/README.md").includes("environment secrets, not repository secrets"), "app/README.md does not point at the environment step of docs/maintaining.md");
  assert.ok(flat("docs/broker.md").includes("refuses the whole list"), "docs/broker.md does not say what an unknown autofill setting does to the vault");
});

// GitHub's page for reporting in private is the one contact: no address, and no promise of a reply time.
test("SECURITY.md names GitHub as the only way to report and promises no reply time", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const text = readFileSync(FILE, "utf8").replace(/\s+/g, " ");
  const report = text.slice(text.indexOf("## Reporting a vulnerability"), text.indexOf("## Scope"));
  assert.ok(report.includes("That page is the only contact for security reports: there is no email address"), "does not say GitHub is the only contact");
  assert.ok(!/within a few days|acknowledgement/.test(report), "still promises an acknowledgement");
  assert.ok(!/[\w.+-]+@[\w-]+\.[\w.]+/.test(report), "gives an address");
});

// Round seven, F-1: every way an agent has to stop the daily check is loud, and none says what it would have found.
test("Known limits says an agent can make the leak check fail on purpose, and what the phone is then not told", (t) => {
  if (!existsSync(FILE)) return t.skip("not a full checkout");
  const limits = knownLimits();
  const at = limits.indexOf("A leak can be found and your phone not told");
  const limit = limits.slice(at, limits.indexOf("- **", at + 1));
  for (const must of ["An agent can make the check fail on purpose", 'see "1Password is asked before you are"',
    "not what it would have found there", "the places not yet reached were not searched that day, other agents' included"]) {
    assert.ok(limit.includes(must), `the limit "A leak can be found and your phone not told" does not say: ${must}`);
  }
  assert.ok(limits.includes("- **1Password is asked before you are.**"), "the limit that sentence points to is gone or renamed");
});
