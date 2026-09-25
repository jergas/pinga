# Stage 3 closure and Antigravity integration spike

2026-09-22. Same DeepSeek/OpenCode session, High. User prioritizes reaching
Antigravity functionality testing with fewer architect round trips. Complete
both phases below in one batch; no intermediate approval needed for ordinary
reversible implementation. Stage 3 is NOT accepted yet. Pi remains unassigned.

Independent review: 78 tests, all-target clippy, repeat-tangle fidelity and
whitespace pass. Snapshot-before-listing and conditional-commit changes are
improved. The report explicitly leaves layout incomplete. Preserve all prior
architect fixes and complete the outstanding previous-review requirements.

## Phase A — finish the existing abstraction

1. Finish actual-height scrolling/mouse mapping from review-2 C. Remove fixed
   VISIBLE_ROWS assumptions. Headers, two-line items, highlighting, hit testing
   and resize must use the SAME mapping. Inspect installed ratatui source/API.
   Test clicking scrolled rows at short/tall sizes and after group changes.
   Do not return another partial layout implementation.
2. Fix launch recovery semantics. Current retry test repeatedly calls
   create_new_session; FakeProvider returns the SAME ID each time, masking
   duplicate native creation. A real API may return a different ID each time.
   Retry the retained SessionKey/window, never call create again. Test a fake
   that allocates distinct IDs and assert create count stays ONE across actual
   retry actions, persistent recording failure and recovery. Recovery must be
   reachable from the UI and bypass normal evidence/adoption refusal when it
   is only retrying persistence of the already-created window.
3. Pending recovery needs its own launch identity: current None==None matching
   conflates ALL unrecorded pending launches from one provider. Distinguish an
   explicit retry from an intentional second new launch; support two pending
   windows with different labels/directories. Check liveness at retry time;
   failed inspection retains the state, confirmed death must not be recorded
   as a successful live launch. Do not automatically recreate a known session.
4. Finish real interleaving tests: current replacement test still changes a
   shared store BETWEEN whole refreshes. Use deterministic barriers/hooks with
   file stores to add/replace during listing and between inspection/commit.
   Restore the outstanding behavioral cases from review-2 D, especially
   malformed real adapter evidence and pending uncertainty/failure sequences.
5. Removal notices must describe actual reasons. Current Applied::Removed
   counts intentional window closes and pending deaths as sessions deleted
   from the server. Carry the reason or use an accurate generic tracking notice.

Run all gates and write an accurate closure report. Keep this phase separately
reviewable in named blueprint chunks/prose before proceeding to Phase B.

## Phase B — Antigravity evidence, adapter prototype and testing

Identify the user's actual installed Antigravity product/version first. Inspect
local executable/help/package metadata and documented storage/CLI/API surfaces
read-only. Consult official upstream documentation as needed and record exact
sources/version/date. Do not infer functionality from the product name or
assume it behaves like Codex/OpenCode. Do not inspect credentials or copy private
conversation contents into fixtures/reports. Use synthetic fixtures.

Write docs/antigravity-integration.md mapping verified support for: session
enumeration, stable native IDs, source/profile separation, creation, resume of
an EXACT conversation, rename, activity evidence, and launch arguments. Mark
unsupported/unknown explicitly. Document what is an app/window launch versus
an actual conversation resume; do not conflate them.

If verified surfaces fit the accepted provider contract, implement an optional
compiled-in antigravity factory/adapter with explicit configuration, disabled
by absence from the default provider list. Use capabilities honestly. Unknown
activity stays Unknown; never attach by newest session or nonunique title.
Listing is the minimum: if even reliable listing/stable identity cannot be
established, deliver the evidence and exact blocker instead of fabricating an
adapter. No broad new plugin protocol or changes to core semantics to disguise
an unsupported surface. Document any contract extension proposal for review.

Exercise the adapter through generic app/config/tracking paths with synthetic
fixtures and recording launchers; test exact argv/source/identity, unsupported
operations, and failed/ambiguous evidence. A read-only live discovery/listing
smoke test is allowed if the verified interface does not mutate user data;
report only counts/redacted IDs, no conversation contents. Do not launch a
conversation, send prompts, rename sessions, install software, alter live
config/state, migrate live tracking, or deploy in this assignment.

Provide a concrete manual Antigravity functionality test checklist and the
exact opt-in config for subsequent user-controlled testing. Report what was
actually tested versus fixture-only/untested. No claim of full functionality
from successfully opening the application.

## Delivery

Blueprint is executable source; update adjacent prose. One writer, preserve
uncommitted work. Run tangle/check/test/lint plus all-target clippy, repeat
fidelity, diff whitespace. Update Stage 3 report, Antigravity integration report,
memory log and status pointer. Stop for architect review after this whole batch.
