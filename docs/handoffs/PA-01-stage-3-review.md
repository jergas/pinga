# PA-01 Stage 3 — first review / consolidated corrections

2026-09-22. CHANGES REQUESTED. Same DeepSeek/OpenCode session, High.
Complete all groups below in one batch, then return for review. No Stage 4,
deployment, live migration, or provider/tmux mutations. Preserve prior work.

Baseline gates pass (63 tests) but acceptance requirements are not met. This
review follows actual call paths, not test names/report claims. Architect has
directly fixed three small rendering defects in blueprint: provider-name color
branch replaced by positional palette; each column's new-row capability comes
from its own provider; modal title/cwd notes come from capabilities. A new real
TestBackend regression covers the modal for an arbitrary fake provider.
Preserve those fixes. Larger corrections remain implementer's work.

## R1 / P1 — exact, recoverable migration snapshot

`ensure_initialized` drops opened.lock after parsing legacy, then rereads the
file for backup. An old writer can change it between reads: migrated records
and backup no longer represent the same snapshot. Read raw bytes ONCE under
both locks, parse those bytes, back up those bytes and derive v2 from them.
Keep the prescribed lock ordering. No second unlocked read.

`write_exact_once` silently accepts ANY existing backup. A conflicting/truncated
backup must abort without committing v2; identical bytes permit retry. Make
backup creation durable and recoverable (temp+sync+atomic publication), not a
plain possibly partial write followed by unconditional existence acceptance.
Sync directory metadata after atomic publication where required on this Linux
target; report errors honestly. Never overwrite a conflicting backup.

Add deterministic migration race/backup conflict/identical retry/write-failure
fixtures, proving both original data and exact backup survive. All temp dirs.

## R2 / P1 — validate persisted invariants and surface read errors

Derived Deserialize on ProviderId bypasses its constructor. `read_v2` validates
only the version: invalid provider IDs, empty Known native IDs, zero/duplicate
record IDs, and next_id colliding with existing IDs are accepted. Validate on
decode and before commit; constructor invariants must also hold after serde.
Require unique nonzero committed IDs and next_id greater than every committed
ID, with overflow handling. Preserve opaque legacy tuples. Invalid envelopes
must not be rewritten. Add corruption tests for each invariant.

FileTrackingStore::read returns Ok(cache) on parse/version/read errors, hiding
the error. Retain last-good state in the APP while surfacing the store failure;
use Result or an explicit stale+error result. App::with must not quietly turn a
failed read into an empty registry either. In-memory test stores must allocate
IDs and perform atomic updates like the real store; current MemStore leaves all
new IDs at zero and clones/unlocks before mutation, masking identity races.

## R3 / P1 — reconcile observed records outside the shared lock

`reconcile` collects evidence from self.records, then iterates EVERY record
reread by store.update, including concurrent additions/replacements never
inspected. An added session absent from the old list can be deleted immediately.
The current stale_update test manually changes a record through a closure;
it does not test application reconciliation or replacement protection.

Read a snapshot; collect listing/liveness/process evidence and proposed changes
OUTSIDE the lock; under lock apply changes only if the exact observed record
ID AND its prior window/state/identity still match. Never inspect tmux or invoke
provider matchers inside store.update (currently both run while flock is held).
New/replaced records must survive stale evidence. Test actual app reconciliation
with another store adding/replacing records between inspection and commit.

Startup eligibility must include stable record ID (currently only provider,
session,window). Do not consume eligibility or publish removal notices when
the transaction fails; `still`/`gone` are currently applied regardless of commit.
Test failed commit -> recovery -> dead initial window and replacement with the
same provider/session/window but new record ID.

Pending records currently check liveness and can be deleted even if their
provider is disabled/unavailable. Preserve them untouched until that provider
has a successful snapshot, as assigned. Pending resolution requires complete
enough evidence to establish uniqueness, not merely one Confirmed candidate
in a partial scan that could conceal another session. Add ambiguous/incomplete/
disabled/failed-list/dead-window sequence tests across restart.

## R4 / P1 — per-instance sources must govern execution and identity

Codex's configured home only affects listing/storage. Both launch plans still
have empty env and run plain codex, so a nondefault instance launches against
the ambient home. Wire the configured home into create AND resume through the
actual supported harness interface; verify using installed local help/docs or
source (read-only), rather than guessing. Reject unrepresentable paths explicitly.

Codex process matches also cannot distinguish two homes with identical native
IDs or titles. Add source discrimination or conservatively return Unknown
where the instance cannot be established. Generic evidence may carry narrowly
selected source metadata; do not collect/log full process environments or
secrets. Preserve adapter-owned interpretation. Tests need TWO REAL Codex
adapters with different temporary homes, not two different provider types,
and must show correct launch source plus no cross-instance confirmed adoption.
The config test named two_instances_of_one_type currently uses OpenCode+Codex.

## R5 / P2 — selection, scrolling and launch failure behavior

Refresh only clamps sel; it does not preserve SessionKey. Capture selected
identity before replacing/grouping the list and restore its selectable index
after refresh/reconciliation, preserving the new-session row and using a bounded
fallback on removal. Test actual list reorder and interrupted-group transitions.
The existing per_provider_failure_is_local_and_selection_survives_reorder test
has neither failure nor reorder nor selection assertions; replace it.

Keep per-view list scroll offsets and use them in mouse hit testing: rendering
creates a fresh ListState which auto-scrolls to selection, while clicks map
screen rows against the full list starting at zero. Test a long scrolled list
and clicking its visible rows, plus third-provider viewport and narrow/zero sizes.

spawn_launch uses `?` on recording after window creation and loses the
created-window context. On record failure report the launched window ID and
that tracking failed; do not imply no launch occurred. Keep enough local state
to prevent a blind retry from creating another window. Foreground launch-to-
create must return failure honestly, not stash error and return Ok. Add actual
application failure tests, including combined terminal cleanup errors.

## R6 / P2 — configuration/startup errors and validation coverage

Config::load treats ALL read errors at the default path as absent config.
Only NotFound permits defaults; permission/read errors must fail. Avoid
echoing raw TOML source lines containing secrets in parse diagnostics.
Validate/build the provider registry before entering raw/alternate-screen mode
(currently App::new builds it afterwards). Use injectable loading/environment
inputs or isolated subprocess tests; do not mutate real user config/environment
concurrently. Test actual loading, explicit-vs-absent env precedence, unknown
options, malformed/unreadable config, disabled validation and factory dispatch.

## R7 / P2 — restore regression coverage and audit the report

Stage 2 had 23 app tests; the submission replaces them with 8, despite the
explicit requirement to retain regression coverage. Restore their BEHAVIORAL
coverage against generic APIs: capability guards before side effects, partial
suspend failure, launch/restore failures, creation retention through delayed
listing and retry, wrong-window/unknown evidence, exact startup transitions,
real OpenCode malformed evidence integration, distinct pending windows.
Do not merely copy names or assert that fixtures exist.

Test remaining assigned scenarios at their real boundaries, especially
disable/re-enable/reorder, failed IO/lock, unsupported record variants, pending
ambiguity, third-provider unsupported actions and factory options wiring.
Remove test compiler warnings; run cargo clippy --all-targets -- -D warnings
in addition to make tangle/check/test/lint, whitespace and repeat fidelity.

Update blueprint prose and report with an honest requirement-to-test map.
Explicitly distinguish snapshot seeding, real adapter interpretation, actual
file-store concurrency and live tests (none). Update memory's obsolete tracking
notes to label legacy behavior and describe v2. Report submitted, not accepted.
Previous review packets are immutable. Return when the whole batch passes.
