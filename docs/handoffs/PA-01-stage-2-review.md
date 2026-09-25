# PA-01 Stage 2 — architect review and consolidated correction task

Revision 1, 2026-09-22. Verdict: CHANGES REQUESTED; Stage 3 remains unassigned.
Assignee: same DeepSeek/OpenCode session. Complete all corrections together,
with one final re-review. Original Stage 2 scope and exclusions still apply.

## Verified baseline

Architect inspected contracts, application lifecycle/reconciliation, adapters,
and launcher code. Independent `make check`, `make test` (25 passed),
`make lint`, and `git diff --check` passed. Generated files matched the blueprint
and two tangles were byte-identical. Passing tests do not establish the missing
application/process-collector behavior. No implementation changes by architect.

## R1 / P1 — live window is incorrectly treated as proof of session identity

`core-launcher::decide_open` immediately selects any tracked window marked
alive, without checking that this window has Confirmed evidence for the target
session. A window left at a shell or reused for another client can therefore be
selected as the requested conversation. The current adoption test explicitly
expects selecting tracked `@0` when only `@1` is confirmed; it codifies the bug.

Require positive identity evidence for the tracked window. Liveness alone is
insufficient. Preserve the original policy for one confirmed candidate,
ambiguity, and force; deduplicate window IDs. Add regression cases for a live
but unrelated tracked window, confirmed elsewhere, incomplete evidence, and
ambiguous tracked identity. Do not silently prefer the old window.

## R2 / P1 — failed or ambiguous inspection can erase tracking

Several paths contradict the explicit retention contract:

- `TmuxCli::window_alive/list_window_ids/pane_root_pids` ignore command exit
  status; a failed tmux command with empty stdout becomes dead/empty evidence.
- `App::compute_interrupted` uses `window_alive(...).unwrap_or(false)`, so even
  a correctly returned inspection error becomes a dead window. After startup,
  that removes the record.
- An Ambiguous/Heuristic match in a complete process snapshot is treated as
  not running and its record is removed. Complete collection does not turn
  uncertain identity into proof of absence.
- Startup eligibility is consumed after a successful provider list even when
  window/process inspection failed. A later dead-window observation can then
  be misclassified as an intentional close rather than interruption.

Check subprocess statuses and malformed output; preserve errors as unknown.
Keep records on failed/ambiguous/heuristic identity inspection. Consume startup
eligibility only when the relevant initial reconciliation was actually
possible. Use per-window/record eligibility if one unknown window would
otherwise consume another record's startup classification. Preserve the
legacy disk tuple format; these can be in-memory states/pure helpers.

Add application-level fixtures for each failure, recovery after failure,
startup interruption, intentional close, legacy unknown indices/empty IDs,
and pending-launch retention. Do not write real opened.json in these tests.

## R3 / P1 — process evidence is not reliably bounded or interpreted

- `ProcFs::tree` stops at max_depth without checking whether deeper descendants
  exist, leaving `complete=true`. It can miss the actual client and certify a
  false absence. Mark truncated inspection incomplete.
- `read_cmdline` skips ALL empty tokens, shifting real argument positions;
  remove only the terminating delimiter and preserve empty arguments.
- Both adapters require argv[0] to equal the bare program name. A native argv
  using `/path/to/codex` or `/path/to/opencode` is silently missed. Recognize
  exact executable basenames appropriately, never substring matches or shell
  command text as proof.
- Unknown option/wrapper forms cannot currently be distinguished from known
  absence in the adapter result. Preserve unknown interpretation explicitly
  rather than using an empty candidate list as evidence the client ended.
- OpenCode endpoint normalization lowercases the ENTIRE URL (including
  case-sensitive paths) and replaces the `localhost` prefix without an authority
  boundary. Distinct paths such as `/A` and `/a`, or hosts `localhost.example`
  and `127.0.0.1.example`, can be conflated. Normalize scheme/host only, match
  exact authority host for loopback aliases, and preserve path/query semantics.
- Codex title uniqueness must use a successful current provider snapshot, not
  stale retained data after a list failure; do not confirm a stale title match.

Add fixtures that exercise the REAL collector logic through injected proc
filesystem/reader and tmux results, not only hand-constructed final evidence.
Cover all panes, bounded descendants, empty arguments, absolute executable
paths, truncated/unreadable data, unknown syntax, case-sensitive URL paths,
host-prefix lookalikes, stale snapshots, and duplicate titles.

## R4 / P2 — actual execution boundary is less safe than its unit test

`open_in_tmux` passes the serialized POSIX fragment as tmux's single command
string. It never explicitly invokes POSIX sh, so tmux interprets it through
the user's configured default shell. The test invokes `sh -c` directly and
therefore does not test the actual boundary. Use an explicit argv launch of
POSIX sh through tmux's multi-argument command interface (or an equivalently
verified mechanism); preserve argument boundaries and avoid a second assumed
shell. Assert the actual tmux invocation through a fake command runner.

`serialize_launch` rejects NUL only in env fields, not program/args/cwd. Apply
shared request validation to both foreground and tmux execution, including env
names and all NUL-bearing fields. Reject non-UTF-8 cwd conversion explicitly
instead of `to_string_lossy` when constructing a launch from current_dir.

The actual `suspend_for` can return after disabling raw mode if the following
terminal operation fails. Restoration errors are then ignored. Its tested
`run_guarded` receives an empty closure, so the test proves a callback executes,
not that the real restoration path works. Put the real suspend/run/restore
sequence behind an injectable terminal seam; always attempt required cleanup
after partial suspension as well as child/spawn failure, and surface meaningful
restoration errors without losing the launch error. Restore cursor/mouse/raw
state and repaint. Test that production orchestration, not a substitute closure.

Also refresh after foreground return in both creation/resume paths; current
paths dropped the immediate refresh. Test with a fake foreground runner.

## R5 / P2 — application requirements and acceptance tests are incomplete

- Only new_session.supported is checked. Rename/suggest/resume handlers and UI
  do not honor all capabilities. The new row still looks enabled for an
  unsupported provider. Forms do not explain applies_title/applies_cwd.
- Pending launches are stored but never surfaced in rendered status; the
  required visible unresolved state is missing. Pending records also carry
  only a provider index rather than the specified stable ProviderId.
- KnownSession checks provider ownership but not the required nonempty native
  key before it can reach tracking. Construct/validate SessionKey at this
  boundary and retain the created identity across plan/spawn failure.
- Report acknowledges no application tests for creation outcomes, multiple
  pendings, deferred focus changes, or reconciliation. These were required,
  not optional manual smoke tests. Registering a third fake alone does not
  demonstrate that it can use the full lifecycle/evidence path.

Introduce injectable application construction, tracking storage, launcher,
and terminal dependencies (or extract testable orchestration/state helpers).
Keep production defaults unchanged and storage format unchanged. Test both
creation outcomes, plan/spawn failure retaining a known session without another
create call, no record on failed launch, multiple pending IDs, visible pending
status, capability-driven forms/handlers/selection, and deferred execution
after focus change. A fake third provider must exercise the same lifecycle
logic without adding a third production column or special-case dispatch.

The explanation that App currently uses live state is a reason to inject that
dependency, not a reason to waive the task's tests. You are authorized to make
that bounded testability refactor and any contract refinement needed to retain
unknown evidence; this does not authorize Stage 3 UI/config/schema changes.

## Delivery and autonomy

Fix R1–R5 as one batch. Internal factoring and typed evidence/error structures
are your decision; preserve the policies above. Review the affected flow end
to end for the same classes of mistakes, rather than only patching listed lines.
Add regression tests that fail against the current behavior before fixing it
where practical. Run all original gates and repeat-tangle hashes. Update
`PA-01-stage-2-report.md` with R1–R5 resolution, actual requirement-to-test
mapping, results, and remaining limitations. Append the project log.

All executable changes/tests stay in blueprint.md. Keep this review immutable.
No installation, live provider writes, commit, new agent messaging, or Stage 3.
Stop only when the whole correction batch meets the Stage 2 contract, or report
a genuine unresolved blocker. The user will request architect re-review.
