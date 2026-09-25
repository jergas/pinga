# PA-01 Stage 3 — second review / remaining corrections

2026-09-22. CHANGES REQUESTED. Same DeepSeek session on High. This narrows
the first review; preserve resolved changes. No Stage 4 or live deployment.

Baseline 74 tests, check, all-target clippy, fidelity and whitespace pass.
Migration now derives backup and records from one byte snapshot; envelope
validation and conditional updates are improved. Remaining work below is not
covered by passing test names.

Architect directly fixed in blueprint (preserve): directory open/sync failures
now propagate for backup and v2 writes; missing/unreadable Codex source metadata
is Unknown even for default home; Up/Down with zero providers no longer indexes
an empty view; refreshing the new-session row no longer selects the first
session. Regression assertions were added for the last three behaviors.

## A / P1 — snapshot ordering and actual interleaving tests

Refresh lists providers BEFORE reconcile reads the tracking snapshot. A second
instance can create and record a session after listing but before that read;
the new record is then included in observed and deleted against an older list.
The equality guard only protects changes AFTER that read. Capture the records
before acquiring the listing/evidence used to reconcile them, or otherwise
explicitly defer records not covered by the refresh generation. Preserve those
added both during provider listing and between inspection and commit.

Seed startup eligibility from construction-time initial records, not all records
found by a later first reconcile. Later additions must never inherit it. Retain
eligibility for same-ID records whose conditional plan was skipped after a
concurrent change; only report removals actually applied. Current gone/still
come from proposed plans, regardless of whether equality checks skipped them.

`reconcile_preserves_records_replaced_by_another_store` runs one refresh, changes
the store, then runs a fresh refresh with failed inspection. It never interleaves
replacement between inspection and commit, so it does not test the guard.
Use deterministic hooks/barriers and real file stores to test both race windows,
including a record not present in the earlier successful provider listing.
Add failed commit -> recovery eligibility assertions and same-ID state changes.

## B / P1 — retain launched-but-unrecorded identity; test actual retries

spawn_launch now names the created window in its error but stores no local
launch record on failure. Retry can still create another window. The test named
no_blind_retry never retries or checks a launch counter. Keep an explicit local
unrecorded-launch state with provider, known key or pending identity, and window.
Retry recording that existing window without spawning another. Preserve it
through store read/refresh failure, handle confirmed death and unknown liveness,
and remove it only after successful recording or confirmed death. Show accurate
status: a launched window is not simply "could not be opened".

Tests must actually retry after persistent failure AND recovery, checking create,
spawn and tracking counters for Known and LaunchToCreate outcomes. This is an
in-memory recovery mechanism, not permission to mutate the live store.

## C / P2 — scrolling and selection still disagree with visible rows

`VISIBLE_ROWS` is a hardcoded viewport height. scroll is adjusted in selectable
session units but applied via visual_rows.skip(scroll), which includes headers.
sel_row resets to zero after skipping. A fresh ListState can then auto-scroll
again, beyond the offset used by hit testing. Multi-line items also mean one
visual item is not one terminal row. This remains wrong on short/long terminals.

Use one authoritative per-view layout/scroll mapping based on actual inner
height and rendered item heights. Drawing, selection highlight and mouse clicks
must share it; do not invent ratatui API limitations without inspecting the
installed dependency. Preserve selection AFTER reconcile/compute_running can
change grouping, not only before those calls. Test long lists with headers,
two-line and one-line rows, several terminal sizes, scrolling then clicking,
provider viewport changes and interrupted/running regrouping.

## D / P2 — faithful fixtures, source evidence and missing regression cases

MemStore still clones under a lock, drops it during mutation and relocks to
commit. next_id is recomputed from current records, so deleting the highest ID
allows reuse. Store an Envelope behind the shared mutex and keep the lock over
read-modify-write, retaining next_id across deletion. Test actual concurrent
updates, delete-all/add, and overflow; don't claim parity from basic CRUD.

Codex source comparison still treats every non-identical string as Different.
Relative CODEX_HOME (including an empty value), unsupported/nonrepresentable
paths, and unverified equivalent-path spellings must not prove another source.
Use a conservatively validated comparison; return Unknown when distinction is
not established. Launch plans must reject non-UTF-8 configured home rather than
silently to_string_lossy. Record the read-only evidence used to verify the
installed harness's CODEX_HOME interface as requested in the first packet.

The new batch adds tests but still lacks the requested terminal preparation/
combined cleanup failures, delayed-list creation retention and retry, actual
malformed OpenCode argv -> app reconciliation, unsupported action guards before
side effects, pending ambiguous/incomplete/disabled/failed-list sequences, and
config FILE loading/env precedence. Restore these against the real orchestration.
Tests named for these behaviors must perform the relevant actions and assertions.

## Delivery

Finish A–D in one batch via blueprint, then update the report honestly. Remove
contradictory historical claims (e.g. cached reads returned as success), label
legacy memory notes and update v2 behavior. Preserve architect fixes. Run all
gates including all-target clippy and repeat-tangle fidelity. Return for review;
do not treat a higher passing-test count as completion of the acceptance map.
