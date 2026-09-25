# PA-01 Stage 2 — capabilities, launches, and attachment evidence

Revision 1, 2026-09-22. READY for user delivery. Assignee: the SAME
DeepSeek/OpenCode session that completed Stage 1. Reviewer: Codex architect.
Stage 1 is accepted in `PA-01-stage-1-review-2.md` (12 passing tests).
This task supplements `docs/provider-architecture.md` revision 2. It pins the
Stage 2 decisions left open there; report any conflict rather than guessing.

## Scope and autonomy

Implement this complete stage, including application integration and tests,
without interim approval for routine design details. Choose internal names,
module boundaries, and helpers; the behavior below is binding. One final
architect review follows. Do not stop after declaring unused contract types.
Resolve ordinary compile/test failures yourself. Raise only a material scope
conflict or a missing integration fact that prevents a correct implementation.

Read AGENTS.md, memory index/gotchas/failed approaches, architecture, Stage 1
acceptance, and this packet. Preserve the existing uncommitted work. Record
starting HEAD/status and baseline `make tangle/check/test/lint` results. Keep
the original Stage 1 packet/report/reviews as history.

Executable source and tests stay in blueprint.md. Allowed chunks: core-model,
prov-mod, both adapters/tests, core-launcher, tui-app, core-main as needed.
New focused chunks/files are allowed with first `path=` fences and module-map
updates. Retain one blueprint and current build tools. No runtime async/plugin
framework, new provider, new config schema, or new dependency unless justified
by a concrete need in the report; prefer the existing stack.

## 1. Capabilities and provider operations

Replace legacy `attach_command` and the server-only `create` contract with:

- Explicit capability metadata: rename, resume, new-session support; whether
  creation applies the requested native title and working directory. Use named
  fields/enums, not positional booleans. Listing remains required.
- A pure resume-plan operation returning a structured launch request or error.
- A create operation accepting name/directory and returning either
  `KnownSession(Session)` or `LaunchToCreate(LaunchRequest)`.
- Provider-owned interpretation of a generic process/window snapshot (§4).

Exact Rust signatures are your choice. Unsupported operation must be an
identifiable error category, distinct from operational failure (a small typed
error compatible with anyhow is sufficient). Capability checks do not replace
the operation's own unsupported result. Validate provider/session identity at
operation boundaries; reject a session belonging to another instance before
performing side effects. Keep SessionKey's validated representation private.

Built-in behavior:

| Provider | New session | Native title applied | Requested cwd applied |
| --- | --- | --- | --- |
| OpenCode | POST through configured shared server, return known session | Yes | No: observed server ignores it |
| Codex | Return plan to launch `codex` in requested cwd | No: title is window label only | Yes |

Both retain rename/resume support. Preserve existing OpenCode HTTP probing,
Codex SQLite naming/fallback, rollout parsing, ancestor labels, and sorting.
Preserve Codex resume target selection (title if present, otherwise UUID); do
not assume an unverified CLI change. Ambiguous title matching is handled below.

## 2. Structured execution

A LaunchRequest contains program, argument vector, optional cwd, and explicit
environment overrides. No executable shell fragment field. Providers do not
call tmux, alter terminal modes, or persist Pinga tracking.

Foreground execution uses Command directly with args/current_dir/envs and
inherited stdio. A child's normal/nonzero exit returns control to Pinga; spawn
failure is an error. Always attempt to restore raw mode, cursor, mouse state,
and repaint after the child returns OR fails to spawn. Surface the launch
error after restoration; do not use `?` to skip cleanup. Preserve the current
alternate-screen behavior rather than redesigning the terminal experience.

At the tmux boundary, centralize safe serialization to POSIX `sh` (invoke it
explicitly, not an assumed user's default shell). Quote every program/argument,
including empty strings; preserve cwd/env semantics and use `exec` so process
inspection sees the real child. Validate env names and reject embedded NUL
instead of generating invalid commands. If string-based serialization cannot
represent a non-UTF-8 OS value, return an explicit error instead of silently
changing it. Prefer a small tested serializer over scattered shell quoting.
Check tmux command status as well as returned window ID. Do not add retries
that can accidentally create multiple windows.

## 3. Application lifecycle and tracking boundary

New-session and resume actions must dispatch generically through Provider,
without provider-name/index checks. Capabilities drive the new row/action,
rename/suggest actions, and forms. Unsupported actions are visibly disabled or
absent and their handlers refuse them. Keep header/selection mapping coherent
when a fake provider cannot create. Creation forms explain unsupported native
title/cwd semantics; do not silently promise those fields will apply.

KnownSession flow: validate the returned provider/key, retain it in the current
snapshot, then obtain/execute its resume plan. If planning or launching fails,
report that the session was created but could not be opened, retaining its
identity. Do not retry creation automatically. A failed create creates no
tracking record. A failed launch creates no successful-window record.

LaunchToCreate flow: maintain an explicit in-memory PendingLaunch with a local
unique token, ProviderId, and the successful tmux window reference. Never put
an empty/fabricated native ID into SessionKey or opened.json. Multiple pending
launches must not overwrite each other. In foreground mode, the pending
lifetime covers the child execution; refresh afterward. No newest-session or
directory-based guessing to discover an ID. Stage 2 may leave launches
unresolved; remove an in-memory pending entry only on confirmed window death,
not on a failed inspection. Make unresolved status visible in a compact status
message/indicator without inventing a session row.

**Deliberate temporary limitation:** pending launches are NOT persisted in this
stage, so they are not recoverable as pending launches after restarting Pinga.
Document this plainly. Stage 3 supplies the versioned persisted format. Do not
add a sidecar registry or alter opened.json's tuple format now. Preserve legacy
empty-ID records without treating them as known sessions; leave their migration
to Stage 3. Known session records keep historical provider positions for now.

Mouse-deferred plans must capture provider identity/key and launch data when
created. Executing one must not use whatever column happens to be focused
later. Preserve mouse-up deferral, cooldown, force-open behavior, grouping,
and startup-only interrupted detection.

## 4. Generic process evidence and explicit adoption policy

Launcher returns windows/panes/processes with real argument boundaries, plus
inspection completeness/errors. On this Linux target, reading NUL-delimited
`/proc/<pid>/cmdline` is suitable; inject its root/reader for fixtures. Do not
split `ps args` on whitespace or match arbitrary substrings. Inspect all panes
and bounded descendants; report truncation/unreadable data as incomplete.
The process collector contains no executable names or provider parsing rules.
Collect current-session candidates for adoption and also inspect tracked
windows explicitly, including those outside the current tmux session.

Adapters interpret executable/argument tokens and native identity. Shell text
such as `sh -c 'codex resume ...'` is not itself proof; inspect the child. An
unrecognized wrapper/option sequence is unknown, not a guessed match. Matching
results carry candidate window IDs and confidence: confirmed, heuristic,
ambiguous, or unknown/no observed match. Unknown is not proof of inactivity.

OpenCode: require its attach syntax, configured server endpoint, and exact
session ID for a confirmed native match. Normalize trailing slashes and
localhost/127.0.0.1 equivalence with matching scheme/port/path, without DNS
lookups or broad host equivalence. Different server endpoints must not match.
ID-less attach plus a uniquely newest session can be a heuristic only.

Codex: exact UUID match is confirmed. A resume title is confirmed only if it
uniquely identifies a session in the current successful provider snapshot;
duplicate/inherited shared titles yield ambiguity. Do not choose the first
matching list entry. Preserve complete arguments containing spaces/quotes.

Core adoption policy (authorized correction to the old heuristic):

1. Prefer a tracked window whose session is still positively identified.
2. Otherwise select/adopt exactly one confirmed candidate.
3. Multiple confirmed candidates, heuristic-only candidates, or ambiguous
   identity: explain uncertainty and refuse automatic adoption/spawn unless
   `f` requests a fresh launch. A heuristic must never select another session
   silently. Thus old OpenCode newest-session auto-adoption becomes a warning.
4. No candidates in a complete snapshot: allow a new launch, respecting the
   existing provider `active` refusal unless forced. Do not claim this proves
   absence in other terminal/tmux sessions.
5. Incomplete inspection with no confirmed candidate: report unavailability
   and refuse a new launch unless forced. Inspection failure is not absence.

Running-group computation and reconciliation use the same adapter evidence,
not separate provider-specific parsers. Deduplicate candidate window IDs.
Heuristic/ambiguous evidence must not mark a specific session as confirmed
running. Retain tracking through unknown/incomplete evidence. Drop a tracked
client only when a complete inspection proves it ended; missing windows at
startup retain the existing interrupted behavior.

Refresh prerequisites: retain a provider's last snapshot on failure, distinguish
failure from successful empty lists, and skip destructive reconciliation for
that provider until a successful snapshot. Keep its first-reconcile eligibility
through failure. Out-of-range legacy provider indices are retained/skipped, not
indexed/panicked or silently removed. These guards are needed for the new
evidence path; they do not authorize a disk format migration.

## 5. Required evidence

Keep Stage 1 coverage, adapting it to the new contract. Add behavioral tests
using fake providers, temp homes, process/window fixtures, and injected runners:

- Capabilities affect handlers/forms; unsupported differs from operation failure.
- Both creation outcomes work through the SAME app path, including multiple
  pending launches. Cross-provider sessions are rejected before side effects.
- Created session survives plan/spawn failure; no duplicate creation on retry,
  no window record on launch failure, no new empty-ID disk records.
- Direct/serialized execution preserve spaces, apostrophes, empty args, Unicode,
  `$()`, backticks, semicolons, cwd, and env; no unintended shell execution.
  Exercise serialization with a harmless local argv/env recorder and POSIX sh.
- Terminal-restoration control flow runs on spawn failure using an injected
  terminal/runner seam; no real interactive terminal needed for automated tests.
- Process fixtures cover all panes, descendants, unreadable/truncated scans,
  executable false positives, exact IDs vs substrings, different OpenCode
  servers, ID-less attach, duplicate Codex titles, and arguments with spaces.
- Adoption policy covers confirmed/heuristic/ambiguous/unknown and force cases.
- Failed refresh/inspection retains records and startup eligibility; successful
  reconciliation distinguishes intentional close and startup interruption.
- A deferred action keeps its original provider after focus changes.
- A third fake adapter can exercise creation/resume/evidence without any new
  core branch. Production still has the existing two columns and default order.

No live provider writes, real Codex home reads in tests, real tmux manipulation,
service restart, installation, or agent messaging. Keep fixtures offline;
tests must meaningfully exercise orchestration, not just construct enums.

Run `make tangle`, `make check`, `make test`, `make lint`, `git diff --check`;
compare hashes of ALL generated files across a second tangle (src is ignored
by Git). Record test counts/results and actual limitations. Inspect executable
chunks for remaining provider-specific lifecycle/evidence branches: only
adapter/composition code may know those semantics. Fixed labels/colors/columns
and legacy index mapping remain explicitly allowed until Stage 3.

## Delivery

Write `docs/handoffs/PA-01-stage-2-report.md`: baseline, changed chunks,
contract choices, requirement-to-test mapping, gate results, authorized behavior
changes (especially heuristic refusal and pending persistence), unresolved
limitations, and useful reviewer entry points. Log significant work/quirks in
project memory. Keep this task unchanged; record proposals in the report.

Do not commit the mixed working tree or deploy. Stop once this complete stage
is ready for review. Stage 3 (generic views/config and tracking migration), Pi,
Antigravity, messaging research, and unrelated bugs remain out of scope.
