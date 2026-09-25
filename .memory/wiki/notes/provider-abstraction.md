# Provider abstraction and implementation handoff

User pause (2026-09-23): suspend provider/Antigravity development and move to
agent message passing. Live smoke PASSED: first message persists conversation;
automatic listing; exact-ID resume preserves history; reopening resumed client
selects existing window. LIMITS: original plain-agy launch remains ambiguous,
and requested name labels tmux window rather than native conversation.
No further provider work until resumed. Recommend a fresh session and separate
message-passing project; evaluate existing mailbox tools before custom glue.
This is a recommendation, not an accepted transport/component decision.

Latest (2026-09-23): final candidate READY FOR USER-CONTROLLED SMOKE TEST,
not live-functionality verified/deployed. See docs/handoffs/PA-01-manual-test-ready.md
and docs/antigravity-smoke.toml (isolated temporary Pinga tracking). Shared-layout,
explicit token retry, process-source and real adapter/app fixtures now reviewed.
Architect wired p to retry oldest pending token, exposed its status, covered
keyboard path, and bounded timestamp conversion. No live client was launched.
Plain agy creation can remain unresolved pending; exact-ID resume should confirm.
Prior CHANGES REQUESTED packets are historical; next step is supervised runtime
validation, not another broad implementation batch.

Latest review (2026-09-23): optional Antigravity/agy adapter exists, but Stage 3
and prototype remain CHANGES REQUESTED. Active packet:
`docs/handoffs/PA-01-antigravity-review.md`. Architect fixed source env collection,
read-only SQLite opening, and row-error propagation; added malformed-row test.
Remaining: scroll layout, explicit pending retry token, actual interleaving tests,
workspace URI/time parsing and credible harness evidence/integrated tests.
DeepSeek report says agy initialized; attribution/authorization not established
in this conversation. No further live mutation authorized. Same High session.
This supersedes earlier status; no deployment or live functionality acceptance.

Latest (2026-09-22): Stage 3 still needs closure; 78 tests/strict lint and
fidelity pass. Active combined packet:
`docs/handoffs/PA-01-stage-3-review-3-antigravity.md`. Finish actual-height layout,
correct known/pending retry identity and real interleaving coverage; then perform
Antigravity read-only reconnaissance and optional fixture-tested adapter if
verified interfaces fit. No live mutation/deployment; no Pi. Same High session.
User prioritizes Antigravity testing and frugality (remaining 63%, 18%).
Earlier statements that all Stage 4 work is unassigned are superseded only by
this bounded Antigravity spike. Stage 3 acceptance remains pending.

Latest review (2026-09-22): Stage 3 still CHANGES REQUESTED. Active packet
`docs/handoffs/PA-01-stage-3-review-2.md` (A–D), same High session. Baseline
74 tests/gates pass; single-snapshot migration and conditional update improved.
Remaining: records read after provider lists still race, launched-but-unrecorded
retry state missing, scrolling/group selection inconsistent, MemStore not atomic
or monotonic, required behavioral tests still missing. Architect directly fixed
directory sync error propagation, missing Codex source -> Unknown, zero-provider
Up/Down panic, and new-session-row selection on refresh; added regression checks.
No live state changes/deployment/Stage 4. Quota 66%, 36%. Earlier status historical.

Latest review (2026-09-22): Stage 3 CHANGES REQUESTED. Active packet:
`docs/handoffs/PA-01-stage-3-review.md` (R1–R7), same DeepSeek/OpenCode on High.
Baseline 63 tests/gates passed but migration snapshot/backup, persisted validation,
stale reconciliation, source-specific Codex launching and UI selection remain
incorrect. Most Stage 2 app regressions were removed; report overstates tests.
Architect fixed three small generic capability/rendering issues through blueprint
and added a TestBackend test; now 64 tests pass. Preserve those fixes.
No live migration/deployment or Stage 4. Remaining quota 69%, 53%.
This supersedes older status below.

Current status (2026-09-22): Stage 2 ACCEPTED after 62 tests and all gates,
including repeat-tangle fidelity. Verdict: PA-01-stage-2-review-5.md.
Stage 3 READY: docs/handoffs/PA-01-stage-3.md revision 1; architecture revision 3.
Same DeepSeek/OpenCode session, High recommended. Full batch covers factories/
explicit provider config, generic views, stable versioned tracking and migration.
Separate tracking-v2.json avoids incompatible old writes; one-time locked legacy
snapshot with exact backup, no legacy dual writes/reimport, no cross-version
convergence. All migration tests isolated; no live deployment. Pi/Antigravity
and message transport remain unassigned. This supersedes historical entries.
Remaining quota reported 70%, 61%.

Latest review (2026-09-22): Stage 2 CHANGES REQUESTED; 60 tests and gates pass.
Active packet: `docs/handoffs/PA-01-stage-2-review-4.md`. Creation retention
accepted; endpoint parser still maps malformed hosts/ports/schemes to Different.
Four standalone probes reproduced it. Packet pins a conservative supported URL
subset and requires actual adapter-to-app reconciliation coverage. Same DeepSeek
session; recommend High reasoning based on repeated example-specific fixes.
Stage 3 unassigned. Quota remaining: 71%, 65%. Earlier status is historical.

Latest review (2026-09-22): Stage 2 CHANGES REQUESTED; 56 tests and all gates
pass. Active packet: `docs/handoffs/PA-01-stage-2-review-3.md` (D/E).
Fix endpoint-parser Unicode panic and unknown-to-absence conversion; retain
created identities independently until first observed in provider listings.
Earlier A–C fixes improved. Same DeepSeek/OpenCode session; Stage 3 unassigned.
This entry supersedes historical status below. Remaining quota: 72%, 77%.

Latest re-review (2026-09-22): Stage 2 still CHANGES REQUESTED, 44 tests/gates
pass. Active correction packet is `docs/handoffs/PA-01-stage-2-review-2.md`
(A–C): preserve exact startup eligibility transitions, represent unrecognized
CLI forms as unknown, and finish actual application failure/capability tests.
Several first-review fixes are resolved. Same DeepSeek session, no Stage 3.
This paragraph supersedes earlier status entries below. Quota remaining most
recently reported: weekly 76%, five-hour 100%; remain economical.

Latest status (2026-09-22): Stage 2 CHANGES REQUESTED. Active correction packet:
`docs/handoffs/PA-01-stage-2-review.md` revision 1, R1–R5, same DeepSeek session,
one complete correction batch. Independent gates passed (25 tests), but review
found wrong-window selection, destructive unknown-evidence handling, process
parser/completeness faults, execution-boundary gaps, and missing app acceptance
coverage. Authorize bounded dependency injection to test actual orchestration.
Stage 3 remains unassigned; do not treat implementer COMPLETE as acceptance.
User reports remaining quota weekly 78%, five-hour 15%; keep architect work
focused. Earlier status paragraphs below are historical.

Current status (2026-09-22): Stage 1 ACCEPTED; Stage 2 packet READY for delivery
to the same DeepSeek/OpenCode session. Stage 1 verdict:
`docs/handoffs/PA-01-stage-1-review-2.md` (12 passing tests).
Active task: `docs/handoffs/PA-01-stage-2.md`, revision 1, with report template
`docs/handoffs/PA-01-stage-2-report.md`; architecture is now revision 2.
Earlier readiness/review sections below are historical.

Stage 2 assigns full capability/launch/creation/evidence integration with one
final review. Explicit decisions: heuristic-only attachment refuses automatic
adoption (force may open fresh); unknown IDs remain in-memory pending launches
without fabricated persisted IDs; failed inspection/refresh retains tracking.
Pending persistence, generic views/config, and state-format migration remain
Stage 3. User requested larger implementation batches and frugal architect
usage (reported remaining quota: weekly 80%, five-hour 26%).

2026-09-22. User accepted compiled-in provider registration and a semi-manual
handoff to DeepSeek running in OpenCode. Codex owns architecture/review.
Recommend a fresh OpenCode session so the current specification is not mixed
with obsolete conversational assumptions from earlier implementation work.

Canonical files in `/home/edgar/Projects/pinga`:

- `docs/provider-architecture.md`: PA-01 revision 2, target design and stages.
- `docs/handoffs/PA-01-stage-2.md`: revision 1, current implementation task.
- `docs/handoffs/PA-01-stage-1.md`: revision 1, completed historical assignment.
- `docs/handoffs/PA-01-stage-1-report.md`: completion-report template; initially
  NOT STARTED, not evidence of implementation.

Stage 1 introduces stable provider/session identity, a trait-object registry,
and built-in composition while preserving two-provider UI/runtime behavior.
Launch lifecycle, provider-neutral attachment evidence, generic views/config,
and persisted-state migration require subsequent reviewed tasks. No Pi or
Antigravity adapter is assigned yet.

Keep `blueprint.md` as literate executable source; implement named chunks and
their prose together, then tangle/check/test/lint and verify repeat tangling.
Only one implementation writer works in the shared checkout. Prior doc fixes
and handoff files are intentional uncommitted input. The user delivers a short
kickoff pointer; the implementer writes a repo report; the architect reviews
the actual diff. Mnemosyne supplies context/pointers, not live task delivery.
Research/installation of cross-agent messaging is deferred.

## Stage 1 review, 2026-09-22

Implementation is present but not yet accepted. Architect independently ran
check/test/lint (11 passing tests), verified generated-source fidelity and
repeat-tangle identity, and inspected the executable diff. Review and bounded
correction instructions: `docs/handoffs/PA-01-stage-1-review.md`, revision 1.
R1: private SessionKey representation to enforce the nonempty-ID invariant.
R2: complete assigned config-wiring and dispatch/non-replacement test evidence.
Use the same DeepSeek implementation conversation for corrections. Stage 2
remains unassigned. The implementation report's COMPLETE status is the
implementer's submission, not architect acceptance.

## Stage 1 status (implemented 2026-09-22, ready for architect review)

Stage 1 landed via the blueprint (see log 2026-09-22 IMPL): `ProviderId`,
`SessionKey`, `Session.provider_id`, `ProviderDescriptor`, `ProviderRegistry`,
and a `builtin_registry` composition function. `ProviderKind`/`AnyProvider`
removed; trait `kind()` became `descriptor()`. The app routes through the
registry by the transitional two-provider index and propagates the now-fallible
`App::new` through the existing terminal-cleanup path. 11 automated tests pass
against fake adapters and temp fixtures (no live server/home). A three-provider
UI and all later stages remain separate reviewed tasks.

## Stage 3 status (implemented 2026-09-22, ready for architect review)

Stage 3 landed via the blueprint (see log 2026-09-22 IMPL): optional ordered
`[[providers]]` config with compiled-in type-key factories (explicit providers
authoritative; legacy defaults/env preserved when absent), a versioned
`tracking-v2.json` store with one-shot legacy migration + exact-bytes backup,
per-provider app view state with a ≤2-column viewport, persisted pending
launches resolved only on unique confirmed evidence, and interruption retained
across polls. `ProviderDescriptor.display_name` is now an owned String. 63 tests
pass. Report: docs/handoffs/PA-01-stage-3-report.md. No live migration performed;
Stage 4 (Pi/Antigravity reconnaissance) is unassigned.

## Stage 2 status (implemented 2026-09-22, ready for architect review)

Stage 2 landed via the blueprint (see log 2026-09-22 IMPL): capabilities,
structured `LaunchRequest`s, explicit `CreateOutcome` (KnownSession |
LaunchToCreate), typed `Unsupported`, cross-provider identity checks, and
provider-owned `ProcessEvidence` → `WindowMatch` interpretation. The launcher
gained injectable ProcReader/Tmux/Foreground seams, a POSIX-sh `exec`
serializer, and an explicit `decide_open` adoption policy (silent newest-session
auto-adoption is now a warning + `f` to force). The app dispatches generically,
retains created-but-unopened sessions, keeps launch-to-create pendings in memory
(removed only on confirmed window death; not persisted until Stage 3), and
retains last snapshot on failed refresh while keeping first-reconcile
eligibility. 25 tests pass; the App event loop itself is not unit-tested (it
reads/writes the real opened.json and drives a real launcher) — the seams and
policy it calls are. Stage 3 (generic views/config + stable tracking migration)
is out of scope.
