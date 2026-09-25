# Antigravity prototype and Stage 3 closure — review

2026-09-23. CHANGES REQUESTED. Same High session, one focused correction
batch. No live launches, prompts, rename, initialization, installation or
deployment. The report says onboarding was completed; record who performed it
and whether it was separately user-authorized. Do not infer authorization from
the earlier read-only spike. No credentials/conversation contents in reports.

The optional agy adapter is useful progress, but is not ready for live testing.
Architect fixed three concrete issues directly through blueprint: collect
ANTIGRAVITY_APP_DATA_DIR alongside CODEX_HOME; open summary SQLite READ_ONLY;
propagate malformed row errors instead of silently skipping rows. Added a
malformed-row regression. Preserve these changes.

## 1. Finish the two core behaviors, with failing tests FIRST

- Scrolling remains broken. move_cursor uses full terminal last_height rather
  than column inner height, treats selectable index as visual index despite
  headers, and advances scroll only when its scan reaches rows.len(). A long
  list therefore lets selection leave the visible area. Derive one layout from
  actual inner geometry, visual item indices and line heights. Draw/highlight/
  hit-test from it; resize and group changes must recompute it. Add a long-list
  TestBackend test that moves below the viewport and clicks the visible selected
  row, with headers and two-line items, at short and tall sizes. Assert actual
  rendered text and dispatched SessionKey, not just stored offsets.
- Pending retry is still inferred from provider+label+cwd. Two intentional new
  launches can share all three. Assign a unique local launch token and expose
  an explicit retry action for that token; ordinary new always means new.
  Liveness error must retain the recovery state, not record a successful open.
  Test same-label/same-cwd distinct launches and explicit retries, including
  failed liveness and recording recovery. Keep known-key retry behavior.
- The interleaving test still edits between complete refreshes. Implement the
  previously assigned deterministic file-store interleaving tests; do not claim
  concurrency coverage without exercising the conflicting timing.

## 2. Antigravity parsing and evidence

- first_workspace returns file:// URIs verbatim as cwd, and guesses comma
  splitting which corrupts valid paths. Establish the actual encoding from
  authoritative source or a separately authorized sample. Parse supported forms
  properly (including URI decoding); unknown formats yield None, never a guessed
  launch directory. Synthetic fixtures must cover spaces, commas, escaped paths.
- parse_go_datetime_ms uses unchecked signed-to-unsigned arithmetic: pre-epoch
  dates can overflow, invalid dates are normalized, and fractional precision is
  mishandled. Use a validated parser/checked conversion; malformed or unsupported
  timestamps yield None without panic. Add invalid, pre-epoch, offset and
  fractional precision tests against the verified supported format.
- Treat inaccessible DB paths as errors, not fresh-install empty lists;
  distinguish NotFound from permission/inspection failure. Reject non-UTF-8
  source paths instead of lossy conversion. Verify launch env through the REAL
  collector → adapter → app path, not just manually populated ProcEvidence.
- Finding an env-var string in a binary does not prove directory override
  semantics. Record concrete evidence for that mapping, plain-agy creation,
  activity-vs-idle meaning, and exact-conversation resume. Label claims inferred
  from help/schema as inferred, and runtime-unverified behavior as untested.
  Use installed source/help or official docs; do not manufacture certainty from
  an empty database. No new live session is authorized by this packet.

## 3. Deliver an actual testing path

Add generic config/factory/app integration tests for Antigravity, two configured
homes and unsupported rename. Provide a COMPLETE opt-in config preserving the
existing OpenCode and Codex providers (an explicit provider list replaces defaults).
Provide a manual test checklist for new conversation, list refresh, exact resume,
second source isolation and pending state, with expected results and limitations.
Do not enable that config or run mutating smoke tests yourself.

Clean the completion report: contradictory 78/84 counts and historical partial
claims must not obscure final status. Map each above requirement to an actual
test/evidence item. Run all gates and repeat tangle. Update memory. Stop for
review with an honest completed/blocked status; no partial layout claim as done.
