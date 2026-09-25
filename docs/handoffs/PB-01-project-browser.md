# PB-01 / revision 1 — external project browser

2026-09-24. User accepted external browsing with same-window viewers; latest
Astra remaining limits 30% weekly / 85% five-hour. Architect owns scope/review;
DeepSeek High owns this complete bounded implementation. Provider work paused.

Builder: OpenCode ses_f317e9fbeffe9uLy8WUt4vc05Z, verified title test-messaging,
provider opencode-go, model deepseek-v4-flash, variant high. Its session directory
is /home/edgar: explicitly work in /home/edgar/Projects/pinga, not yatagarasu.
Read AGENTS and memory index/gotchas/failed approaches. Preserve ALL uncommitted
provider work. Change blueprint chunks and adjacent prose, then tangle.

## Accepted product scope

`b` opens a Browse project directory form (advertise in help). Prefill with the
selected session's existing local absolute directory when valid; otherwise
Pinga's current directory. Allow editing before launch, Enter confirms, Esc
cancels without effects. This is directory selection, not Git-root inference:
don't silently climb to an ancestor. Relative user input resolves against the
current Pinga cwd; support literal paths without shell/variable expansion.
Validate existence, directory type and representation; explain invalid input
without losing edits. Works with zero providers, no selection, unavailable
provider or missing session directory. Browsing never calls provider operations.

Launch external Yazi rooted there: new tmux window in tmux, foreground with
Pinga suspend/restore otherwise. Reuse structured LaunchRequest/execution seams;
browser windows never enter session tracking or pending-creation reconciliation.
Cancel/failure leaves Pinga usable; failed terminal preparation never launches,
and restoration/repaint run after foreground return or errors.

Markdown opens through Glow in pager mode; text/code through bat with paging,
in the SAME explorer window, blocking until viewer exits back to Yazi. No
automatic new viewer windows. No custom renderer, embedded pane, knowledge
sync, Mnemosyne installer changes, or unrelated provider fixes.

## Tools, configuration and boundaries

Use FOSS tools, documenting exact licenses from upstream: Yazi, Glow, bat.
The user prefers copyleft but permits permissive licenses. Don't make blanket
GPL-compatibility or Markdown-compliance claims. Sources to verify:
https://yazi-rs.github.io/docs/configuration/yazi/
https://github.com/sxyazi/yazi
https://github.com/charmbracelet/glow
https://github.com/sharkdp/bat

Yazi currently documents `%s` argument placeholders and blocking openers;
verify against the actual supported version, not remembered older syntax.
Record supported/tested versions and fallback/error behavior. Only bat was
found on PATH during architect inspection; do not claim a real Yazi/Glow smoke
test without obtaining/testing them. No system install or global config writes
in this batch: provide concrete dependency installation instructions for review.

Keep the integration profile owned by Pinga, isolated from the user's Yazi,
Glow and bat configuration. It must work from an installed Pinga executable,
not depend on repo cwd or hardcoded checkout paths. Embedded/generated assets
and a private helper mode are acceptable; manage profile lifetime through tmux
launch and viewer return. Do not leave tmux referring to deleted temp files.
No system-wide/editor defaults or shell command templates in user input.

Check missing executables early and display actionable names. Openers must
preserve file argument boundaries (spaces, quotes, dollar signs, leading '-'
and Unicode); no shell interpolation of user paths. Verify pager flags/quoting
with real tool help or primary docs. Unsupported/binary file handling should be
clear rather than executing a file or routing it to an arbitrary default app.
Yazi is writable: document that this is a normal file manager, NOT a read-only
sandbox. The initial chosen directory is not a filesystem confinement boundary.

## Evidence, workflow and delivery

Write regression tests against actual form/action/helper orchestration:
- Default/edited roots, invalid/missing cwd, zero providers, cancellation.
- tmux versus foreground launch; failure/cleanup, no tracking writes or provider
  calls; filenames with hostile shell characters arrive intact.
- Isolated profile, correct Markdown vs code opener, missing dependencies;
  profile/helper lifetime across deferred execution. Test installed-path use.
- Preserve existing provider tests; don't replace scenarios with weaker names.

Use fixtures/recording launchers for automated checks; never modify real user
files or open live interactive windows unattended. Repo-local tooling for
testing is fine if available without installation; otherwise explicitly record
that real-tool validation is pending. Do not install packages, deploy, commit,
or alter live configurations. Routine implementation factoring is delegated.

Run make tangle/check/test/lint, cargo clippy --all-targets -- -D warnings,
repeat-tangle fidelity, git diff --check. Return docs/handoffs/PB-01-report.md
with requirement-to-test mapping, actual checks/versions/licenses, manual test
instructions and limitations. Update project memory log.

Communicate via the already verified native channel, not through the user.
Reply to architect thread 01a0cb2e-e31c-7e33-8094-ac926ac14b53 with assignment
PB-01/1 correlation, concise acknowledgement and final report pointer. Reuse
the established Codex queue return route; do not assume the Yatagarasu bridge
has passed live acceptance. Ask only genuine blockers. Stop after this batch
for independent architect review; don't treat green checks as acceptance.
