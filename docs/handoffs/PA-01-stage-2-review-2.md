# PA-01 Stage 2 — second review / remaining corrections

2026-09-22. Verdict: CHANGES REQUESTED. This narrows the remaining work after
`PA-01-stage-2-review.md`; resolved fixes should be preserved. Same DeepSeek
session, one correction batch, no Stage 3 or deployment.

Independent checks passed: check, 44 tests, lint, whitespace, generated-source
fidelity, and repeat-tangle hashes. Positive tracked-window identification,
explicit sh invocation, NUL validation, ID validation, dependency injection,
and much of the capability/evidence work are improved. Remaining findings:

## A / P1 — startup eligibility transitions remain incorrect

In `tui-app::compute_interrupted`:

1. `still_eligible.push(...)` executes on provider failure, unknown liveness,
   and ambiguous/incomplete identity without checking the record's existing
   `eligible` value. A newly opened record can therefore acquire startup
   eligibility after a transient failure and later be falsely classified as
   interrupted. Preserve membership; never grant it to a later record.
2. When evidence collection fails entirely, `(None, _) => (true, false)` retains
   the record but consumes its startup eligibility. Unknown evidence must keep
   existing eligibility, not pretend successful confirmation.
3. The startup key omits the window ID. A replacement window for the same
   provider/session must not inherit the old record's unresolved startup state.
   Keep startup identity tied to the actual initial record/window.

Add sequence tests (not just one-call assertions): empty startup -> later open
-> failed list/inspection -> close; initial record -> collection error with
successful liveness -> later dead window; initial unresolved record -> window
replacement. Confirm intentional closes stay intentional and initial unknowns
retain their original classification. Do not change the persisted tuple format.

Architect reproduced case 1 with a failing unit test in a temporary copy of
the source; the production checkout was not edited.

## B / P1 — unrecognized native command syntax still becomes absence

Both adapter matchers ignore their executable when the subcommand is not
exactly argv[1]. A form with an unrecognized leading option, e.g. the synthetic
`["codex", "--unknown-option", "resume", "id"]`, yields no candidate. This
does NOT prove absence; it is precisely the unknown-form case required by the
task. OpenCode with a dangling `-s` also yields no candidate. Conversely, the
parsers accept recognized prefixes without validating conflicting/trailing
arguments. Do not claim complete syntax knowledge from a partial prefix.

Define a small explicit grammar for supported forms; executable recognized but
syntax not understood => ambiguous/unknown. Only positively understood forms
may establish another session/server or a non-client command. No speculative
upstream CLI expansion is needed. Test leading/trailing unknown options,
dangling/duplicate/conflicting session flags, complete supported forms, and
reconciliation preserving records on these unknown results.

OpenCode URL parsing still separates authority only at `/`; a root URL with
`?Token=A` makes the query part of the lowercased host, conflating query case.
Preserve query bytes and pin/test trailing-slash equivalence for non-root paths
as required by the original packet. Use parsed URL components or a strictly
validated bounded parser; do not silently reinterpret unsupported URL forms.

## C / P2 — finish real application failure/capability coverage

The report claims app-level spawn-failure and foreground restoration tests,
but `make_app` hardcodes `FakeForeground { err: false }` and a terminal with
both error flags false. The restoration test still calls the obsolete
`run_guarded` helper, whereas production uses `App::suspend_for`. No test calls
that application method through the claimed error cases. Add tests against the
actual orchestration, with configurable recording fakes:

- Partial suspend failure: attempt restoration, do NOT launch a client after
  terminal preparation failed. Current suspend_for still launches it.
- Spawn failure, restore failure, combined failures: cleanup ordering and error
  visibility; foreground refresh on normal return and error.
- Created known session followed by foreground failure: retain its identity
  and report created-but-not-opened. Current open_session swallows the launch
  error into self.error and returns Ok, so the outer creation context is lost.
  Make the result distinguish opened/refused/failed rather than reporting every
  non-error control return as an opened session. No automatic re-create.
- Failed tmux spawn: no successful tracking record. Multiple pending windows
  must have distinct fake window IDs, not every fake launch returning `@10`.
- `capabilities().resume == false`: handler refuses BEFORE asking the adapter
  for a plan or launching; current open_session does not check this flag.
- New-session current_dir failure/non-UTF-8: explicit error, not the current
  `.ok().and_then(...).unwrap_or_default()` empty-directory fallback.

The injected application currently accepts one fake provider but its refresh
still assumes two. Construct a valid two-slot transitional fixture for tests
that exercise refresh/foreground return; Stage 3 generalization is not needed.

Update the report to name only tests actually executed on the relevant
production paths. The report's claims of rejected non-UTF-8 cwd and tested
spawn failures are not true of the current code/test wiring. Clearly separate
fixture assertions from untested behavior.

## Delivery

Write regression tests from these expected transitions before adjusting code.
Audit the original Stage 2 requirements against actual call sites and tests;
do not infer coverage from having a seam/type or a similarly named helper.
Implement all A–C through blueprint chunks/prose, run all gates and repeat
tangle, update Stage 2 report with an A–C evidence table, and append memory log.
Keep review files immutable. Routine factoring is delegated; no new approval
round is needed. Return for one architect re-review when the full batch passes.
